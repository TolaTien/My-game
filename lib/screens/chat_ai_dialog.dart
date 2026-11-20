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
  final List<ChatAiMessage> _messages = [
    ChatAiMessage(
      sender: 'ai',
      text:
          'Xin chào Chiến Binh! Tôi là **Trợ Lý AI Big-War** 🤖.\nBạn muốn hỏi về **Level Nhân vật 1–100**, **Đổi 1 Xu = 1000 Vàng**, **Kết bạn lập đội PvP 2v2/4v4**, hay **Cách thêm Assets tùy chỉnh**?',
      timestamp: DateTime.now(),
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendPrompt(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    AudioService.instance.playSfx(SfxSound.uiClick);
    final reply = ChatAiAssistantService.instance.generateReply(trimmed);

    setState(() {
      _messages.add(
        ChatAiMessage(
          sender: 'user',
          text: trimmed,
          timestamp: DateTime.now(),
        ),
      );
      _messages.add(
        ChatAiMessage(
          sender: 'ai',
          text: reply,
          timestamp: DateTime.now(),
        ),
      );
      _controller.clear();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
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
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TRỢ LÝ AI BIG-WAR (FAQ & HƯỚNG DẪN)',
                          style: TextStyle(
                            color: Colors.cyanAccent,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.1,
                          ),
                        ),
                        Text(
                          'Hỏi đáp nhanh về cơ chế game, Level 1-100, PvP Team & tùy chỉnh Assets',
                          style: TextStyle(color: Colors.white60, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            // Quick FAQ Chips
            SizedBox(
              height: 34,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: ChatAiAssistantService.faqTopics.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, idx) {
                  final topic = ChatAiAssistantService.faqTopics[idx];
                  return ActionChip(
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
                    onPressed: () => _sendPrompt(topic.prompt),
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
                  itemCount: _messages.length,
                  itemBuilder: (context, idx) {
                    final msg = _messages[idx];
                    final isUser = msg.sender == 'user';
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
                                : Colors.cyanAccent.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Text(
                          msg.text,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            height: 1.4,
                          ),
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
                      height: 38,
                      child: TextField(
                        controller: _controller,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        onSubmitted: _sendPrompt,
                        decoration: InputDecoration(
                          hintText:
                              'Nhập câu hỏi (VD: level 100, đổi xu, mời bạn bè 2v2, thêm asset)...',
                          hintStyle: const TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.07),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
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
                      backgroundColor: Colors.cyanAccent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    onPressed: () => _sendPrompt(_controller.text),
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: const Text(
                      'GỬI',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
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
