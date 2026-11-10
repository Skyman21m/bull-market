import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
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
  final Map<String, String> headers;

  final Uint8List? body;

  /// The largest body this request accepts: the adapter should stop reading beyond it and fail with [CoordinatorResponseTooLarge].
  final int maxResponseBytes;

  const CoordinatorRequest({
    required this.method,
    required this.url,
    required this.headers,
    required this.maxResponseBytes,
    this.body,
  });

  /// The method and the path, which are public: requests in this package carry no credential in the URL.
  @override
  String toString() =>
      'CoordinatorRequest(${method.name.toUpperCase()} ${url.path})';
}

/// The response of a coordinator, as the adapter received it.
@immutable
final class CoordinatorResponse {
  final int statusCode;

  /// The response headers this package reads, with lowercase names: at least `content-type` when the coordinator sent one.
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
/// The Tor-backed adapter lives in `features/p2p`: it owns the Tor sessions, the deadlines, the retries and the `User-Agent`, and maps everything that can go wrong into a [CoordinatorTransportFailure].
/// It must not follow redirects, and it should stop reading a body at [CoordinatorRequest.maxResponseBytes].
/// Calls may run concurrently, one per coordinator.
abstract interface class CoordinatorTransport {
  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> send(
    CoordinatorRequest request,
  );
}
