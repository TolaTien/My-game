import 'dart:async';

import 'package:flutter/material.dart';
import '../services/audio_service.dart';
import '../services/chat_ai_assistant_service.dart';

class ChatAiDialog extends StatefulWidget {
  const ChatAiDialog({super.key});

  @override
  State<ChatAiDialog> createState() => _ChatAiDialogState();
}

class _ChatAiDialogState extends State<ChatAiDialog> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  bool _isStreamingText = false;
  int? _streamingMessageIndex;

  StreamSubscription<String>? _streamSub;
  Timer? _typewriterTimer;
  final List<int> _pendingRunes = <int>[];
  bool _upstreamCompleted = false;
  String _currentStreamBuffer = '';

  final List<ChatAiMessage> _messages = [
    ChatAiMessage(
      sender: 'ai',
      text:
          'Xin chào Chiến Binh! Tôi là **Trợ Lý AI Big-War** 🤖.\nBạn muốn hỏi về **Level Nhân vật 1–100**, **Đổi 1 Xu = 1000 Vàng**, **Kết bạn lập đội PvP 2v2/4v4**, hay bất kỳ mẹo chiến đấu nào?',
      timestamp: DateTime.now(),
    ),
  ];

  @override
  void dispose() {
    _cancelActiveStream();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _cancelActiveStream() {
    _streamSub?.cancel();
    _streamSub = null;
    _typewriterTimer?.cancel();
    _typewriterTimer = null;
    _pendingRunes.clear();
  }

  static bool _isCombiningOrEmojiModifier(int rune) {
    return rune == 0xFE0F ||
        rune == 0x20E3 ||
        rune == 0x200D ||
        (rune >= 0x0300 && rune <= 0x036F) ||
        (rune >= 0x1F3FB && rune <= 0x1F3FF);
  }

  void _scrollToBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (jump) {
        _scrollController.jumpTo(target);
      } else {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _ensureTypewriterRunning() {
    if (_typewriterTimer != null) return;

    _typewriterTimer = Timer.periodic(
      const Duration(milliseconds: 18),
      (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        if (_pendingRunes.isEmpty) {
          if (_upstreamCompleted) {
            timer.cancel();
            _typewriterTimer = null;
            setState(() {
              _isLoading = false;
              _isStreamingText = false;
              _streamingMessageIndex = null;
            });
            _scrollToBottom();
          }
          return;
        }

        final backlog = _pendingRunes.length;
        final baseStep = backlog > 240
            ? 14
            : backlog > 120
                ? 8
                : backlog > 45
                    ? 4
                    : 2;

        final chunkRunes = <int>[];
        var count = 0;
        while (_pendingRunes.isNotEmpty &&
            (count < baseStep ||
                _isCombiningOrEmojiModifier(_pendingRunes.first))) {
          chunkRunes.add(_pendingRunes.removeAt(0));
          count++;
        }

        _currentStreamBuffer += String.fromCharCodes(chunkRunes);

        setState(() {
          if (_streamingMessageIndex == null) {
            _messages.add(
              ChatAiMessage(
                sender: 'ai',
                text: _currentStreamBuffer,
                timestamp: DateTime.now(),
              ),
            );
            _streamingMessageIndex = _messages.length - 1;
            _isStreamingText = true;
          } else {
            final idx = _streamingMessageIndex!;
            _messages[idx] = ChatAiMessage(
              sender: 'ai',
              text: _currentStreamBuffer,
              timestamp: _messages[idx].timestamp,
            );
          }
        });

        _scrollToBottom(jump: true);
      },
    );
  }

  Future<void> _sendPrompt(
    String text, {
    bool preferInstantFaq = false,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isLoading) return;

    AudioService.instance.playSfx(SfxSound.uiClick);
    _cancelActiveStream();

    final isProxyReady = ChatAiAssistantService.instance.isProxyConfigured;
    final historySnapshot = List<ChatAiMessage>.from(_messages);

    _currentStreamBuffer = '';
    _upstreamCompleted = false;
    _streamingMessageIndex = null;

    setState(() {
      _messages.add(
        ChatAiMessage(
          sender: 'user',
          text: trimmed,
          timestamp: DateTime.now(),
        ),
      );
      _controller.clear();
      _isLoading = true;
      _isStreamingText = false;
    });
    _scrollToBottom();

    // Khi bấm nút gợi ý nhanh (hoặc chưa cấu hình Proxy) -> lấy FAQ offline rồi stream mượt ra khung chat
    if (preferInstantFaq || !isProxyReady) {
      final localReply =
          ChatAiAssistantService.instance.resolveLocalReply(trimmed) ??
              ChatAiAssistantService.instance.generateReply(trimmed);
      _pendingRunes.addAll(localReply.runes);
      _upstreamCompleted = true;
      _ensureTypewriterRunning();
      return;
    }

    // Khi đã cấu hình AI Proxy -> đọc luồng SSE thời gian thực từ Gemini
    final stream = ChatAiAssistantService.instance.streamReplyAsync(
      trimmed,
      history: historySnapshot,
      bypassKeywordFilter: true,
      bypassScopeFilter: true,
    );

    _streamSub = stream.listen(
      (delta) {
        if (!mounted || delta.isEmpty) return;
        _pendingRunes.addAll(delta.runes);
        _ensureTypewriterRunning();
      },
      onError: (_) {
        if (!mounted) return;
        if (_currentStreamBuffer.isEmpty && _pendingRunes.isEmpty) {
          final fallback =
              ChatAiAssistantService.instance.generateReply(trimmed);
          _pendingRunes.addAll(fallback.runes);
        }
        _upstreamCompleted = true;
        _ensureTypewriterRunning();
      },
      onDone: () {
        if (!mounted) return;
        if (_currentStreamBuffer.isEmpty && _pendingRunes.isEmpty) {
          final fallback =
              ChatAiAssistantService.instance.generateReply(trimmed);
          _pendingRunes.addAll(fallback.runes);
        }
        _upstreamCompleted = true;
        _ensureTypewriterRunning();
      },
    );
  }

  Widget _buildMessageRichText(
    String rawText, {
    required bool isUser,
    required bool showCursor,
  }) {
    final spans = <InlineSpan>[];
    final boldPattern = RegExp(r'\*\*(.+?)\*\*');
    var lastEnd = 0;

    for (final match in boldPattern.allMatches(rawText)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: rawText.substring(lastEnd, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(1),
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: isUser ? Colors.white : const Color(0xFFFFE082),
          ),
        ),
      );
      lastEnd = match.end;
    }

    if (lastEnd < rawText.length) {
      spans.add(TextSpan(text: rawText.substring(lastEnd)));
    }

    if (showCursor) {
      spans.add(
        const TextSpan(
          text: ' ▍',
          style: TextStyle(
            color: Colors.cyanAccent,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
    }

    return Text.rich(
      TextSpan(
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12.5,
          height: 1.42,
        ),
        children: spans,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isApiReady = ChatAiAssistantService.instance.isApiConfigured;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 430),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF151C2C), Color(0xFF0D111A)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.cyanAccent.withValues(alpha: 0.6),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.7),
              blurRadius: 24,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.cyanAccent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.smart_toy_rounded,
                      color: Colors.cyanAccent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'TRỢ LÝ AI BIG-WAR',
                              style: TextStyle(
                                color: Colors.cyanAccent,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.1,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isApiReady
                                    ? Colors.greenAccent.withValues(alpha: 0.15)
                                    : Colors.amberAccent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isApiReady
                                      ? Colors.greenAccent.withValues(alpha: 0.6)
                                      : Colors.amberAccent.withValues(alpha: 0.5),
                                ),
                              ),
                              child: Text(
                                isApiReady ? 'AI SERVER' : 'CHẾ ĐỘ DEMO',
                                style: TextStyle(
                                  color: isApiReady
                                      ? Colors.greenAccent
                                      : Colors.amberAccent,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Text(
                          'Hỏi đáp thông minh về cơ chế game, Level 1-100, PvP Team & mẹo chiến đấu',
                          style: TextStyle(color: Colors.white60, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Đóng hộp thoại Trợ lý AI',
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  ),
                ],
              ),
            ),

            // Quick FAQ Chips (vùng chạm >= 48dp đạt chuẩn trợ năng)
            SizedBox(
              height: 48,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: ChatAiAssistantService.faqTopics.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, idx) {
                  final topic = ChatAiAssistantService.faqTopics[idx];
                  return ActionChip(
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    backgroundColor: const Color(0xFF1E293B),
                    side: BorderSide(
                      color: Colors.amberAccent.withValues(alpha: 0.45),
                    ),
                    label: Text(
                      topic.label,
                      style: const TextStyle(
                        color: Colors.amberAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: _isLoading
                        ? null
                        : () => _sendPrompt(
                              topic.prompt,
                              preferInstantFaq: true,
                            ),
                  );
                },
              ),
            ),

            const SizedBox(height: 8),

            // Chat History
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: ListView.builder(
                  controller: _scrollController,
                  itemCount: _messages.length +
                      ((_isLoading && !_isStreamingText) ? 1 : 0),
                  itemBuilder: (context, idx) {
                    if (_isLoading &&
                        !_isStreamingText &&
                        idx == _messages.length) {
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.cyanAccent.withValues(alpha: 0.25),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.cyanAccent,
                                ),
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Trợ lý AI đang suy nghĩ...',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    final msg = _messages[idx];
                    final isUser = msg.sender == 'user';
                    final isActivelyStreaming =
                        _isStreamingText && idx == _streamingMessageIndex;
                    return Align(
                      alignment:
                          isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 5),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        constraints: const BoxConstraints(maxWidth: 520),
                        decoration: BoxDecoration(
                          color: isUser
                              ? const Color(0xFF0284C7)
                              : const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isUser
                                ? Colors.lightBlueAccent
                                : Colors.cyanAccent.withValues(
                                    alpha: isActivelyStreaming ? 0.55 : 0.25,
                                  ),
                          ),
                        ),
                        child: _buildMessageRichText(
                          msg.text,
                          isUser: isUser,
                          showCursor: isActivelyStreaming,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // Input Row
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: TextField(
                        controller: _controller,
                        enabled: !_isLoading,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        onSubmitted: _sendPrompt,
                        decoration: InputDecoration(
                          hintText:
                              'Nhập câu hỏi về game Big-War...',
                          hintStyle: const TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.07),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Colors.white24),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(88, 48),
                      backgroundColor: Colors.cyanAccent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onPressed:
                        _isLoading ? null : () => _sendPrompt(_controller.text),
                    icon: _isLoading
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black54,
                            ),
                          )
                        : const Icon(Icons.send_rounded, size: 16),
                    label: Text(
                      _isLoading ? 'ĐANG GỬI' : 'GỬI',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
