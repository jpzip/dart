import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Result of a raw GET. `body == null` indicates a 404.
class RawResponse {
  final Uint8List? body;
  final int statusCode;
  const RawResponse(this.body, this.statusCode);
}

/// GETs [url] with up to 3 attempts, exponential backoff on 5xx and network
/// errors. 404 is returned as `RawResponse(null, 404)` so callers can
/// distinguish "absent" from "fetch error".
Future<RawResponse> getRaw(http.Client client, String url) async {
  Object? lastErr;
  for (var attempt = 0; attempt < 3; attempt++) {
    if (attempt > 0) {
      final ms = 200 * (1 << attempt); // 400, 800
      await Future<void>.delayed(Duration(milliseconds: ms));
    }
    try {
      final resp = await client.get(
        Uri.parse(url),
        headers: const {'Accept': 'application/json'},
      );
      if (resp.statusCode == 404) {
        return const RawResponse(null, 404);
      }
      if (resp.statusCode >= 500) {
        lastErr = HttpStatusException(url, resp.statusCode);
        continue;
      }
      if (resp.statusCode >= 400) {
        throw HttpStatusException(url, resp.statusCode);
      }
      return RawResponse(resp.bodyBytes, resp.statusCode);
    } catch (e) {
      if (e is HttpStatusException && e.statusCode < 500) rethrow;
      lastErr = e;
    }
  }
  if (lastErr is Exception) throw lastErr;
  throw Exception('jpzip: fetch $url failed: ${lastErr ?? "unknown"}');
}

/// Thrown when the CDN returns a non-2xx, non-404 status that exhausted
/// retries (5xx) or that we surface immediately (4xx other than 404).
class HttpStatusException implements Exception {
  final String url;
  final int statusCode;
  const HttpStatusException(this.url, this.statusCode);

  @override
  String toString() => 'jpzip: $url returned $statusCode';
}
