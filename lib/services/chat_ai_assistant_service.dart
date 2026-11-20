import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/env_config.dart';

class ChatAiMessage {
  final String sender; // 'user' | 'ai'
  final String text;
  final DateTime timestamp;

  const ChatAiMessage({
    required this.sender,
    required this.text,
    required this.timestamp,
  });
}

class FaqTopic {
  final String id;
  final String label;
  final String prompt;
  final List<String> keywords;
  final String answer;

  const FaqTopic({
    required this.id,
    required this.label,
    required this.prompt,
    required this.keywords,
    required this.answer,
  });
}

/// Hệ thống Trợ Lý AI lai (Hybrid):
/// 1) Lọc từ khóa (Keyword Matching có dấu & không dấu) trả lời tức thì (<1ms).
/// 2) Gọi Gemini API (`gemini-flash-lite-latest` từ `.env`) cho câu hỏi mở.
class ChatAiAssistantService {
  ChatAiAssistantService._();
  static final ChatAiAssistantService instance = ChatAiAssistantService._();

  static const Duration _requestTimeout = Duration(seconds: 12);

  static const String offTopicRefusalReply =
      '🛡️ Mình là **Trợ Lý AI Big-War**, chỉ hỗ trợ giải đáp các câu hỏi liên quan đến tựa game **Big-War** '
      '(nhân vật, kỹ năng, cấp độ 1–100, PvP/PvE, Boss, tổ đội, kinh tế Xu/Vàng, trợ thủ, mẹo chiến đấu...).\n'
      'Bạn hãy đặt câu hỏi về game hoặc chọn nhanh các chủ đề gợi ý phía trên nhé!';

  /// Tập từ khóa phạm vi game (không dấu) để chặn câu hỏi ngoài lề ngay ở client (0 token)
  static const List<String> _gameScopeKeywords = [
    'big-war',
    'big war',
    'bigwar',
    'gold rush',
    'game',
    'tro choi',
    'choi',
    'huong dan',
    'cach choi',
    'meo',
    'chien thuat',
    'combo',
    'build',
    'tuong',
    'nhan vat',
    'hero',
    'george',
    'nova',
    'shadow',
    'ember',
    'lyra',
    'braum',
    'hayate',
    'ninja',
    'dau si',
    'xa thu',
    'sat thu',
    'phap su',
    'hiep si',
    'skill',
    'ky nang',
    'chieu',
    'ulti',
    'level',
    'lv',
    'cap',
    'exp',
    'kinh nghiem',
    'chi so',
    'hp',
    'mau',
    'nang luong',
    'atk',
    'suc danh',
    'sat thuong',
    'toc do',
    'huan luyen',
    'nang cap',
    'xu',
    'vang',
    'gold',
    'kim cuong',
    'shop',
    'cua hang',
    'quy doi',
    'doi xu',
    'doi vang',
    'pvp',
    'pve',
    '1v1',
    '2v2',
    '4v4',
    'dau truong',
    'ghep tran',
    'tran dau',
    'rank',
    'xep hang',
    'bang xep hang',
    'bxh',
    'rp',
    'ban be',
    'ket ban',
    'to doi',
    'party',
    'team',
    'ma id',
    'player code',
    'bot',
    'tro thu',
    'pet',
    'companion',
    'aegis',
    'tinh linh',
    'boss',
    'quai',
    'zombie',
    'skeleton',
    'vuot ai',
    'map',
    'ban do',
    'vong quay',
    'spin',
    'jackpot',
    'dieu khien',
    'phim tat',
    'joystick',
    'di chuyen',
    'tan cong',
    'ne don',
    'tai khoan',
    'dang nhap',
    'dang ky',
    'ho so',
    'cai dat',
    'am thanh',
    'asset',
    'sprite',
    'sanh cho',
    'lobby',
    'lag',
    'bug',
    'xin chao',
    'hello',
    'hi',
  ];

