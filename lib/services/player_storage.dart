import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/stat_growth_formula.dart';
import '../core/companion_catalog.dart';
import '../models/player_profile.dart';
import '../models/pvp_match.dart';
import 'friend_party_service.dart';

class PlayerStorage {
  static const String _storageKey = 'big_war_player_profile';
  static const String _legacyStorageKey = 'gold_rush_player_profile';

  /// Tỷ giá quy đổi chuẩn: 1 Xu = 1000 Vàng
  static const int goldPerXu = PlayerProfile.goldPerXu;

  /// ValueNotifier cho phép toàn bộ UI phản ứng tức thì khi dữ liệu thay đổi
  static final ValueNotifier<PlayerProfile> profileNotifier =
      ValueNotifier<PlayerProfile>(PlayerProfile.defaultProfile());

  static PlayerProfile get currentProfile => profileNotifier.value;

  /// UID tài khoản Firebase đang đăng nhập (null = chơi offline / khách)
  static String? _activeUid;
  static String? get activeUid => _activeUid;

  /// Hook đồng bộ hồ sơ lên cloud (do AuthService gắn vào khi đăng nhập)
  static void Function(PlayerProfile profile)? _cloudSync;

  /// Mỗi tài khoản có một bản cache cục bộ riêng để không lẫn dữ liệu khi đổi tài khoản
  static String get _activeKey =>
      _activeUid == null ? _storageKey : '${_storageKey}_$_activeUid';

  /// Gắn tài khoản đang đăng nhập (gọi bởi AuthService)
  static void attachUser(String uid, void Function(PlayerProfile) cloudSync) {
    _activeUid = uid;
    _cloudSync = cloudSync;
  }

  /// Gỡ tài khoản khi đăng xuất
  static void detachUser() {
    _activeUid = null;
    _cloudSync = null;
    profileNotifier.value = PlayerProfile.defaultProfile();
  }

