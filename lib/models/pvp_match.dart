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
    winGoldReward: 200,
  ),
  duo2v2(
    teamSize: 2,
    code: '2v2',
    title: '2V2 SONG ĐẤU',
    shortLabel: '2v2',
    subtitle: 'Tổ đội 2 đấu 2 hiệp đồng tác chiến',
    winGoldReward: 350,
  ),
  squad4v4(
    teamSize: 4,
    code: '4v4',
    title: '4V4 QUÂN ĐOÀN',
    shortLabel: '4v4',
    subtitle: 'Đại chiến 4 đấu 4 hỗn chiến đỉnh cao',
    winGoldReward: 500,
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
  final int? heroLevel;
  final bool isBot;
  final BotDifficulty difficulty;
  final bool isAlly;

  const PvpOpponentInfo({
    required this.name,
    required this.rankPoints,
    required this.rankTier,
    required this.heroId,
    this.heroLevel,
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
    Random? random,
  }) {
    final rand = random ?? Random();
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
        ? (playerHeroId.isNotEmpty ? playerHeroId : classicRoster[rand.nextInt(classicRoster.length)])
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
    int? seed,
  }) {
    final usedNames = <String>{
      ...onlineAllies.map((a) => a.name),
      ...onlineEnemies.map((e) => e.name),
    };
    final rand = seed != null ? Random(seed) : Random();
    const extendedHeroes = [
      'george',
      'ranger',
      'tanker',
      'ninja',
      'nova_blade',
      'shadow_01',
      'ember_02',
    ];

    final allies = <PvpOpponentInfo>[...onlineAllies];
    while (allies.length < mode.teamSize - 1) {
      final baseBot = PvpOpponentInfo.generateBot(
        playerRp,
        playerHeroId: playerHeroId,
        isAlly: true,
        excludeNames: usedNames,
        random: rand,
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
        random: rand,
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
  final bool isDemotion;
  final int goldReward;
  final Duration matchDuration;
  final PvpGameMode gameMode;

  /// Cơ chế tính Rank theo Sao (dùng chung cho cả 3 chế độ 1v1, 2v2, 4v4)
  final int starDelta;
  final int oldTotalStars;
  final int newTotalStars;
  final int oldStarsInTier;
  final int newStarsInTier;
  final int? maxStarsInNewTier;
  final bool isChallengerTop10;
  final int? serverRank;
  final int? top10CutoffStars;

  const PvpMatchResult({
    required this.isWinner,
    required this.playerRoundsWon,
    required this.opponentRoundsWon,
    required this.rpDelta,
    required this.newRankPoints,
    required this.oldRankTier,
    required this.newRankTier,
    required this.isPromotion,
    this.isDemotion = false,
    required this.goldReward,
    required this.matchDuration,
    this.gameMode = PvpGameMode.solo1v1,
    this.starDelta = 0,
    this.oldTotalStars = 0,
    this.newTotalStars = 0,
    this.oldStarsInTier = 0,
    this.newStarsInTier = 0,
    this.maxStarsInNewTier = PvpRankSystem.starsPerStandardTier,
    this.isChallengerTop10 = false,
    this.serverRank,
    this.top10CutoffStars,
  });

  bool get isLegendaryOrAbove =>
      newTotalStars >= PvpRankSystem.legendaryStartTotalStars;

  PvpMatchResult copyWithChallengerStatus({
    required bool isChallengerTop10,
    required String resolvedNewTier,
    int? serverRank,
    int? top10CutoffStars,
  }) {
    final promoted = isWinner &&
        (resolvedNewTier != oldRankTier) &&
        (PvpRankSystem.tierOrder(resolvedNewTier) >
            PvpRankSystem.tierOrder(oldRankTier));
    final demoted = !isWinner &&
        (resolvedNewTier != oldRankTier) &&
        (PvpRankSystem.tierOrder(resolvedNewTier) <
            PvpRankSystem.tierOrder(oldRankTier));

    return PvpMatchResult(
      isWinner: isWinner,
      playerRoundsWon: playerRoundsWon,
      opponentRoundsWon: opponentRoundsWon,
      rpDelta: rpDelta,
      newRankPoints: newRankPoints,
      oldRankTier: oldRankTier,
      newRankTier: resolvedNewTier,
      isPromotion: promoted,
      isDemotion: demoted,
      goldReward: goldReward,
      matchDuration: matchDuration,
      gameMode: gameMode,
      starDelta: starDelta,
      oldTotalStars: oldTotalStars,
      newTotalStars: newTotalStars,
      oldStarsInTier: oldStarsInTier,
      newStarsInTier: newStarsInTier,
      maxStarsInNewTier: maxStarsInNewTier,
      isChallengerTop10: isChallengerTop10,
      serverRank: serverRank ?? this.serverRank,
      top10CutoffStars: top10CutoffStars ?? this.top10CutoffStars,
    );
  }
}

/// Hệ thống tính Rank theo Sao áp dụng chung cho cả 3 chế độ 1v1, 2v2, 4v4:
/// - Từ Đồng -> Bạc -> Vàng -> Bạch Kim -> Kim Cương: mỗi bậc có 3 sao để lên bậc tiếp theo.
///   + Đồng: 0..2 tổng sao (0⭐, 1⭐, 2⭐; đủ 3 sao lên Bạc 0⭐)
///   + Bạc: 3..5 tổng sao (0⭐, 1⭐, 2⭐; đủ 3 sao lên Vàng 0⭐)
///   + Vàng: 6..8 tổng sao (0⭐, 1⭐, 2⭐; đủ 3 sao lên Bạch Kim 0⭐)
///   + Bạch Kim: 9..11 tổng sao (0⭐, 1⭐, 2⭐; đủ 3 sao lên Kim Cương 0⭐)
///   + Kim Cương: 12..14 tổng sao (0⭐, 1⭐, 2⭐; đủ 3 sao lên Huyền Thoại 0⭐)
/// - Từ Huyền Thoại (tổng sao >= 15): bắt đầu từ 0 sao (0⭐, 1⭐, 2⭐...) cộng sao tích lũy.
/// - Thách Đấu: cần đạt tối thiểu 3 sao Huyền Thoại (tổng sao >= 18) VÀ nằm trong
///   Top 10 game thủ nhiều sao nhất server (tránh nhảy thẳng từ Kim Cương lên Thách Đấu).
class PvpRankSystem {
  static const int starsPerStandardTier = 3;
  static const int standardTierCount = 5; // Đồng, Bạc, Vàng, Bạch Kim, Kim Cương
  static const int legendaryStartTotalStars =
      starsPerStandardTier * standardTierCount; // 15 tổng sao = Huyền Thoại 0 sao
  static const int challengerMinLegendaryStars =
      3; // Cần ít nhất 3 sao Huyền Thoại trước khi xét Thách Đấu
  static const int challengerMinTotalStars =
      legendaryStartTotalStars + challengerMinLegendaryStars; // 18 tổng sao
  static const int challengerTopLimit = 10; // Top 10 game thủ nhiều sao nhất server

  static const List<String> standardTiers = [
    'Đồng',
    'Bạc',
    'Vàng',
    'Bạch Kim',
    'Kim Cương',
  ];

  static String getRankAssetPath(String tier) {
    switch (tier) {
      case 'Thách Đấu':
        return 'assets/images/ranks/rank_thach_dau.png';
      case 'Huyền Thoại':
        return 'assets/images/ranks/rank_huyen_thoai.png';
      case 'Kim Cương':
        return 'assets/images/ranks/rank_kim_cuong.png';
      case 'Bạch Kim':
        return 'assets/images/ranks/rank_bach_kim.png';
      case 'Vàng':
        return 'assets/images/ranks/rank_vang.png';
      case 'Bạc':
        return 'assets/images/ranks/rank_bac.png';
      case 'Đồng':
      default:
        return 'assets/images/ranks/rank_dong.png';
    }
  }

  static int tierOrder(String tier) {
    switch (tier) {
      case 'Đồng':
        return 0;
      case 'Bạc':
        return 1;
      case 'Vàng':
        return 2;
      case 'Bạch Kim':
        return 3;
      case 'Kim Cương':
        return 4;
      case 'Huyền Thoại':
        return 5;
      case 'Thách Đấu':
        return 6;
      default:
        return 0;
    }
  }

  /// Lấy tên bậc Rank theo tổng số sao tích lũy và trạng thái Top 10 Server
  static String getTierFromStars(
    int totalStars, {
    bool isTop10Challenger = false,
  }) {
    final safeStars = max(0, totalStars);
    if (safeStars >= legendaryStartTotalStars) {
      final eligibleChallenger =
          isTop10Challenger && safeStars >= challengerMinTotalStars;
      return eligibleChallenger ? 'Thách Đấu' : 'Huyền Thoại';
    }
    final tierIdx =
        (safeStars ~/ starsPerStandardTier).clamp(0, standardTiers.length - 1);
    return standardTiers[tierIdx];
  }

  /// Số sao hiện tại bên trong bậc Rank:
  /// - Đồng -> Kim Cương: 0, 1, 2 (trên tối đa 3 sao để lên bậc kế tiếp)
  /// - Huyền Thoại / Thách Đấu: từ 0 sao trở lên (totalStars - 15)
  static int getStarsInTier(int totalStars) {
    final safeStars = max(0, totalStars);
    if (safeStars >= legendaryStartTotalStars) {
      return safeStars - legendaryStartTotalStars;
    }
    return safeStars % starsPerStandardTier;
  }

  /// Số sao tối đa để thăng hạng của bậc hiện tại (3 sao cho Đồng -> Kim Cương, null cho Huyền Thoại/Thách Đấu)
  static int? getMaxStarsForTier(int totalStars) {
    if (totalStars >= legendaryStartTotalStars) return null;
    return starsPerStandardTier;
  }

  /// Tên bậc Rank mục tiêu kế tiếp
  static String getNextTierName(
    int totalStars, {
    bool isTop10Challenger = false,
  }) {
    final safeStars = max(0, totalStars);
    if (safeStars < 3) return 'Bạc';
    if (safeStars < 6) return 'Vàng';
    if (safeStars < 9) return 'Bạch Kim';
    if (safeStars < 12) return 'Kim Cương';
    if (safeStars < 15) return 'Huyền Thoại';
    if (!isTop10Challenger) return 'Thách Đấu (Top 10 Server)';
    return 'Thách Đấu Đỉnh Cao (Top 10 Server)';
  }

  /// Chuỗi hiển thị ngắn gọn Bậc Rank kèm số Sao (VD: "Kim Cương • 2/3 ⭐" hoặc "Huyền Thoại • 4 ⭐")
  static String formatRankLabel(
    int totalStars, {
    bool isTop10Challenger = false,
    int? serverRank,
  }) {
    final tier = getTierFromStars(
      totalStars,
      isTop10Challenger: isTop10Challenger,
    );
    final starsInTier = getStarsInTier(totalStars);
    if (totalStars >= legendaryStartTotalStars) {
      final eligibleChallenger =
          isTop10Challenger && totalStars >= challengerMinTotalStars;
      final rankSuffix =
          (eligibleChallenger && serverRank != null && serverRank <= challengerTopLimit)
              ? ' #$serverRank'
              : '';
      return '$tier$rankSuffix • $starsInTier ⭐';
    }
    return '$tier • $starsInTier/$starsPerStandardTier ⭐';
  }

  /// Quy đổi từ Tổng Sao sang điểm RP tương đương (để đồng bộ Matchmaking & BXH)
  static int rpFromTotalStars(int totalStars) {
    final safeStars = max(0, totalStars);
    if (safeStars >= legendaryStartTotalStars) {
      final legendaryStars = safeStars - legendaryStartTotalStars;
      return 2000 + legendaryStars * 30;
    }
    final tierIdx = safeStars ~/ starsPerStandardTier;
    final starInTier = safeStars % starsPerStandardTier;
    return 1000 + (tierIdx * 200) + (starInTier * 65);
  }

  /// Quy đổi từ điểm RP sang Tổng Sao tương đương
  static int totalStarsFromRp(int rp) {
    if (rp <= 1000) return 0;
    if (rp >= 2000) {
      return legendaryStartTotalStars + ((rp - 2000) ~/ 30);
    }
    final tierIdx = ((rp - 1000) ~/ 200).clamp(0, standardTierCount - 1);
    final offsetInTier = (rp - (1000 + tierIdx * 200)).clamp(0, 199);
    final starInTier =
        (offsetInTier ~/ 65).clamp(0, starsPerStandardTier - 1);
    return tierIdx * starsPerStandardTier + starInTier;
  }
}

class PvpEloCalculator {
  static PvpMatchResult calculateResult({
    required int playerCurrentRp,
    int? playerCurrentStars,
    bool isCurrentChallengerTop10 = false,
    bool? isNewChallengerTop10,
    int? serverRank,
    int? top10CutoffStars,
    required int playerRoundsWon,
    required int opponentRoundsWon,
    required Duration matchDuration,
    PvpGameMode gameMode = PvpGameMode.solo1v1,
  }) {
    final bool isWinner = playerRoundsWon >= 2;
    int goldReward = isWinner ? gameMode.winGoldReward : 0;

    // 1. Tính Sao Rank (áp dụng chung cho cả 3 chế độ 1v1, 2v2, 4v4):
    // Mỗi trận thắng +1 sao, mỗi trận thua -1 sao (tối thiểu 0 sao ở bậc Đồng).
    final int oldTotalStars =
        playerCurrentStars ?? PvpRankSystem.totalStarsFromRp(playerCurrentRp);
    final int starDelta = isWinner ? 1 : (oldTotalStars > 0 ? -1 : 0);
    final int newTotalStars = max(0, oldTotalStars + starDelta);
    final int oldStarsInTier = PvpRankSystem.getStarsInTier(oldTotalStars);
    final int newStarsInTier = PvpRankSystem.getStarsInTier(newTotalStars);
    final int? maxStarsInNewTier =
        PvpRankSystem.getMaxStarsForTier(newTotalStars);

    // 2. Tính Điểm RP & Bậc Rank:
    // Nếu truyền playerCurrentStars (chế độ tính Rank theo Sao), đồng bộ RP và Tier theo Sao.
    // Nếu không truyền playerCurrentStars (các bài test Elo cũ), giữ nguyên công thức RP cũ.
    final int rpDelta;
    final int newRankPoints;
    final String oldTier;
    final String newTier;

    if (playerCurrentStars != null) {
      newRankPoints = PvpRankSystem.rpFromTotalStars(newTotalStars);
      rpDelta = newRankPoints - playerCurrentRp;
      oldTier = PvpRankSystem.getTierFromStars(
        oldTotalStars,
        isTop10Challenger: isCurrentChallengerTop10,
      );
      final resolvedNewChallenger =
          isNewChallengerTop10 ?? isCurrentChallengerTop10;
      newTier = PvpRankSystem.getTierFromStars(
        newTotalStars,
        isTop10Challenger: resolvedNewChallenger &&
            newTotalStars >= PvpRankSystem.challengerMinTotalStars,
      );
    } else {
      int rawRpDelta = 0;
      if (isWinner) {
        rawRpDelta = 30;
        if (playerRoundsWon == 2 && opponentRoundsWon == 0) {
          rawRpDelta += 5; // Clean sweep 2-0 bonus
        }
      } else {
        if (playerCurrentRp < 1200) {
          rawRpDelta = -5; // Bronze loss mitigation
        } else {
          rawRpDelta = -20;
        }
      }
      rpDelta = rawRpDelta;
      newRankPoints = max(0, playerCurrentRp + rpDelta);
      oldTier = getRankTier(playerCurrentRp);
      newTier = getRankTier(newRankPoints);
    }

    final bool isPromotion = isWinner &&
        (newTier != oldTier) &&
        (PvpRankSystem.tierOrder(newTier) > PvpRankSystem.tierOrder(oldTier));
    final bool isDemotion = !isWinner &&
        (newTier != oldTier) &&
        (PvpRankSystem.tierOrder(newTier) < PvpRankSystem.tierOrder(oldTier));

    return PvpMatchResult(
      isWinner: isWinner,
      playerRoundsWon: playerRoundsWon,
      opponentRoundsWon: opponentRoundsWon,
      rpDelta: rpDelta,
      newRankPoints: newRankPoints,
      oldRankTier: oldTier,
      newRankTier: newTier,
      isPromotion: isPromotion,
      isDemotion: isDemotion,
      goldReward: goldReward,
      matchDuration: matchDuration,
      gameMode: gameMode,
      starDelta: starDelta,
      oldTotalStars: oldTotalStars,
      newTotalStars: newTotalStars,
      oldStarsInTier: oldStarsInTier,
      newStarsInTier: newStarsInTier,
      maxStarsInNewTier: maxStarsInNewTier,
      isChallengerTop10: newTier == 'Thách Đấu',
      serverRank: serverRank,
      top10CutoffStars: top10CutoffStars,
    );
  }

  static String getRankTier(int rp, {bool isTop10Challenger = false}) {
    final challengerMinRp =
        PvpRankSystem.rpFromTotalStars(PvpRankSystem.challengerMinTotalStars);
    if (rp >= challengerMinRp && isTop10Challenger) return 'Thách Đấu';
    if (rp >= 2000) return 'Huyền Thoại';
    if (rp >= 1800) return 'Kim Cương';
    if (rp >= 1600) return 'Bạch Kim';
    if (rp >= 1400) return 'Vàng';
    if (rp >= 1200) return 'Bạc';
    return 'Đồng';
  }
}