  static const List<FaqTopic> faqTopics = [
    FaqTopic(
      id: 'level_100',
      label: 'Cấp độ 1-100',
      prompt: 'Hệ thống Level 1 đến 100 của nhân vật hoạt động thế nào?',
      keywords: [
        'level',
        'lv',
        'cấp',
        'cap do',
        '100',
        'exp',
        'kinh nghiệm',
        'kinh nghiem',
        'tăng chỉ số',
        'tang chi so',
        'nâng cấp',
        'nang cap',
        'huấn luyện',
        'huan luyen',
      ],
      answer:
          '⚡ **Hệ thống Level Nhân Vật (1 → 100)**:\n'
          '• Mỗi nhân vật của bạn có cấp độ riêng từ **Level 1 đến Level 100**.\n'
          '• Sau mỗi trận đấu (PvE vượt ải hoặc PvP đấu trường), nhân vật vừa ra trận sẽ nhận được **EXP Thông Thạo**.\n'
          '• Mỗi khi lên cấp, nhân vật được cộng vĩnh viễn **HP, Ki (Năng lượng) và Sức Đánh (ATK)** theo đặc trưng hệ tướng (Đỡ đòn tăng nhiều HP, Sát thủ/Xạ thủ tăng mạnh Sức Đánh & Ki).\n'
          '• Ngoài ra, trong Cửa Hàng bạn cũng có thể dùng Vàng để **Huấn Luyện Nhanh** giúp nhân vật thăng cấp tức thì!',
    ),
    FaqTopic(
      id: 'economy_xu_gold',
      label: 'Quy đổi 1 Xu = 1000 Vàng',
      prompt: 'Tỷ lệ đổi Xu và Vàng trong game như thế nào?',
      keywords: [
        'xu',
        'vàng',
        'vang',
        'gold',
        'tiền',
        'tien',
        'đổi',
        'doi xu',
        '1000',
        'kinh tế',
        'kinh te',
        'cửa hàng',
        'cua hang',
        'shop',
      ],
      answer:
          '🪙 **Hệ thống Kinh Tế (1 Xu = 1000 Vàng)**:\n'
          '• Tỷ giá cố định trong Big-War là **1 Xu = 1.000 Vàng**.\n'
          '• Bạn có thể chuyển đổi 2 chiều giữa **Xu ↔ Vàng** ngay trong **Cửa Hàng (Tab Quy Đổi Xu/Vàng)** hoặc trên thanh tiền tệ ở Sảnh Chờ.\n'
          '• Vàng dùng để mở khóa Nhân vật, Trợ thủ AI và Huấn luyện cấp độ 1–100.',
    ),
    FaqTopic(
      id: 'friends_party_pvp',
      label: 'Kết bạn & Tổ đội PvP',
      prompt: 'Làm sao để kết bạn và mời bạn bè vào team chơi PvP 2v2, 4v4?',
      keywords: [
        'kết bạn',
        'ket ban',
        'bạn bè',
        'ban be',
        'mời bạn',
        'moi ban',
        'mời team',
        'moi team',
        'tổ đội',
        'to doi',
        'party',
        'pvp',
        '1v1',
        '2v2',
        '4v4',
        'ghép trận',
        'ghep tran',
        'đấu trường',
        'dau truong',
      ],
      answer:
          '🤝 **Kết Bạn & Mời Tổ Đội PvP (1v1 / 2v2 / 4v4)**:\n'
          '1. Nhấn nút **BẠN BÈ** ở Sảnh Chờ (Lobby).\n'
          '2. Nhập **Mã ID (Player Code)** của bạn bè (ví dụ: `GR8899`) hoặc chọn kết bạn từ danh sách gợi ý.\n'
          '3. Chuyển sang tab **Tổ Đội (Party)**, chọn chế độ **2v2 Song Đấu** hoặc **4v4 Quân Đoàn** rồi nhấn **Mời Vào Team** cạnh tên bạn bè (hoặc gửi Mã Phòng Tổ Đội cho bạn bè nhập).\n'
          '4. Khi nhấn **BẮT ĐẦU**, cả đội sẽ cùng vào Đấu Trường! Nếu hàng đợi quá 60s chưa đủ người thật, hệ thống tự động bù **AI Bot thông minh (A* + FSM)** để trận đấu diễn ra ngay.',
    ),
    FaqTopic(
      id: 'heroes_skills',
      label: 'Nhân vật & Kỹ năng',
      prompt: 'Giới thiệu các nhân vật và kỹ năng trong game?',
      keywords: [
        'nhân vật',
        'nhan vat',
        'tướng',
        'tuong',
        'hero',
        'george',
        'nova',
        'shadow',
        'ember',
        'lyra',
        'braum',
        'hayate',
        'ninja',
        'skill',
        'kỹ năng',
        'ky nang',
        'chiêu',
        'chieu',
      ],
      answer:
          '🗡️ **Hệ thống Nhân Vật & Bộ 3 Kỹ Năng**:\n'
          '• **George (Đấu Sĩ Búa)**: Búa Cuồng Phong (Xoay 360°), Nện Đất Chấn Động (Choáng AoE), Cơn Cuồng Nộ (+Tốc chạy & Sát thương).\n'
          '• **Nova Blade / Shadow / Ember**: Các chiến binh cao cấp với bộ chiêu năng lượng, ám sát và hỏa cầu diện rộng.\n'
          '• **Lyra (Xạ Thủ)**: Bắn tên tầm xa, Mưa Tên Tinh Tú, lộn nhào né đòn.\n'
          '• **Braum (Hiệp Sĩ Khiên)**: Máu cực trâu, Khiên Chấn Động, Pháo Đài Thép.\n'
          '• **Hayate (Ninja)**: Tốc độ cao nhất, Phi Tiêu Lướt Ảnh, Bom Khói, Ám Sát.',
    ),
    FaqTopic(
      id: 'companions',
      label: 'Trợ thủ AI bay',
      prompt: 'Trợ thủ AI bay có tác dụng gì?',
      keywords: [
        'trợ thủ',
        'tro thu',
        'pet',
        'companion',
        'aegis',
        'drone',
        'hút vàng',
        'hut vang',
        'tinh linh',
      ],
      answer:
          '🛸 **Hệ thống Trợ Thủ AI Bay**:\n'
          '• Bay lơ lửng theo quỹ đạo lò xo sau vai nhân vật, tự động bắn tia năng lượng và **tự động hút Vàng/Bình máu/Ngọc EXP**.\n'
          '• Có 4 loại trợ thủ: **Aegis-X9** (Gom quái + Tạo khiên + Thưởng 25% Vàng), **Hỏa Tinh Linh** (Công kích), **Thổ Linh** (Phòng ngự tạo khiên), **Băng Linh** (Khống chế làm chậm 50%).',
    ),
    FaqTopic(
      id: 'boss_pve',
      label: 'Mẹo đánh Boss',
      prompt: 'Mẹo vượt ải và đánh Boss hiệu quả?',
      keywords: [
        'boss',
        'quái',
        'quai',
        'vượt ải',
        'vuot ai',
        'pve',
        'zombie',
        'skeleton',
      ],
      answer:
          '👹 **Mẹo Vượt Ải & Đánh Boss**:\n'
          '• Quái Zombie và Boss sử dụng thuật toán **A* (A-Star)** để tìm đường vòng qua tường đá, còn Skeleton biết giữ khoảng cách bắn tỉa (Kiting AI).\n'
          '• Hãy tận dụng 4 khu vực cột đá chữ L ở góc bản đồ để chắn đạn của Skeleton & Boss, nhặt Ngọc EXP để lên cấp trong trận (tối đa Lv.15) và tung chiêu cuối khi Boss vừa kết thúc đợt lao tới!',
    ),
    FaqTopic(
      id: 'lucky_wheel',
      label: 'Vòng Quay May Mắn',
      prompt: 'Vòng quay may mắn hoạt động như thế nào?',
      keywords: [
        'vòng quay',
        'vong quay',
        'quay',
        'spin',
        'may mắn',
        'may man',
        'jackpot',
        'kim cương',
        'kim cuong',
      ],
      answer:
          '🎡 **Vòng Quay May Mắn**:\n'
          '• Mỗi ngày bạn có **1 lượt quay miễn phí**, tự động làm mới vào **00:00 UTC (07:00 sáng giờ Việt Nam)**.\n'
          '• Bạn cũng có thể dùng Kim Cương để quay thêm và săn giải **Jackpot 2.000 Vàng**!',
    ),
    FaqTopic(
      id: 'custom_assets',
      label: 'Thêm Assets tùy chỉnh',
      prompt: 'Làm sao để thêm file nhân vật, map, trợ thủ, skill mới vào game?',
      keywords: [
        'asset',
        'assets',
        'sprite',
        'png',
        'json',
        'tùy chỉnh',
        'tuy chinh',
        'thêm map',
        'them map',
      ],
      answer:
          '📁 **Cách Thêm Nhân Vật, Map, Trợ Thủ, Skill Từ Thư Mục `assets/`**:\n'
          '• Toàn bộ cấu hình được tách riêng trong `assets/data/` (`heroes.json`, `skills.json`, `companions.json`, `maps.json`, `enemies.json`).\n'
          '• Bạn chỉ cần chép file ảnh `.png` vào `assets/images/heroes/` (hoặc `maps/`, `companions/`, `skills/`) rồi thêm thông tin vào file `.json` tương ứng.\n'
          '• Hệ thống `GameAssetRegistry` sẽ tự động đọc và đưa thẳng vào game!',
    ),
  ];

