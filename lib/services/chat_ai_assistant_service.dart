import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/env_config.dart';
import 'ai_sse_client.dart';

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
    'valeria',
    'garrick',
    'ranger',
    'tanker',
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
    'ki',
    'nang luong',
    'atk',
    'suc danh',
    'sat thuong',
    'toc do',
    'nang cap',
    'xu',
    'vang',
    'gold',
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
    'solo',
    'cuoc',
    'phong',
    'dau truong',
    'ghep tran',
    'tran dau',
    'rank',
    'sao rank',
    'thach dau',
    'huyen thoai',
    'kim cuong',
    'bach kim',
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
    'cyber',
    'luna',
    'orbit',
    'dragon',
    'rong',
    'drone',
    'tinh linh',
    'boss',
    'quai',
    'zombie',
    'skeleton',
    'vuot ai',
    'tang',
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
    'sanh cho',
    'lobby',
    'tan thu',
    'manh nhat',
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
      ],
      answer:
          '⚡ **Hệ thống Cấp Độ Nhân Vật (Lv.1 → Lv.100)**:\n'
          '• Mỗi nhân vật sở hữu cấp thông thạo riêng từ **Level 1 đến Level 100**.\n'
          '• Sau mỗi trận **PvE vượt tầng** hoặc **PvP Đấu Trường** (kể cả thắng hay thua), tướng vừa ra trận đều nhận được **EXP Thông Thạo**.\n'
          '• Mỗi khi lên cấp, tướng được cộng vĩnh viễn **HP, Ki và Sức Đánh (ATK)** theo đặc trưng hệ tướng.\n'
          '• Ngoài ra khi vào trận PvE, nhặt **Ngọc EXP** rơi từ quái sẽ giúp nhân vật lên cấp tạm thời trong trận (tối đa **Lv.15**)!',
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
          '🪙 **Hệ thống Kinh Tế (1 Xu = 1.000 Vàng)**:\n'
          '• Tỷ giá cố định trong Big-War là **1 Xu = 1.000 Vàng**.\n'
          '• Bấm vào nút **Xu** trong **Cửa Hàng** hoặc trên thanh tiền tệ ở **Sảnh Chờ** để đổi nhanh sang Vàng.\n'
          '• **Cách cày Xu & Vàng**: Nhặt Xu rơi trong trận PvE, quay **Vòng Quay May Mắn** mỗi ngày, vượt tầng PvE (`200 × số tầng` Vàng), hoặc chiến thắng PvP Rank & Phòng Solo.\n'
          '• Vàng dùng để mở khóa **Nhân vật mới (4.000 – 6.500 Vàng)** và **Trợ thủ AI (2.000 – 10.000 Vàng)**.',
    ),
    FaqTopic(
      id: 'friends_party_pvp',
      label: 'PvP Rank, Tổ đội & Solo',
      prompt: 'Làm sao để leo Rank PvP, mời bạn bè tổ đội 2v2/4v4 và tạo phòng Solo cược Vàng?',
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
        'solo',
        'cược vàng',
        'cuoc vang',
        'ghép trận',
        'ghep tran',
        'đấu trường',
        'dau truong',
      ],
      answer:
          '⚔️ **Đấu Trường PvP Rank, Tổ Đội & Phòng Solo**:\n'
          '• **Đấu Rank Bo3**: Gồm **1v1 Đấu Đơn** (+200 Vàng), **2v2 Song Đấu** (+350 Vàng), **4v4 Quân Đoàn** (+500 Vàng). Hệ thống gồm 7 bậc: **Đồng → Bạc → Vàng → Bạch Kim → Kim Cương** (3 sao/bậc) → **Huyền Thoại** (từ 15 sao) → **Thách Đấu (Top 10 Server)**.\n'
          '• **Kết Bạn & Tổ Đội**: Vào mục **Bạn Bè** nhập **Mã ID** để kết bạn, xem trạng thái Online và mời vào **Tổ Đội 2v2 / 4v4** (quá 20s tìm trận chưa đủ người sẽ tự bù AI Bot thông minh).\n'
          '• **Phòng Solo / Đấu Tùy Chọn**: Tạo phòng hoặc nhập mã phòng để thách đấu bạn bè, tùy chọn bản đồ và đặt mức **cược Vàng** công bằng.',
    ),
    FaqTopic(
      id: 'heroes_skills',
      label: 'Nhân vật & Kỹ năng',
      prompt: 'Giới thiệu các nhân vật, giá mở khóa và kỹ năng trong game?',
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
        'ranger',
        'tanker',
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
          '🗡️ **Hệ thống Nhân Vật & Bộ 3 Chiêu Thức**:\n'
          '• **George (Mặc định - 0 Vàng)**: Đấu sĩ búa cân bằng — *Búa Cuồng Phong*, *Nện Đất*, *Cơn Cuồng Nộ*.\n'
          '• **Xạ Thủ Ranger / Lyra (4.000 Vàng)**: Bắn xa thả diều — *Tiễn Vũ 5 Tên*, *Nhào Lộn Bẫy Gai*, *Mưa Sao Băng*.\n'
          '• **Hiệp Sĩ Tanker / Braum (4.000 Vàng)**: Đỡ đòn siêu cứng — *Húc Khiên*, *Pháo Đài Sắt (-65% DMG + hồi máu)*, *Địa Chấn*.\n'
          '• **Ninja Sát Thủ / Hayate (4.500 Vàng)**: Bạo kích tốc độ — *Phi Tiêu Lướt Ảnh*, *Khói Ẩn Thân*, *Ảnh Sát Liên Hoàn*.\n'
          '• **Nova Blade (6.000 Vàng)**: Chiến binh ánh sáng — *Energy Slash*, *Shadow Dash*, *Quantum Burst (hút địch nổ AoE)*.\n'
          '• **Shadow (6.000 Vàng)** & **Ember (6.500 Vàng)**: Sát thủ hư không cơ động & Pháp sư đại hỏa cầu diện rộng.',
    ),
    FaqTopic(
      id: 'companions',
      label: 'Trợ thủ AI bay',
      prompt: 'Các Trợ thủ AI bay có kỹ năng và giá mua thế nào?',
      keywords: [
        'trợ thủ',
        'tro thu',
        'pet',
        'companion',
        'aegis',
        'cyber',
        'luna',
        'orbit',
        'dragon',
        'rồng',
        'rong',
        'drone',
        'hút vàng',
        'hut vang',
        'tinh linh',
      ],
      answer:
          '🛸 **Hệ thống 8 Trợ Thủ AI Bay (Kích hoạt chiêu bằng nút PET / phím E)**:\n'
          '• **Bậc 1 (2.000 – 3.000 Vàng)**: *Trợ Thủ Công Kích* (Mưa Đạn Plasma), *Phòng Ngự* (giảm 30% DMG + Khiên 55%), *Khống Chế* (Bão Tuyết đóng băng 3s).\n'
          '• **Bậc 2 (4.000 – 5.000 Vàng)**: *Cyber Drone PIXEL-01* (hồi 25% HP + khiên), *Hồ Ly Luna* (hồi 40% Ki + giảm 3s hồi chiêu), *ORBIT-03* (Pháo Laser nổ + bắn liên thanh).\n'
          '• **Bậc 3 Huyền Thoại**: *Aegis-X9 Lôi Từ* (**8.000 Vàng** — gom quái, hút vật phẩm toàn map + khiên 35%) và *Pyro-Frost Dragon* (**10.000 Vàng** — Hơi Thở Bão Tố đóng băng 2.5s + tăng 30% ATK).',
    ),
    FaqTopic(
      id: 'boss_pve',
      label: 'Mẹo vượt tầng & Boss',
      prompt: 'Mẹo vượt tầng PvE và đánh Boss Chúa Tể hiệu quả?',
      keywords: [
        'boss',
        'quái',
        'quai',
        'vượt ải',
        'vuot ai',
        'tầng',
        'tang',
        'pve',
        'zombie',
        'skeleton',
      ],
      answer:
          '👹 **Mẹo Vượt Tầng PvE & Đánh Boss Chúa Tể**:\n'
          '• Chiến trường có 5 bản đồ (*Đấu Trường Băng Giá, Đảo Băng Tuyết, Rừng Cây Cổ Thụ, Điện Thờ Cổ Long, Hỏa Ngục Dung Nham*). Tầng càng cao, số lượng Boss/quái và sát thương càng tăng.\n'
          '• **Zombie** dùng thuật toán A* truy đuổi, **Skeleton** biết giữ khoảng cách bắn tỉa, còn **Boss Chúa Tể** gọi đệ ở mốc **70% / 50% / 30% HP** và hóa **Cuồng Nộ** khi dưới 50% HP.\n'
          '• Tận dụng các cụm trụ đá chắn đạn, ăn điểm Buff trên bản đồ và dồn sát thương hạ hết Boss (quái phụ còn sót sẽ tự động bị quét sạch để qua tầng, nhận `200 × tầng` Vàng)!',
    ),
    FaqTopic(
      id: 'lucky_wheel',
      label: 'Vòng Quay May Mắn',
      prompt: 'Vòng quay may mắn hoạt động và có phần thưởng gì?',
      keywords: [
        'vòng quay',
        'vong quay',
        'quay',
        'spin',
        'may mắn',
        'may man',
        'jackpot',
      ],
      answer:
          '🎡 **Vòng Quay May Mắn**:\n'
          '• Mỗi ngày bạn nhận **1 lượt quay miễn phí**, tự động làm mới vào **00:00 UTC (07:00 sáng giờ Việt Nam)**.\n'
          '• Vòng quay gồm 6 ô thưởng (`0 Xu, 1 Xu, 2 Xu, 3 Xu, 5 Xu` và giải **Jackpot `10 Xu` = 10.000 Vàng**) giúp bạn tích lũy Vàng mở khóa tướng & trợ thủ cực nhanh!',
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
    bool bypassScopeFilter = false,
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
    } else if (!bypassScopeFilter && !isGameRelatedQuery(trimmed)) {
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

  /// Phản hồi theo luồng thời gian thực (SSE Streaming kiểu ChatGPT).
  /// - Gọi `/api/chat/stream` để nhận từng mảnh văn bản ngay khi Gemini sinh ra.
  /// - Tự động fallback sang `/api/chat` hoặc FAQ offline nếu mất mạng / server chưa cập nhật.
  Stream<String> streamReplyAsync(
    String rawQuery, {
    List<ChatAiMessage> history = const [],
    http.Client? client,
    bool bypassKeywordFilter = false,
    bool bypassScopeFilter = false,
  }) async* {
    final trimmed = rawQuery.trim();
    if (trimmed.isEmpty) {
      yield 'Bạn hãy nhập câu hỏi về game Big-War hoặc bấm vào các chủ đề gợi ý bên dưới nhé!';
      return;
    }

    if (!bypassKeywordFilter) {
      final localReply = resolveLocalReply(trimmed);
      if (localReply != null) {
        yield localReply;
        return;
      }
    } else if (!bypassScopeFilter && !isGameRelatedQuery(trimmed)) {
      yield offTopicRefusalReply;
      return;
    }

    final proxyBaseUrl = EnvConfig.aiProxyUrl.replaceAll(RegExp(r'/+$'), '');
    if (proxyBaseUrl.isEmpty) {
      yield generateReply(trimmed);
      return;
    }

    final streamUri = Uri.parse('$proxyBaseUrl/api/chat/stream');
    final recentHistory =
        history.length > 2 ? history.sublist(history.length - 2) : history;

    final payloadJson = jsonEncode(<String, dynamic>{
      'message': trimmed,
      'history': [
        for (final msg in recentHistory)
          {
            'role': msg.sender == 'user' ? 'user' : 'model',
            'text': msg.text,
          },
      ],
    });

    var yieldedAny = false;
    try {
      await for (final rawLine in postSseLines(
        uri: streamUri,
        jsonBody: payloadJson,
        timeout: _requestTimeout,
        client: client,
      )) {
        final line = rawLine.trim();
        if (line.isEmpty || !line.startsWith('data:')) continue;

        final dataStr = line.substring(5).trim();
        if (dataStr.isEmpty || dataStr == '[DONE]') {
          if (dataStr == '[DONE]') break;
          continue;
        }

        final decoded = jsonDecode(dataStr);
        if (decoded is Map<String, dynamic>) {
          final err = decoded['error']?.toString();
          if (err != null && err.isNotEmpty && !yieldedAny) {
            debugPrint('ChatAiAssistantService: SSE upstream error: $err');
            break;
          }
          final delta = decoded['delta']?.toString() ?? '';
          if (delta.isNotEmpty) {
            yieldedAny = true;
            yield delta;
          }
        }
      }

      if (yieldedAny) return;
    } catch (e) {
      debugPrint('ChatAiAssistantService: SSE stream fallback: $e');
      if (yieldedAny) return;
    }

    // Dự phòng: gọi endpoint chuẩn /api/chat (hoặc FAQ offline nếu lỗi mạng)
    final fallbackReply = await generateReplyAsync(
      trimmed,
      history: history,
      client: client,
      bypassKeywordFilter: bypassKeywordFilter,
      bypassScopeFilter: bypassScopeFilter,
    );
    yield fallbackReply;
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
        '1️⃣ **Hệ thống 7 Nhân vật & 8 Trợ thủ AI bay** (giá mua & kỹ năng)\n'
        '2️⃣ **Cấp độ Nhân vật (1 → 100)** & nhận EXP sau mỗi trận\n'
        '3️⃣ **Quy đổi Kinh tế** (`1 Xu = 1.000 Vàng`) & Vòng Quay Jackpot 10 Xu\n'
        '4️⃣ **Đấu Rank PvP Bo3 (1v1/2v2/4v4)**, Tổ đội & Phòng Solo cược Vàng\n'
        '5️⃣ **Mẹo vượt tầng PvE & đánh Boss Chúa Tể**\n\n'
        'Hãy nhấn vào các nút gợi ý nhanh phía trên hoặc gõ câu hỏi bất kỳ nhé!';
  }
}
