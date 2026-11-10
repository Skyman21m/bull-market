import 'dart:convert';

import 'package:primitives/primitives.dart';
import 'package:robosats/src/coordinator/coordinator.dart';
import 'package:robosats/src/coordinator/coordinator_info.dart';
import 'package:robosats/src/coordinator/coordinator_transport.dart';
import 'package:robosats/src/coordinator/currency_limits.dart';
import 'package:robosats/src/coordinator/dropped_order_reason.dart';
import 'package:robosats/src/coordinator/order_book.dart';
import 'package:robosats/src/coordinator/order_values.dart';
import 'package:robosats/src/coordinator/read_bounds.dart';
import 'package:robosats/src/coordinator/robosats_currency.dart';
import 'package:robosats/src/coordinator/robosats_network.dart';
import 'package:robosats/src/robosats_failure.dart';

/// Reads the public endpoints of one coordinator at a time, through a [CoordinatorTransport].
///
/// Every method returns a [CoordinatorFailure] instead of throwing, whatever the coordinator sends and even if the transport throws an [Exception].
/// Methods are independent: call them concurrently, one future per coordinator.
final class CoordinatorClient {
  final CoordinatorTransport _transport;
  final DateTime Function() _clock;

  /// [clock] gives the time that rules out absurd order dates, the system clock by default.
  CoordinatorClient(this._transport, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// `GET /api/info/`, checked against the federation entry of [coordinator]: an identity mismatch is a [CoordinatorIdentityFailure].
  Future<Result<CoordinatorInfo, CoordinatorFailure>> fetchInfo(
    Coordinator coordinator,
    RobosatsNetwork network,
  ) async {
    final response = await _exchange(
      coordinator,
      network,
      '/api/info/',
      const {},
      CoordinatorReadBounds.infoBytes,
    );
    return switch (_decodeOk(response)) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => switch (CoordinatorInfo.parse(value)) {
        Err(:final failure) => Err(failure),
        Ok(value: final info) => coordinator.verifyIdentity(info, network),
      },
    };
  }

  /// `GET /api/book/`, the public orders of [coordinator], of one [currency] and one [type] when given.
  ///
  /// The official client sends no parameter, which is the same as asking for every currency and both types (`currency=0`, `type=2`).
  /// A coordinator with no order answers `404`, which gives an empty book.
  /// An order that does not match the filters is dropped with [DroppedOrderReason.filterMismatch].
  Future<Result<OrderBook, CoordinatorFailure>> fetchBook(
    Coordinator coordinator,
    RobosatsNetwork network, {
    RobosatsCurrency? currency,
    OrderType? type,
  }) async {
    final response = await _exchange(coordinator, network, '/api/book/', {
      if (currency != null) 'currency': '${currency.id}',
      if (type != null) 'type': '${type.wire}',
    }, CoordinatorReadBounds.bookBytes);
    if (response case Ok(value: CoordinatorResponse(statusCode: 404))) {
      return switch (_decode(response)) {
        Ok(value: final Map<String, Object?> body)
            when body.containsKey('not_found') =>
          Ok(OrderBook.empty(coordinator)),
        _ => const Err(CoordinatorUnexpectedStatus(404)),
      };
    }
    return switch (_decodeOk(response)) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => OrderBook.parse(
        value,
        coordinator,
        _clock(),
        currency: currency,
        type: type,
      ),
    };
  }

  /// `GET /api/limits/`, the market price of [coordinator] and its order size bounds in every currency.
  Future<Result<CurrencyLimits, CoordinatorFailure>> fetchLimits(
    Coordinator coordinator,
    RobosatsNetwork network,
  ) async {
    final response = await _exchange(
      coordinator,
      network,
      '/api/limits/',
      const {},
      CoordinatorReadBounds.limitsBytes,
    );
    return switch (_decodeOk(response)) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => CurrencyLimits.parse(value),
    };
  }

  Future<Result<CoordinatorResponse, CoordinatorFailure>> _exchange(
    Coordinator coordinator,
    RobosatsNetwork network,
    String path,
    Map<String, String> query,
    int maxResponseBytes,
  ) async {
    final onion = coordinator.origins(network).onion;
    if (onion == null) return const Err(CoordinatorNotOnNetwork());
    final request = CoordinatorRequest(
      method: CoordinatorHttpMethod.get,
      url: Uri.parse(
        onion,
      ).replace(path: path, queryParameters: query.isEmpty ? null : query),
      headers: const {'Accept': 'application/json'},
      maxResponseBytes: maxResponseBytes,
    );
    final Result<CoordinatorResponse, CoordinatorTransportFailure> result;
    try {
      result = await _transport.send(request);
    } on Exception {
      // The adapter should map every failure itself; one it lets through stays confined to this coordinator.
      return const Err(CoordinatorTransportFailed());
    }
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(value: final response) when response.body.length > maxResponseBytes =>
        const Err(CoordinatorResponseTooLarge()),
      Ok(value: final response) => Ok(response),
    };
  }

  /// The decoded JSON of a `200` answer.
  static Result<Object?, CoordinatorFailure> _decodeOk(
    Result<CoordinatorResponse, CoordinatorFailure> response,
  ) => switch (response) {
    Ok(value: CoordinatorResponse(statusCode: 200)) => _decode(response),
    Ok(value: CoordinatorResponse(:final statusCode)) => Err(
      CoordinatorUnexpectedStatus(statusCode),
    ),
    Err(:final failure) => Err(failure),
  };

  /// The decoded JSON of an answer whatever its status: a JSON content type, UTF-8 and a body that parses.
  static Result<Object?, CoordinatorFailure> _decode(
    Result<CoordinatorResponse, CoordinatorFailure> response,
  ) {
    final CoordinatorResponse value;
    switch (response) {
      case Err(:final failure):
        return Err(failure);
      case Ok(value: final ok):
        value = ok;
    }
    final contentType = value.contentType?.toLowerCase().trim();
    if (contentType == null ||
        !(contentType == 'application/json' ||
            contentType.startsWith('application/json;'))) {
      return const Err(CoordinatorNotJson());
    }
    try {
      return Ok(jsonDecode(utf8.decode(value.body)));
    } on FormatException {
      return const Err(CoordinatorNotJson());
    }
  }
}