  bool get isProxyConfigured => EnvConfig.aiProxyUrl.isNotEmpty;

  /// Giữ alias tương thích ngược cho UI/test
  bool get isApiConfigured => isProxyConfigured;

  /// Chuẩn hóa chuỗi tiếng Việt để lọc từ khóa chính xác (cả có dấu lẫn không dấu)
  static String _normalizeVietnamese(String input) {
    var s = input.toLowerCase();
    const replacements = <String, String>{
      'à': 'a', 'á': 'a', 'ạ': 'a', 'ả': 'a', 'ã': 'a',
      'â': 'a', 'ầ': 'a', 'ấ': 'a', 'ậ': 'a', 'ẩ': 'a', 'ẫ': 'a',
      'ă': 'a', 'ằ': 'a', 'ắ': 'a', 'ặ': 'a', 'ẳ': 'a', 'ẵ': 'a',
      'è': 'e', 'é': 'e', 'ẹ': 'e', 'ẻ': 'e', 'ẽ': 'e',
      'ê': 'e', 'ề': 'e', 'ế': 'e', 'ệ': 'e', 'ể': 'e', 'ễ': 'e',
      'ì': 'i', 'í': 'i', 'ị': 'i', 'ỉ': 'i', 'ĩ': 'i',
      'ò': 'o', 'ó': 'o', 'ọ': 'o', 'ỏ': 'o', 'õ': 'o',
      'ô': 'o', 'ồ': 'o', 'ố': 'o', 'ộ': 'o', 'ổ': 'o', 'ỗ': 'o',
      'ơ': 'o', 'ờ': 'o', 'ớ': 'o', 'ợ': 'o', 'ở': 'o', 'ỡ': 'o',
      'ù': 'u', 'ú': 'u', 'ụ': 'u', 'ủ': 'u', 'ũ': 'u',
      'ư': 'u', 'ừ': 'u', 'ứ': 'u', 'ự': 'u', 'ử': 'u', 'ữ': 'u',
      'ỳ': 'y', 'ý': 'y', 'ỵ': 'y', 'ỷ': 'y', 'ỹ': 'y',
      'đ': 'd',
    };
    replacements.forEach((k, v) {
      s = s.replaceAll(k, v);
    });
    return s;
  }

