import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/src/coordinator/robot_session_key.dart';
import 'package:robosats/src/robosats_failure.dart';

/// The HTTP methods the RoboSats API uses.
enum CoordinatorHttpMethod { get, post, put, delete }

/// One HTTP request to a coordinator, built by this package.
@immutable
final class CoordinatorRequest {
  final CoordinatorHttpMethod method;

  /// The absolute URL: the onion origin of the coordinator, the path and the query.
  final Uri url;

  /// The request headers, which never include a `User-Agent`: the adapter chooses it.
  ///
  /// An authenticated request carries the credential of its robot in `Authorization`: never log the headers.
  final Map<String, String> headers;

  final Uint8List? body;

  /// The largest body this request accepts, in bytes: the adapter must stop reading and fail with [CoordinatorResponseTooLarge] before buffering more.
  final int maxResponseBytes;

  /// The robot this request is made for, or `null` for an anonymous request, such as the read of a book.
  ///
  /// The adapter must never let two requests with different values, `null` included, share a connection or a Tor circuit: a coordinator, or anyone watching it, would otherwise tie a robot to another robot or to the anonymous reads of the same device.
  final RobotSessionKey? robot;

  const CoordinatorRequest({
    required this.method,
    required this.url,
    required this.headers,
    required this.maxResponseBytes,
    this.body,
    this.robot,
  });

  /// The method and the path, which are public: requests in this package carry no credential in the URL, and the headers and the robot are left out.
  @override
  String toString() =>
      'CoordinatorRequest(${method.name.toUpperCase()} ${url.path})';
}

/// The response of a coordinator, as the adapter received it.
@immutable
final class CoordinatorResponse {
  final int statusCode;

  /// The response headers, with names in lowercase as the adapter must give them: at least `content-type` when the coordinator sent one.
  final Map<String, String> headers;

  final Uint8List body;

  const CoordinatorResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  /// The `Content-Type` header, or `null` when the coordinator sent none.
  String? get contentType => headers['content-type'];

  /// The status and the body size only: the body is coordinator text.
  @override
  String toString() => 'CoordinatorResponse($statusCode, ${body.length} bytes)';
}

/// Performs one HTTP request to a coordinator: the port this package needs and never implements.
///
/// The Tor-backed adapter lives in `features/p2p`: it owns the Tor sessions, the retries and the `User-Agent`.
/// Its contract, which this package relies on:
/// - it must always complete, with an [Ok] or an [Err]: never throw, never leave the future pending;
/// - it must enforce a total deadline on the whole exchange, connection and body included, and fail with [CoordinatorTimedOut] when it passes, since a coordinator can send its body a byte at a time;
/// - it must stop reading a body at [CoordinatorRequest.maxResponseBytes] and fail with [CoordinatorResponseTooLarge] before buffering more;
/// - it must give header names in lowercase;
/// - it must not follow redirects;
/// - it must keep the requests of each [CoordinatorRequest.robot] on connections and Tor circuits of their own, per coordinator, apart from those of every other robot and from the anonymous requests, and refuse a request that carries an `Authorization` header without naming its robot;
/// - it must never log or keep the headers of a request, which may hold a credential;
/// - when its own limits leave no connection for a request for now, it fails with [CoordinatorTransportBusy] and with nothing else, so that a caller can tell a request to send again later from a coordinator that does not work;
/// - it maps everything else that goes wrong into a [CoordinatorTransportFailure].
///
/// Calls may run concurrently, one per coordinator and per robot.
abstract interface class CoordinatorTransport {
  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> send(
    CoordinatorRequest request,
  );
}
