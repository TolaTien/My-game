import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

Stream<String> postSseLinesImpl({
  required Uri uri,
  required String jsonBody,
  required Duration timeout,
  http.Client? client,
}) async* {
  final httpClient = client ?? http.Client();
  final shouldClose = client == null;

  try {
    final request = http.Request('POST', uri)
      ..headers['Content-Type'] = 'application/json; charset=utf-8'
      ..headers['Accept'] = 'text/event-stream'
      ..body = jsonBody;

    final streamedResponse = await httpClient.send(request).timeout(timeout);
    if (streamedResponse.statusCode < 200 ||
        streamedResponse.statusCode >= 300) {
      throw http.ClientException(
        'SSE HTTP ${streamedResponse.statusCode}',
        uri,
      );
    }

    final lineStream = streamedResponse.stream
        .timeout(timeout)
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in lineStream) {
      yield line;
    }
  } finally {
    if (shouldClose) {
      httpClient.close();
    }
  }
}