  static bool _containsWholePhrase(String text, String phrase) {
    final pattern = RegExp(
      '(^|[^a-z0-9])${RegExp.escape(phrase)}(\$|[^a-z0-9])',
    );
    return pattern.hasMatch(text);
  }

  /// Lọc từ khóa trong câu hỏi của user. Trả về `null` nếu không khớp chủ đề nào
  /// (để chuyển sang Gemini AI trả lời).
  String? matchKeywordReply(String rawQuery) {
    final query = rawQuery.trim().toLowerCase();
    if (query.isEmpty) return null;
    final normalizedQuery = _normalizeVietnamese(query);

    int bestScore = 0;
    FaqTopic? bestTopic;

    for (final topic in faqTopics) {
      int score = 0;
      for (final kw in topic.keywords) {
        final lowerKw = kw.toLowerCase();
        final normKw = _normalizeVietnamese(lowerKw);
        final isAccented = lowerKw != normKw;
        final matched = isAccented
            ? query.contains(lowerKw)
            : _containsWholePhrase(normalizedQuery, normKw);
        if (matched) {
          score += lowerKw.length >= 4 ? 3 : 2;
        }
      }
      if (score > bestScore) {
        bestScore = score;
        bestTopic = topic;
      }
    }

    if (bestTopic != null && bestScore >= 2) {
      return bestTopic.answer;
    }
    return null;
  }

  /// Kiểm tra câu hỏi có thuộc phạm vi game Big-War hay không.
  /// Nếu ngoài lề -> chặn ngay ở client để không tốn token Gemini API.
  bool isGameRelatedQuery(String rawQuery) {
    final normalized = _normalizeVietnamese(rawQuery.trim());
    if (normalized.isEmpty) return false;
    if (matchKeywordReply(rawQuery) != null) return true;

    for (final kw in _gameScopeKeywords) {
      if (_containsWholePhrase(normalized, kw)) {
        return true;
      }
    }
    return false;
  }

