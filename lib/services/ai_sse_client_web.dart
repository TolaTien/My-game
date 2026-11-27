import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

@JS('fetch')
external JSPromise<_JSResponse> _jsFetch(JSString url, _JSRequestInit init);

extension type _JSRequestInit._(JSObject _) implements JSObject {
  external factory _JSRequestInit({
    JSString method,
    JSObject headers,
    JSString body,
    JSObject? signal,
  });
}

@JS('Headers')
extension type _JSHeaders._(JSObject _) implements JSObject {
  external factory _JSHeaders();
  external void append(JSString name, JSString value);
}

@JS('AbortController')
extension type _JSAbortController._(JSObject _) implements JSObject {
  external factory _JSAbortController();
  external JSObject get signal;
  external void abort();
}

extension type _JSResponse._(JSObject _) implements JSObject {
  external bool get ok;
  external int get status;
  external _JSReadableStream? get body;
}

extension type _JSReadableStream._(JSObject _) implements JSObject {
  external _JSReadableStreamReader getReader();
}

extension type _JSReadableStreamReader._(JSObject _) implements JSObject {
  external JSPromise<_JSReadResult> read();
  external JSPromise<JSAny?> cancel();
}

extension type _JSReadResult._(JSObject _) implements JSObject {
  external bool get done;
  external JSUint8Array? get value;
}

Stream<String> postSseLinesImpl({
  required Uri uri,
  required String jsonBody,
  required Duration timeout,
  http.Client? client,
}) async* {
  // Nếu truyền MockClient trong unit test thì dùng đường http.Client chuẩn
  if (client != null) {
    final request = http.Request('POST', uri)
      ..headers['Content-Type'] = 'application/json; charset=utf-8'
      ..headers['Accept'] = 'text/event-stream'
      ..body = jsonBody;
    final streamedResponse = await client.send(request).timeout(timeout);
    if (streamedResponse.statusCode < 200 ||
        streamedResponse.statusCode >= 300) {
      throw http.ClientException(
        'SSE HTTP ${streamedResponse.statusCode}',
        uri,
      );
    }
    yield* streamedResponse.stream
        .timeout(timeout)
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    return;
  }

  final abortCtrl = _JSAbortController();
  Timer? timeoutTimer = Timer(timeout, () => abortCtrl.abort());

  final headers = _JSHeaders()
    ..append('Content-Type'.toJS, 'application/json; charset=utf-8'.toJS)
    ..append('Accept'.toJS, 'text/event-stream'.toJS);

  final init = _JSRequestInit(
    method: 'POST'.toJS,
    headers: headers,
    body: jsonBody.toJS,
    signal: abortCtrl.signal,
  );

  _JSReadableStreamReader? reader;
  final utf8Buffer = StringBuffer();
  final byteSink = ByteConversionSink.withCallback((chunk) {
    // Không dùng trực tiếp vì ta giải mã từng mảnh bằng Utf8Decoder cho phép ký tự nhiều byte bị cắt ngang
  });
  byteSink.close();

  final controller = StreamController<List<int>>();
  final lineQueue = <String>[];
  String carryOver = '';

  final utf8Sub = controller.stream.transform(utf8.decoder).listen((decoded) {
    final combined = carryOver + decoded;
    final parts = combined.split('\n');
    carryOver = parts.removeLast();
    for (final p in parts) {
      lineQueue.add(p.endsWith('\r') ? p.substring(0, p.length - 1) : p);
    }
  });

  try {
    final resp = await _jsFetch(uri.toString().toJS, init).toDart;
    if (!resp.ok) {
      throw http.ClientException('SSE HTTP ${resp.status}', uri);
    }
    final body = resp.body;
    if (body == null) {
      throw http.ClientException('Empty SSE stream body', uri);
    }

    reader = body.getReader();
    while (true) {
      timeoutTimer?.cancel();
      timeoutTimer = Timer(timeout, () => abortCtrl.abort());

      final chunk = await reader.read().toDart;
      if (chunk.done) break;

      final jsBytes = chunk.value;
      if (jsBytes != null) {
        final Uint8List bytes = jsBytes.toDart;
        controller.add(bytes);
        // Cho phép stream utf8.decoder xử lý microtask ngay lập tức
        await Future<void>.delayed(Duration.zero);
        while (lineQueue.isNotEmpty) {
          yield lineQueue.removeAt(0);
        }
      }
    }

    await controller.close();
    await utf8Sub.asFuture<void>();
    if (carryOver.isNotEmpty) {
      utf8Buffer.write(
        carryOver.endsWith('\r')
            ? carryOver.substring(0, carryOver.length - 1)
            : carryOver,
      );
      yield utf8Buffer.toString();
    }
    while (lineQueue.isNotEmpty) {
      yield lineQueue.removeAt(0);
    }
  } finally {
    timeoutTimer?.cancel();
    await utf8Sub.cancel();
    if (!controller.isClosed) {
      await controller.close();
    }
    if (reader != null) {
      try {
        await reader.cancel().toDart;
      } catch (_) {}
    }
  }
}