  /// Đọc hồ sơ người chơi từ SharedPreferences
  static Future<PlayerProfile> loadProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var jsonString = prefs.getString(_activeKey);
      if (jsonString == null || jsonString.isEmpty) {
        final legacyKey = _activeUid == null ? _legacyStorageKey : '${_legacyStorageKey}_$_activeUid';
        jsonString = prefs.getString(legacyKey);
      }
      if (jsonString != null && jsonString.isNotEmpty) {
        final Map<String, dynamic> map = jsonDecode(jsonString);
        var profile = PlayerProfile.fromJson(map);

        // Nâng cấp khỏi mã ID tĩnh cũ GR8899 nếu chưa có mã riêng
        if (profile.playerCode == 'GR8899' || profile.playerCode.isEmpty) {
          final rand = 1000 + Random().nextInt(8999);
          final newCode = 'GR$rand';
          final newName = profile.playerName == 'Chiến Binh #88'
              ? 'Chiến Binh #$rand'
              : profile.playerName;
          profile = profile.copyWith(
            playerCode: newCode,
            playerName: newName,
          );
          unawaited(saveProfile(profile));
        }

        if (profile.selectedHeroId == 'aria' || profile.unlockedHeroIds.contains('aria')) {
          final cleanUnlocked =
              profile.unlockedHeroIds.where((id) => id != 'aria').toList();
          final cleanSelected =
              profile.selectedHeroId == 'aria' ? 'george' : profile.selectedHeroId;
          profile = profile.copyWith(
            selectedHeroId: cleanSelected,
            unlockedHeroIds: cleanUnlocked,
          );
          unawaited(saveProfile(profile));
        }
        profileNotifier.value = profile;
        return profile;
      }
    } catch (e) {
      debugPrint('Lỗi tải player profile: $e');
    }

    final defaultProf = PlayerProfile.defaultProfile();
    profileNotifier.value = defaultProf;
    unawaited(saveProfile(defaultProf));
    return defaultProf;
  }

  /// Cập nhật Tên và Mã ID người chơi
  static Future<void> updateNameAndCode(String newName, String newCode) async {
    final cleanName = newName.trim();
    final cleanCode = newCode.trim().toUpperCase();
    if (cleanName.isEmpty || cleanCode.isEmpty) return;

    final updated = currentProfile.copyWith(
      playerName: cleanName,
      playerCode: cleanCode,
    );
    await saveProfile(updated);
    // Đồng bộ ngay lập tức lên directory
    unawaited(FriendPartyService.instance.syncOwnProfileToDirectory(updated));
  }

  /// Lưu hồ sơ người chơi vào SharedPreferences và cập nhật notifier
  /// và đồng bộ lên Firebase (players/{uid}/profile) nếu đã đăng nhập.
  static Future<void> saveProfile(PlayerProfile profile, {bool syncCloud = true}) async {
    profileNotifier.value = profile;
    if (syncCloud) _cloudSync?.call(profile);
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(profile.toJson());
      await prefs.setString(_activeKey, jsonString);
    } catch (e) {
      debugPrint('Lỗi lưu player profile: $e');
    }
  }

  /// Cộng Vàng vào tài khoản
  static Future<void> addGold(int amount) async {
    final updated = currentProfile.copyWith(
      gold: currentProfile.gold + amount,
    );
    await saveProfile(updated);
  }

  /// Cộng Xu vào tài khoản (1 Xu = 1000 Vàng)
  static Future<void> addXu(int amount) async {
    if (amount <= 0) return;
    final updated = currentProfile.copyWith(
      xu: currentProfile.xu + amount,
    );
    await saveProfile(updated);
  }

  /// Đổi từ Xu sang Vàng theo tỷ lệ 1 Xu = 1000 Vàng
  static Future<bool> convertXuToGold(int xuAmount) async {
    if (xuAmount <= 0 || currentProfile.xu < xuAmount) return false;
    final updated = currentProfile.copyWith(
      xu: currentProfile.xu - xuAmount,
      gold: currentProfile.gold + (xuAmount * goldPerXu),
    );
    await saveProfile(updated);
    return true;
  }

  /// Đổi từ Vàng sang Xu theo tỷ lệ 1000 Vàng = 1 Xu
  static Future<bool> convertGoldToXu(int xuAmount) async {
    final neededGold = xuAmount * goldPerXu;
    if (xuAmount <= 0 || currentProfile.gold < neededGold) return false;
    final updated = currentProfile.copyWith(
      gold: currentProfile.gold - neededGold,
      xu: currentProfile.xu + xuAmount,
    );
    await saveProfile(updated);
    return true;
  }

  /// Trừ Vàng khỏi tài khoản (nếu đủ số dư)
  static Future<bool> spendGold(int amount) async {
    if (currentProfile.gold < amount) return false;
    final updated = currentProfile.copyWith(
      gold: currentProfile.gold - amount,
    );
    await saveProfile(updated);
    return true;
  }

  /// Trừ Kim Cương khỏi tài khoản (nếu đủ số dư)
  static Future<bool> spendDiamonds(int amount) async {
    if (currentProfile.diamonds < amount) return false;
    final updated = currentProfile.copyWith(
      diamonds: currentProfile.diamonds - amount,
    );
    await saveProfile(updated);
    return true;
  }

  /// Cộng EXP cho nhân vật sau mỗi trận đấu (Level 1 -> 100)
  /// Tự động tăng cấp và cộng chỉ số HP, Ki, Sức đánh theo hệ tướng.
  static Future<HeroLevelUpResult> addHeroExpAfterMatch({
    String? heroId,
    required bool isVictory,
    required bool isPvp,
    int floorOrRounds = 1,
    int coinsOrKills = 0,
    int? customExp,
  }) async {
    final targetHeroId = heroId ?? currentProfile.selectedHeroId;
    final curLv = currentProfile.getHeroLevel(targetHeroId);
    final curExp = currentProfile.getHeroExp(targetHeroId);
    final expEarned = customExp ??
        StatGrowthFormula.calculateMatchExpReward(
          isVictory: isVictory,
          isPvp: isPvp,
          floorOrRounds: floorOrRounds,
          coinsOrKills: coinsOrKills,
        );

    final result = StatGrowthFormula.applyExpGain(
      heroId: targetHeroId,
      currentLevel: curLv,
      currentExp: curExp,
      expEarned: expEarned,
    );

    final newLevels = Map<String, int>.from(currentProfile.heroLevels);
    final newExps = Map<String, int>.from(currentProfile.heroExp);
    newLevels[targetHeroId] = result.newLevel;
    newExps[targetHeroId] = result.currentExp;

    final updated = currentProfile.copyWith(
      heroLevels: newLevels,
      heroExp: newExps,
    );
    await saveProfile(updated);
    return result;
  }

  /// Huấn luyện / nâng cấp nhanh nhân vật bằng Vàng tại Lobby/Shop (tối đa cấp 100)
  static Future<HeroLevelUpResult?> trainHeroWithGold(String heroId) async {
    final curLv = currentProfile.getHeroLevel(heroId);
    if (curLv >= StatGrowthFormula.maxHeroLevel) return null;

    final costGold = 300 + (curLv * 50);
    if (currentProfile.gold < costGold) return null;

    final neededExp = StatGrowthFormula.expRequiredForNextLevel(curLv) -
        currentProfile.getHeroExp(heroId);
    final result = StatGrowthFormula.applyExpGain(
      heroId: heroId,
      currentLevel: curLv,
      currentExp: currentProfile.getHeroExp(heroId),
      expEarned: neededExp > 0 ? neededExp : 100,
    );

    final newLevels = Map<String, int>.from(currentProfile.heroLevels);
    final newExps = Map<String, int>.from(currentProfile.heroExp);
    newLevels[heroId] = result.newLevel;
    newExps[heroId] = result.currentExp;

    final updated = currentProfile.copyWith(
      gold: currentProfile.gold - costGold,
      heroLevels: newLevels,
      heroExp: newExps,
    );
    await saveProfile(updated);
    return result;
  }

  /// Ghi nhận lượt quay Vòng Quay May Mắn (cộng vàng + cập nhật timestamp)
  static Future<void> recordSpin(int goldEarned) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final updated = currentProfile.copyWith(
      gold: currentProfile.gold + goldEarned,
      lastSpinTimestamp: nowMs,
    );
    await saveProfile(updated);
  }

  /// Cập nhật kết quả sau trận đấu PvP (áp dụng chung mức Rank & Sao cho cả 1v1, 2v2, 4v4)
  static Future<void> applyPvpResult(PvpMatchResult result) async {
    final updated = currentProfile.copyWith(
      rankPoints: result.newRankPoints,
      rankStars: result.newTotalStars,
      isChallengerTop10: result.isChallengerTop10,
      serverRank: result.serverRank,
      gold: currentProfile.gold + result.goldReward,
    );
    await saveProfile(updated);
  }

  /// Mở khóa nhân vật
  static Future<bool> unlockHero(String heroId, int price) async {
    if (currentProfile.unlockedHeroIds.contains(heroId)) return true;
    if (currentProfile.gold < price) return false;

    final newUnlocked = List<String>.from(currentProfile.unlockedHeroIds)
      ..add(heroId);
    final newLevels = Map<String, int>.from(currentProfile.heroLevels);
    newLevels.putIfAbsent(heroId, () => 1);
    final newExps = Map<String, int>.from(currentProfile.heroExp);
    newExps.putIfAbsent(heroId, () => 0);

    final updated = currentProfile.copyWith(
      gold: currentProfile.gold - price,
      unlockedHeroIds: newUnlocked,
      selectedHeroId: heroId,
      heroLevels: newLevels,
      heroExp: newExps,
    );
    await saveProfile(updated);
    return true;
  }

  /// Chọn nhân vật xuất chiến
  static Future<void> selectHero(String heroId) async {
    if (!currentProfile.unlockedHeroIds.contains(heroId)) return;
    final updated = currentProfile.copyWith(selectedHeroId: heroId);
    await saveProfile(updated);
    unawaited(FriendPartyService.instance.updateMyPartyHero(heroId));
  }

  /// Mở khóa Trợ thủ AI
  static Future<bool> unlockCompanion(String companionId, int price) async {
    if (!availableCompanionIds.contains(companionId)) return false;
    if (currentProfile.unlockedCompanionIds.contains(companionId)) return true;
    if (currentProfile.gold < price) return false;

    final newCompanions =
        List<String>.from(currentProfile.unlockedCompanionIds)..add(companionId);
    final updated = currentProfile.copyWith(
      gold: currentProfile.gold - price,
      unlockedCompanionIds: newCompanions,
      selectedCompanionId: companionId,
    );
    await saveProfile(updated);
    return true;
  }

  /// Trang bị / Gỡ trợ thủ AI
  static Future<void> selectCompanion(String? companionId) async {
    if (companionId != null && !availableCompanionIds.contains(companionId)) return;
    final updated = currentProfile.copyWith(
      selectedCompanionId: companionId,
      clearCompanion: companionId == null,
    );
    await saveProfile(updated);
  }
}
