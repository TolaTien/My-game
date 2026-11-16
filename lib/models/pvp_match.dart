import 'dart:math';

enum PvpMatchState {
  waiting,
  matchmaking,
  roundIntro,
  fighting,
  roundEnd,
  matchFinished,
}

/// Chế độ đấu trường PvP: 1v1 Đấu Đơn, 2v2 Song Đấu, 4v4 Đại Chiến Quân Đoàn
enum PvpGameMode {
  solo1v1(
    teamSize: 1,
    code: '1v1',
    title: '1V1 ĐẤU ĐƠN',
    shortLabel: '1v1',
    subtitle: 'Solo Rank Bo3 truyền thống',
    winGoldReward: 1500,
  ),
  duo2v2(
    teamSize: 2,
    code: '2v2',
    title: '2V2 SONG ĐẤU',
    shortLabel: '2v2',
    subtitle: 'Tổ đội 2 đấu 2 hiệp đồng tác chiến',
    winGoldReward: 2200,
  ),
  squad4v4(
    teamSize: 4,
    code: '4v4',
    title: '4V4 QUÂN ĐOÀN',
    shortLabel: '4v4',
    subtitle: 'Đại chiến 4 đấu 4 hỗn chiến đỉnh cao',
    winGoldReward: 3000,
  );

  final int teamSize;
  final String code;
  final String title;
  final String shortLabel;
  final String subtitle;
  final int winGoldReward;

  const PvpGameMode({
    required this.teamSize,
    required this.code,
    required this.title,
    required this.shortLabel,
    required this.subtitle,
    required this.winGoldReward,
  });

  int get totalPlayers => teamSize * 2;
}

enum BotDifficulty {
  bronzeSilver,
  goldPlatinum,
  diamondChallenger,
}

enum QuickChatPhrase {
  attack('Tấn công!'),
  retreat('Rút lui!'),
  help('Cứu tôi!'),
  awesome('Tuyệt vời!'),
  wait('Chờ tí!'),
  noob('Gà quá!');

  final String text;
  const QuickChatPhrase(this.text);
}

class PvpRoundResult {
  final int roundNumber;
  final bool isPlayerWinner;
  final int playerHpRemaining;
  final int opponentHpRemaining;
  final Duration roundDuration;

  const PvpRoundResult({
    required this.roundNumber,
    required this.isPlayerWinner,
    required this.playerHpRemaining,
    required this.opponentHpRemaining,
    required this.roundDuration,
  });
}

typedef PvpOpponent = PvpOpponentInfo;

class PvpOpponentInfo {
  final String name;
  final int rankPoints;
  final String rankTier;
  final String heroId;
  final bool isBot;
  final BotDifficulty difficulty;
  final bool isAlly;

  const PvpOpponentInfo({
    required this.name,
    required this.rankPoints,
    required this.rankTier,
    required this.heroId,
    this.isBot = true,
    this.difficulty = BotDifficulty.bronzeSilver,
    this.isAlly = false,
  });

  static const List<String> gamerTags = [
    'BáĐạo99',
    'ChiếnThần_SG',
    'SátThủBóngĐêm',
    'RồngLửaVN',
    'TrùmSolo1v1',
    'VôĐịchThiênHạ',
    'BóngMaHưKhông',
    'LôiThầnHàThành',
    'ĐộcCôCầuBại',
    'KiếmThánh_VN',
    'ThầnĐiêuĐạiHiệp',
    'BấtBại_9x',
    'HắcBạchCôngTử',
    'TiểuLongNữ',
    'CuồngPhong_HN',
    'BãoLửa2026',
    'HiệpSĩBóngĐêm',
    'NinjaSiêuCấp',
    'ThầnSấm_VN',
    'ĐạiHiệpBấtTử',
    'HắcÁmVương',
    'CaoThủẨnDanh',
    'PhượngHoàngLửa',
    'SongĐaoQuyết',
    'BáchPhátBáchTrúng',
    'VuaChiếnTrường',
    'TửThầnĐêm',
    'SóiBăng_VN',
    'CuồngMaĐao',
    'VươngGiảVinhDiệu',
  ];

  factory PvpOpponentInfo.generateBot(
    int playerRp, {
    String playerHeroId = 'george',
    bool isAlly = false,
    Set<String>? excludeNames,
  }) {
    final rand = Random();
    final availableTags = excludeNames == null || excludeNames.isEmpty
        ? gamerTags
        : gamerTags.where((t) => !excludeNames.contains(t)).toList();
    final pool = availableTags.isNotEmpty ? availableTags : gamerTags;
    final name = pool[rand.nextInt(pool.length)];

    final delta = rand.nextInt(301) - 150; // -150 to +150
    final botRp = max(0, playerRp + delta);
    final tier = PvpEloCalculator.getRankTier(botRp);

    // Giữ nguyên tập 4 tướng cơ bản cho bài test unit 1v1, mở rộng khi chọn tướng mới
    const classicRoster = ['george', 'ranger', 'tanker', 'ninja'];
    final hero = rand.nextDouble() < 0.6
        ? (classicRoster.contains(playerHeroId) ? playerHeroId : classicRoster[rand.nextInt(classicRoster.length)])
        : classicRoster[rand.nextInt(classicRoster.length)];

    final BotDifficulty diff;
    if (playerRp < 1400) {
      diff = BotDifficulty.bronzeSilver;
    } else if (playerRp < 1800) {
      diff = BotDifficulty.goldPlatinum;
    } else {
      diff = BotDifficulty.diamondChallenger;
    }

    return PvpOpponentInfo(
      name: name,
      rankPoints: botRp,
      rankTier: tier,
      heroId: hero,
      isBot: true,
      difficulty: diff,
      isAlly: isAlly,
    );
  }

