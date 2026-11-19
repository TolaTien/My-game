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

/// Hệ thống Trợ Lý AI (FAQ + Keyword Matching NLP tiếng Việt) hỗ trợ người chơi
class ChatAiAssistantService {
  ChatAiAssistantService._();
  static final ChatAiAssistantService instance = ChatAiAssistantService._();

  static const List<FaqTopic> faqTopics = [
    FaqTopic(
      id: 'level_100',
      label: 'Cấp độ 1-100',
      prompt: 'Hệ thống Level 1 đến 100 của nhân vật hoạt động thế nào?',
      keywords: [
        'level',
        'cấp',
        '100',
        'exp',
        'kinh nghiệm',
        'tăng chỉ số',
        'mạnh',
        'nâng cấp',
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
        'gold',
        'tiền',
        'đổi',
        '1000',
        'kinh tế',
        'mua',
      ],
      answer:
          '🪙 **Hệ thống Kinh Tế (1 Xu = 1000 Vàng)**:\n'
          '• Tỷ giá cố định trong Gold Rush là **1 Xu = 1.000 Vàng**.\n'
          '• Bạn có thể chuyển đổi 2 chiều giữa **Xu ↔ Vàng** ngay trong **Cửa Hàng (Tab Quy Đổi Xu/Vàng)** hoặc trên thanh tiền tệ ở Sảnh Chờ.\n'
          '• Vàng dùng để mở khóa Nhân vật, Trợ thủ AI và Huấn luyện cấp độ 1–100.',
    ),
    FaqTopic(
      id: 'friends_party_pvp',
      label: 'Kết bạn & Tổ đội PvP',
      prompt: 'Làm sao để kết bạn và mời bạn bè vào team chơi PvP 2v2, 4v4?',
      keywords: [
        'kết bạn',
        'bạn bè',
        'mời',
        'team',
        'tổ đội',
        'party',
        'pvp',
        '1v1',
        '2v2',
        '4v4',
        'ghép trận',
      ],
      answer:
          '🤝 **Kết Bạn & Mời Tổ Đội PvP (1v1 / 2v2 / 4v4)**:\n'
          '1. Nhấn nút **BẠN BÈ & TỔ ĐỘI** ở Sảnh Chờ (Lobby).\n'
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
        'tướng',
        'hero',
        'george',
        'lyra',
        'braum',
        'ninja',
        'skill',
        'kỹ năng',
        'chiêu',
      ],
      answer:
          '🗡️ **Hệ thống Nhân Vật & Bộ 3 Kỹ Năng**:\n'
          '• **George (Đấu Sĩ Búa)**: Búa Cuồng Phong (Xoay 360°), Nện Đất Chấn Động (Choáng AoE), Cơn Cuồng Nộ (+Tốc chạy & Sát thương).\n'
          '• **Lyra (Xạ Thủ)**: Bắn tên tầm xa, Mưa Tên Tinh Tú, lộn nhào né đòn.\n'
          '• **Braum (Hiệp Sĩ Khiên)**: Máu cực trâu (+20 HP/cấp), Khiên Chấn Động, Pháo Đài Thép.\n'
          '• **Hayate (Ninja)**: Tốc độ cao nhất, Phi Tiêu Lướt Ảnh, Bom Khói, Ám Sát.',
    ),
    FaqTopic(
      id: 'companions',
      label: 'Trợ thủ AI bay',
      prompt: 'Trợ thủ AI bay có tác dụng gì?',
      keywords: [
        'trợ thủ',
        'pet',
        'companion',
        'aegis',
        'drone',
        'bay',
        'hút vàng',
      ],
      answer:
          '🛸 **Hệ thống Trợ Thủ AI Bay**:\n'
          '• Bay lơ lửng theo quỹ đạo lò xo sau vai nhân vật, tự động bắn tia năng lượng và **tự động hút Vàng/Bình máu/Ngọc EXP**.\n'
          '• Có 4 loại trợ thủ: **Aegis-X9** (Gom quái + Tạo khiên + Thưởng 25% Vàng), **Hỏa Tinh Linh** (Công kích), **Thổ Linh** (Phòng ngự tạo khiên), **Băng Linh** (Khống chế làm chậm 50%).',
    ),
    FaqTopic(
      id: 'custom_assets',
      label: 'Thêm Assets tùy chỉnh',
      prompt: 'Làm sao để thêm file nhân vật, map, trợ thủ, skill mới vào game?',
      keywords: [
        'asset',
        'thêm',
        'file',
        'map',
        'sprite',
        'png',
        'json',
        'tùy chỉnh',
      ],
      answer:
          '📁 **Cách Thêm Nhân Vật, Map, Trợ Thủ, Skill Từ Thư Mục `assets/`**:\n'
          '• Toàn bộ cấu hình được tách riêng trong `assets/data/` (`heroes.json`, `skills.json`, `companions.json`, `maps.json`, `enemies.json`).\n'
          '• Bạn chỉ cần chép file ảnh `.png` vào `assets/images/heroes/` (hoặc `maps/`, `companions/`, `skills/`) rồi thêm thông tin vào file `.json` tương ứng.\n'
          '• Hệ thống `GameAssetRegistry` sẽ tự động đọc và đưa thẳng vào game!',
    ),
  ];

  /// Phân tích câu hỏi bằng Keyword Matching + Điểm tương đồng ngữ nghĩa
  String generateReply(String rawQuery) {
    final query = rawQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return 'Bạn hãy nhập câu hỏi hoặc bấm vào các chủ đề gợi ý bên dưới nhé!';
    }

    int bestScore = 0;
    FaqTopic? bestTopic;

    for (final topic in faqTopics) {
      int score = 0;
      for (final kw in topic.keywords) {
        if (query.contains(kw.toLowerCase())) {
          score += kw.length >= 4 ? 3 : 2;
        }
      }
      if (score > bestScore) {
        bestScore = score;
        bestTopic = topic;
      }
    }

    if (bestTopic != null && bestScore > 0) {
      return bestTopic.answer;
    }

    if (query.contains('boss') || query.contains('quái') || query.contains('ải')) {
      return '👹 **Mẹo Vượt Ải & Đánh Boss**:\n'
          '• Quái Zombie và Boss sử dụng thuật toán **A* (A-Star)** để tìm đường vòng qua tường đá, còn Skeleton biết giữ khoảng cách bắn tỉa (Kiting AI).\n'
          '• Hãy tận dụng 4 khu vực cột đá chữ L ở góc bản đồ để chắn đạn của Skeleton & Boss, nhặt Ngọc EXP để lên cấp trong trận (tối đa Lv.15) và dùng chiêu cuối khi Boss vừa kết thúc đợt lao tới!';
    }

    if (query.contains('quay') || query.contains('spin') || query.contains('may mắn')) {
      return '🎡 **Vòng Quay May Mắn**:\n'
          '• Mỗi ngày bạn có **1 lượt quay miễn phí**, tự động làm mới vào **00:00 UTC (07:00 sáng giờ Việt Nam)**.\n'
          '• Bạn cũng có thể dùng Kim Cương để quay thêm và săn giải **Jackpot 2.000 Vàng**!';
    }

    return '🤖 **Trợ Lý AI Gold Rush**:\n'
        'Mình có thể giải đáp cho bạn về:\n'
        '1️⃣ **Cấp độ Nhân vật (1 → 100)** & cộng chỉ số sau mỗi trận\n'
        '2️⃣ **Quy đổi Kinh tế** (`1 Xu = 1000 Vàng`)\n'
        '3️⃣ **Kết bạn & Mời tổ đội PvP** (1v1 / 2v2 / 4v4)\n'
        '4️⃣ **Kỹ năng Nhân vật & Trợ thủ AI bay**\n'
        '5️⃣ **Cách thêm file Nhân vật / Map / Skill vào `assets/`**\n\n'
        'Hãy nhấn vào các nút gợi ý nhanh phía trên hoặc gõ từ khóa bạn quan tâm nhé!';
  }
}