  /// Lọc tức thì ở client (<1ms, 0 token):
  /// - Trả về câu trả lời FAQ nếu khớp từ khóa game.
  /// - Trả về thông báo từ chối nếu câu hỏi nằm ngoài phạm vi game.
  /// - Trả về `null` nếu thuộc phạm vi game nhưng cần Gemini AI giải đáp chi tiết.
  String? resolveLocalReply(String rawQuery) {
    final trimmed = rawQuery.trim();
    if (trimmed.isEmpty) {
      return 'Bạn hãy nhập câu hỏi về game Big-War hoặc bấm vào các chủ đề gợi ý bên dưới nhé!';
    }
    final keywordReply = matchKeywordReply(trimmed);
    if (keywordReply != null) {
      return keywordReply;
    }
    if (!isGameRelatedQuery(trimmed)) {
      return offTopicRefusalReply;
    }
    return null;
  }

  /// Ưu tiên lọc từ khóa & giới hạn phạm vi ở client (<1ms, 0 token).
  /// Nếu đã cấu hình `AI_PROXY_URL`, gọi máy chủ proxy (khóa Gemini chỉ nằm trên server).
  /// Nếu chưa có server hoặc mất mạng, tự động chạy Chế độ Demo (FAQ offline).
  Future<String> generateReplyAsync(
    String rawQuery, {
    List<ChatAiMessage> history = const [],
    http.Client? client,
    bool bypassKeywordFilter = false,
  }) async {
    final trimmed = rawQuery.trim();
    if (trimmed.isEmpty) {
      return 'Bạn hãy nhập câu hỏi về game Big-War hoặc bấm vào các chủ đề gợi ý bên dưới nhé!';
    }

    // Bước 1: Lọc từ khóa & chặn câu hỏi ngoài lề ngay tại client (0 token)
    if (!bypassKeywordFilter) {
      final localReply = resolveLocalReply(trimmed);
      if (localReply != null) {
        return localReply;
      }
    } else if (!isGameRelatedQuery(trimmed)) {
      return offTopicRefusalReply;
    }

    // Bước 2: Gọi AI Proxy Server (khóa Gemini chỉ nằm ở server/ai_proxy/.env)
    final proxyBaseUrl = EnvConfig.aiProxyUrl.replaceAll(RegExp(r'/+$'), '');
    if (proxyBaseUrl.isEmpty) {
      return generateReply(trimmed);
    }

    final uri = Uri.parse('$proxyBaseUrl/api/chat');
    final recentHistory = history.length > 2
        ? history.sublist(history.length - 2)
        : history;

    final payload = <String, dynamic>{
      'message': trimmed,
      'history': [
        for (final msg in recentHistory)
          {
            'role': msg.sender == 'user' ? 'user' : 'model',
            'text': msg.text,
          },
      ],
    };

    final httpClient = client ?? http.Client();
    final shouldClose = client == null;

    try {
      final response = await httpClient
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode(payload),
          )
          .timeout(_requestTimeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes))
            as Map<String, dynamic>;
        final text = decoded['reply']?.toString().trim() ?? '';
        if (text.isNotEmpty) {
          return text;
        }
      } else {
        debugPrint(
          'ChatAiAssistantService: AI Proxy error ${response.statusCode}: ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('ChatAiAssistantService: AI Proxy request failed: $e');
    } finally {
      if (shouldClose) {
        httpClient.close();
      }
    }

    return generateReply(trimmed);
  }

  /// Trả lời offline hoàn toàn bằng Keyword Matching
  String generateReply(String rawQuery) {
    final trimmed = rawQuery.trim();
    if (trimmed.isEmpty) {
      return 'Bạn hãy nhập câu hỏi hoặc bấm vào các chủ đề gợi ý bên dưới nhé!';
    }

    final matched = matchKeywordReply(trimmed);
    if (matched != null) {
      return matched;
    }

    return '🤖 **Trợ Lý AI Big-War**:\n'
        'Mình có thể giải đáp cho bạn về:\n'
        '1️⃣ **Cấp độ Nhân vật (1 → 100)** & cộng chỉ số sau mỗi trận\n'
        '2️⃣ **Quy đổi Kinh tế** (`1 Xu = 1000 Vàng`)\n'
        '3️⃣ **Kết bạn & Mời tổ đội PvP** (1v1 / 2v2 / 4v4)\n'
        '4️⃣ **Kỹ năng Nhân vật & Trợ thủ AI bay**\n'
        '5️⃣ **Mẹo đánh Boss, Vòng Quay May Mắn & thêm Assets**\n\n'
        'Hãy nhấn vào các nút gợi ý nhanh phía trên hoặc gõ câu hỏi bất kỳ nhé!';
  }
}