  /// Tạo đội hình đầy đủ cho chế độ 1v1, 2v2 hoặc 4v4
  static PvpTeamRoster generateTeamRoster({
    required int playerRp,
    required PvpGameMode mode,
    String playerHeroId = 'george',
    List<PvpOpponentInfo> onlineAllies = const [],
    List<PvpOpponentInfo> onlineEnemies = const [],
  }) {
    final usedNames = <String>{
      ...onlineAllies.map((a) => a.name),
      ...onlineEnemies.map((e) => e.name),
    };
    final rand = Random();
    const extendedHeroes = ['george', 'kaelen', 'ranger', 'tanker', 'ninja', 'valeria', 'garrick'];

    final allies = <PvpOpponentInfo>[...onlineAllies];
    while (allies.length < mode.teamSize - 1) {
      final baseBot = PvpOpponentInfo.generateBot(
        playerRp,
        playerHeroId: playerHeroId,
        isAlly: true,
        excludeNames: usedNames,
      );
      usedNames.add(baseBot.name);
      final hero = extendedHeroes[rand.nextInt(extendedHeroes.length)];
      allies.add(PvpOpponentInfo(
        name: baseBot.name,
        rankPoints: baseBot.rankPoints,
        rankTier: baseBot.rankTier,
        heroId: hero,
        isBot: true,
        difficulty: baseBot.difficulty,
        isAlly: true,
      ));
    }

    final enemies = <PvpOpponentInfo>[...onlineEnemies];
    while (enemies.length < mode.teamSize) {
      final baseBot = PvpOpponentInfo.generateBot(
        playerRp,
        playerHeroId: playerHeroId,
        isAlly: false,
        excludeNames: usedNames,
      );
      usedNames.add(baseBot.name);
      final hero = mode == PvpGameMode.solo1v1
          ? baseBot.heroId
          : extendedHeroes[rand.nextInt(extendedHeroes.length)];
      enemies.add(PvpOpponentInfo(
        name: baseBot.name,
        rankPoints: baseBot.rankPoints,
        rankTier: baseBot.rankTier,
        heroId: hero,
        isBot: true,
        difficulty: baseBot.difficulty,
        isAlly: false,
      ));
    }

    return PvpTeamRoster(
      mode: mode,
      allies: allies,
      enemies: enemies,
    );
  }
}

/// Danh sách thành viên 2 đội trong trận đấu PvP (1v1, 2v2, 4v4)
class PvpTeamRoster {
  final PvpGameMode mode;
  /// Đồng đội của người chơi (0 cho 1v1, 1 cho 2v2, 3 cho 4v4)
  final List<PvpOpponentInfo> allies;
  /// Đội hình phe địch (1 cho 1v1, 2 cho 2v2, 4 cho 4v4)
  final List<PvpOpponentInfo> enemies;

  const PvpTeamRoster({
    required this.mode,
    required this.allies,
    required this.enemies,
  });

  PvpOpponentInfo get primaryOpponent => enemies.first;
}

class PvpMatchResult {
  final bool isWinner;
  final int playerRoundsWon;
  final int opponentRoundsWon;
  final int rpDelta;
  final int newRankPoints;
  final String oldRankTier;
  final String newRankTier;
  final bool isPromotion;
  final int goldReward;
  final Duration matchDuration;
  final PvpGameMode gameMode;

  const PvpMatchResult({
    required this.isWinner,
    required this.playerRoundsWon,
    required this.opponentRoundsWon,
    required this.rpDelta,
    required this.newRankPoints,
    required this.oldRankTier,
    required this.newRankTier,
    required this.isPromotion,
    required this.goldReward,
    required this.matchDuration,
    this.gameMode = PvpGameMode.solo1v1,
  });
}

class PvpEloCalculator {
  static PvpMatchResult calculateResult({
    required int playerCurrentRp,
    required int playerRoundsWon,
    required int opponentRoundsWon,
    required Duration matchDuration,
    PvpGameMode gameMode = PvpGameMode.solo1v1,
  }) {
    final bool isWinner = playerRoundsWon >= 2;
    int rpDelta = 0;
    int goldReward = 0;

    if (isWinner) {
      rpDelta = 30;
      if (playerRoundsWon == 2 && opponentRoundsWon == 0) {
        rpDelta += 5; // Clean sweep 2-0 bonus
      }
      goldReward = gameMode.winGoldReward;
    } else {
      if (playerCurrentRp < 1200) {
        rpDelta = -5; // Bronze loss mitigation
      } else {
        rpDelta = -20;
      }
    }

    final int newRankPoints = max(0, playerCurrentRp + rpDelta);
    final String oldTier = getRankTier(playerCurrentRp);
    final String newTier = getRankTier(newRankPoints);
    final bool isPromotion = isWinner && (newTier != oldTier);

    return PvpMatchResult(
      isWinner: isWinner,
      playerRoundsWon: playerRoundsWon,
      opponentRoundsWon: opponentRoundsWon,
      rpDelta: rpDelta,
      newRankPoints: newRankPoints,
      oldRankTier: oldTier,
      newRankTier: newTier,
      isPromotion: isPromotion,
      goldReward: goldReward,
      matchDuration: matchDuration,
      gameMode: gameMode,
    );
  }

  static String getRankTier(int rp) {
    if (rp >= 2000) return 'Thách Đấu';
    if (rp >= 1800) return 'Kim Cương';
    if (rp >= 1600) return 'Bạch Kim';
    if (rp >= 1400) return 'Vàng';
    if (rp >= 1200) return 'Bạc';
    return 'Đồng';
  }
}
