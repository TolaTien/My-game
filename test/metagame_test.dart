import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_game/models/player_profile.dart';
import 'package:my_game/services/player_storage.dart';
import 'package:my_game/screens/lucky_wheel_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlayerProfile Tests', () {
    test('Hồ sơ mặc định khởi tạo chuẩn xác', () {
      final profile = PlayerProfile.defaultProfile();

      expect(profile.gold, 2000);
      expect(profile.diamonds, 50);
      expect(profile.rankPoints, 1000);
      expect(profile.rankTier, 'Đồng');
      expect(profile.unlockedHeroIds, ['george']);
      expect(profile.selectedHeroId, 'george');
      expect(profile.unlockedSkinIds, isEmpty);
      expect(profile.canSpinToday(), isTrue);
    });

    test('Xếp hạng Rank phân tầng chính xác theo Elo', () {
      expect(const PlayerProfile(rankPoints: 800).rankTier, 'Đồng');
      expect(const PlayerProfile(rankPoints: 1200).rankTier, 'Bạc');
      expect(const PlayerProfile(rankPoints: 1450).rankTier, 'Vàng');
      expect(const PlayerProfile(rankPoints: 1650).rankTier, 'Bạch Kim');
      expect(const PlayerProfile(rankPoints: 1850).rankTier, 'Kim Cương');
      expect(const PlayerProfile(rankPoints: 2100).rankTier, 'Thách Đấu');
    });

    test('Kiểm tra logic reset lượt quay 00:00 UTC (07:00 VN)', () {
      // 1. Chưa quay bao giờ
      final freshProfile = const PlayerProfile(lastSpinTimestamp: 0);
      expect(freshProfile.canSpinToday(), isTrue);

      // 2. Vừa quay hôm nay (theo giờ UTC)
      final spunToday = PlayerProfile(
        lastSpinTimestamp: DateTime.now().toUtc().millisecondsSinceEpoch,
      );
      expect(spunToday.canSpinToday(), isFalse);

      // 3. Đã quay từ hôm qua (UTC)
      final yesterdayUtc = DateTime.now().toUtc().subtract(const Duration(days: 1));
      final spunYesterday = PlayerProfile(
        lastSpinTimestamp: yesterdayUtc.millisecondsSinceEpoch,
      );
      expect(spunYesterday.canSpinToday(), isTrue);
    });

    test('Serialization toJson và fromJson bảo toàn dữ liệu', () {
      const original = PlayerProfile(
        playerName: 'Pro Player',
        gold: 85000,
        diamonds: 120,
        rankPoints: 1750,
        unlockedHeroIds: ['george', 'ranger'],
        selectedHeroId: 'ranger',
        unlockedSkinIds: ['skin_ranger_shadow'],
        selectedSkinId: 'skin_ranger_shadow',
        unlockedCompanionIds: ['comp_attack'],
        selectedCompanionId: 'comp_attack',
        lastSpinTimestamp: 1700000000000,
      );

      final json = original.toJson();
      final restored = PlayerProfile.fromJson(json);

      expect(restored.playerName, original.playerName);
      expect(restored.gold, original.gold);
      expect(restored.diamonds, original.diamonds);
      expect(restored.rankPoints, original.rankPoints);
      expect(restored.unlockedHeroIds, original.unlockedHeroIds);
      expect(restored.selectedHeroId, original.selectedHeroId);
      expect(restored.unlockedSkinIds, original.unlockedSkinIds);
      expect(restored.selectedSkinId, original.selectedSkinId);
      expect(restored.unlockedCompanionIds, original.unlockedCompanionIds);
      expect(restored.selectedCompanionId, original.selectedCompanionId);
      expect(restored.lastSpinTimestamp, original.lastSpinTimestamp);
    });

    test('fromJson gracefully parses floating-point num values without TypeError', () {
      final json = {
        'playerName': 'Float Player',
        'gold': 5000.0,
        'diamonds': 10.0,
        'rankPoints': 1450.5,
        'lastSpinTimestamp': 1700000000.0,
      };
      final profile = PlayerProfile.fromJson(json);

      expect(profile.playerName, 'Float Player');
      expect(profile.gold, 5000);
      expect(profile.diamonds, 10);
      expect(profile.rankPoints, 1450);
      expect(profile.lastSpinTimestamp, 1700000000);
    });
  });

  group('Lucky Wheel Reward Rule', () {
    test('Quy tắc tỷ giá cốt lõi: 1 Xu = 1000 Vàng', () {
      const reward10 = WheelReward(
        coins: 10,
        label: '10 Xu',
        primaryColor: Color(0xFF1E88E5),
        secondaryColor: Color(0xFF1565C0),
        icon: Icons.monetization_on_outlined,
      );
      expect(reward10.goldValue, 10000);

      const jackpot = WheelReward(
        coins: 100,
        label: '100 Xu',
        primaryColor: Color(0xFFFFB300),
        secondaryColor: Color(0xFFFF8F00),
        icon: Icons.military_tech_rounded,
        isJackpot: true,
      );
      expect(jackpot.goldValue, 100000);
    });
  });

  group('PlayerStorage SharedPreferences Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Lưu và đọc profile qua PlayerStorage', () async {
      await PlayerStorage.loadProfile();
      expect(PlayerStorage.currentProfile.gold, 2000);

      // Thử cộng vàng
      await PlayerStorage.addGold(5000);
      expect(PlayerStorage.currentProfile.gold, 7000);

      // Thử trừ vàng
      final spendSuccess = await PlayerStorage.spendGold(3000);
      expect(spendSuccess, isTrue);
      expect(PlayerStorage.currentProfile.gold, 4000);

      // Trừ quá số dư
      final overSpend = await PlayerStorage.spendGold(99999);
      expect(overSpend, isFalse);
      expect(PlayerStorage.currentProfile.gold, 4000);

      // Mở khóa tướng Ranger (giá 100 vàng)
      final unlockRanger = await PlayerStorage.unlockHero('ranger', 100);
      expect(unlockRanger, isTrue);
      expect(PlayerStorage.currentProfile.gold, 3900);
      expect(PlayerStorage.currentProfile.unlockedHeroIds, contains('ranger'));
      expect(PlayerStorage.currentProfile.selectedHeroId, 'ranger');

      // Ghi nhận vòng quay
      await PlayerStorage.recordSpin(20000);
      expect(PlayerStorage.currentProfile.gold, 23900);
      expect(PlayerStorage.currentProfile.canSpinToday(), isFalse);
    });
  });
}
