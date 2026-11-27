import 'package:http/http.dart' as http;

import 'ai_sse_client_io.dart'
    if (dart.library.js_interop) 'ai_sse_client_web.dart' as impl;

/// Mở kết nối POST đọc luồng Server-Sent Events (SSE) theo từng dòng thời gian thực
/// trên cả Mobile/Desktop (`dart:io`) lẫn Trình duyệt Web (`fetch` ReadableStream).
Stream<String> postSseLines({
  required Uri uri,
  required String jsonBody,
  required Duration timeout,
  http.Client? client,
}) {
  return impl.postSseLinesImpl(
    uri: uri,
    jsonBody: jsonBody,
    timeout: timeout,
    client: client,
  );
}
