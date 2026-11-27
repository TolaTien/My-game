import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_game/core/env_config.dart';
import 'package:my_game/firebase_options.dart';
import 'package:my_game/services/chat_ai_assistant_service.dart';

void main() {
  tearDown(EnvConfig.clearTestOverrides);

  group('EnvConfig & ChatAiAssistantService (AI Proxy + Demo Mode)', () {
    test('has no hardcoded Firebase or AI API keys by default', () {
      EnvConfig.clearTestOverrides();
      expect(EnvConfig.firebaseApiKey, isEmpty);
      expect(EnvConfig.aiProxyUrl, isEmpty);
      expect(DefaultFirebaseOptions.isConfigured, isFalse);
    });

    test('loads non-secret runtime config without bundling API keys in client', () {
      EnvConfig.setTestOverrides({
        'AI_PROXY_URL': 'https://ai-proxy.example.com',
        'FIREBASE_API_KEY': 'fb_key_456',
        'FIREBASE_APP_ID_WEB': '1:123:web:abc',
        'FIREBASE_APP_ID_ANDROID': '1:123:android:def',
        'FIREBASE_DATABASE_URL': 'https://example-rtdb.firebasedatabase.app',
        'FIREBASE_PROJECT_ID': 'example-project',
        'FIREBASE_MESSAGING_SENDER_ID': '123456',
      });

      expect(EnvConfig.aiProxyUrl, 'https://ai-proxy.example.com');
      expect(DefaultFirebaseOptions.apiKey, 'fb_key_456');
      expect(DefaultFirebaseOptions.isConfigured, isTrue);
      expect(ChatAiAssistantService.instance.isProxyConfigured, isTrue);
    });

    test('matches keywords instantly (including unaccented Vietnamese) without calling server', () async {
      EnvConfig.setTestOverrides({
        'AI_PROXY_URL': 'https://ai-proxy.example.com',
      });

      bool apiCalled = false;
      final mockClient = MockClient((_) async {
        apiCalled = true;
        return http.Response('{}', 200);
      });

      final reply = await ChatAiAssistantService.instance.generateReplyAsync(
        'cho hoi ty le doi xu vang trong game',
        client: mockClient,
      );

      expect(apiCalled, isFalse);
      expect(reply, contains('1 Xu = 1.000 Vàng'));
    });

    test('blocks off-topic questions at client without calling server (0 tokens)', () async {
      EnvConfig.setTestOverrides({
        'AI_PROXY_URL': 'https://ai-proxy.example.com',
      });

      bool apiCalled = false;
      final mockClient = MockClient((_) async {
        apiCalled = true;
        return http.Response('{}', 200);
      });

      final reply = await ChatAiAssistantService.instance.generateReplyAsync(
        'Hôm nay thời tiết Hà Nội thế nào, nấu phở bò ra sao?',
        client: mockClient,
      );

      expect(apiCalled, isFalse);
      expect(reply, ChatAiAssistantService.offTopicRefusalReply);
    });

    test('calls AI Proxy Server (/api/chat) without sending any API key from client', () async {
      EnvConfig.setTestOverrides({
        'AI_PROXY_URL': 'https://ai-proxy.example.com',
      });

      Uri? capturedUri;
      Map<String, String>? capturedHeaders;

      final mockClient = MockClient((request) async {
        capturedUri = request.url;
        capturedHeaders = request.headers;
        return http.Response(
          jsonEncode({
            'reply': 'Bạn nên giữ khoảng cách và dùng phím né đúng nhịp trong Big-War.',
            'model': 'gemini-flash-lite-latest',
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final reply = await ChatAiAssistantService.instance.generateReplyAsync(
        'Mình mới chơi game này, cho vài mẹo chiến thuật để leo rank nhanh?',
        client: mockClient,
      );

      expect(capturedUri.toString(), 'https://ai-proxy.example.com/api/chat');
      expect(capturedHeaders?.containsKey('x-goog-api-key'), isFalse);
      expect(reply, 'Bạn nên giữ khoảng cách và dùng phím né đúng nhịp trong Big-War.');
    });

    test('runs Demo Mode gracefully when AI_PROXY_URL is empty or server returns error', () async {
      EnvConfig.setTestOverrides({'AI_PROXY_URL': ''});
      expect(ChatAiAssistantService.instance.isProxyConfigured, isFalse);

      final demoReply = await ChatAiAssistantService.instance.generateReplyAsync(
        'Mẹo chiến thuật leo rank nhanh nhất trong Big-War?',
      );
      expect(demoReply, contains('Trợ Lý AI Big-War'));

      EnvConfig.setTestOverrides({
        'AI_PROXY_URL': 'https://ai-proxy.example.com',
      });
      final mockClient = MockClient((_) async => http.Response('error', 503));
      final fallbackReply = await ChatAiAssistantService.instance.generateReplyAsync(
        'Mẹo chiến thuật leo rank nhanh nhất trong Big-War?',
        client: mockClient,
      );
      expect(fallbackReply, contains('Trợ Lý AI Big-War'));
    });

    test('streams SSE chunks incrementally from /api/chat/stream', () async {
      EnvConfig.setTestOverrides({
        'AI_PROXY_URL': 'https://ai-proxy.example.com',
      });

      Uri? capturedUri;
      final mockClient = MockClient.streaming((request, _) async {
        capturedUri = request.url;
        final sseEvents = <List<int>>[
          utf8.encode(
            'data: ${jsonEncode({'delta': 'Hãy giữ vị trí ', 'model': 'gemini-3.5-flash-lite'})}\n\n',
          ),
          utf8.encode(
            'data: ${jsonEncode({'delta': 'sau cột đá để né đạn Boss!', 'model': 'gemini-3.5-flash-lite'})}\n\n',
          ),
          utf8.encode('data: [DONE]\n\n'),
        ];
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable(sseEvents),
          200,
          headers: {'content-type': 'text/event-stream; charset=utf-8'},
        );
      });

      final chunks = await ChatAiAssistantService.instance
          .streamReplyAsync(
            'Tư vấn cách di chuyển sống sót tốt nhất?',
            client: mockClient,
            bypassKeywordFilter: true,
            bypassScopeFilter: true,
          )
          .toList();

      expect(
        capturedUri.toString(),
        'https://ai-proxy.example.com/api/chat/stream',
      );
      expect(chunks, ['Hãy giữ vị trí ', 'sau cột đá để né đạn Boss!']);
    });
  });
}
