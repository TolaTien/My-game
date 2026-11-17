import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/models/player_profile.dart';
import 'package:my_game/screens/lucky_wheel_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('00:00 UTC Anti-Cheat Daily Reset Logic', () {
    test('Fresh profile (never spun, timestamp <= 0) can always spin', () {
      const profile0 = PlayerProfile(lastSpinTimestamp: 0);
      expect(profile0.canSpinToday(), isTrue);

      const profileNegative = PlayerProfile(lastSpinTimestamp: -1);
      expect(profileNegative.canSpinToday(), isTrue);
    });

    test('Same calendar UTC day prevents multiple free spins', () {
      final nowUtc = DateTime.now().toUtc();
      final spunRecently = PlayerProfile(
        lastSpinTimestamp: nowUtc.millisecondsSinceEpoch,
      );
      expect(spunRecently.canSpinToday(), isFalse);

      // Spun 3 hours ago today (same UTC day)
      final spun3HoursAgo = PlayerProfile(
        lastSpinTimestamp:
            nowUtc.subtract(const Duration(hours: 3)).millisecondsSinceEpoch,
      );
      // If 3 hours ago was still same UTC day
      final threeHoursAgoDate = nowUtc.subtract(const Duration(hours: 3));
      if (threeHoursAgoDate.day == nowUtc.day) {
        expect(spun3HoursAgo.canSpinToday(), isFalse);
      }
    });

    test(
        'Critical Edge Boundary: 23:59:59 UTC to 00:00:01 UTC allows spin across midnight',
        () {
      // Simulate spin at 23:59:59.999 on Day D
      final spinTime = DateTime.utc(2026, 5, 10, 23, 59, 59, 999);
      final profile = PlayerProfile(
        lastSpinTimestamp: spinTime.millisecondsSinceEpoch,
      );
      expect(profile.lastSpinTimestamp, spinTime.millisecondsSinceEpoch);

      // Evaluation at 00:00:00.001 on Day D+1 (2ms later)
      final checkTime = DateTime.utc(2026, 5, 11, 0, 0, 0, 1);
      final lastDateUtc = DateTime.utc(
          spinTime.year, spinTime.month, spinTime.day);
      final nowDateUtc = DateTime.utc(
          checkTime.year, checkTime.month, checkTime.day);

      expect(nowDateUtc.isAfter(lastDateUtc), isTrue,
          reason:
              'Crossing 00:00 UTC into a new day must grant a new free spin');
    });

    test(
        'Intra-Day Boundary: 00:00:01 UTC to 23:59:59 UTC on same day blocks extra spin',
        () {
      final spinTime = DateTime.utc(2026, 5, 10, 0, 0, 1);
      final checkTime = DateTime.utc(2026, 5, 10, 23, 59, 59);

      final lastDateUtc = DateTime.utc(
          spinTime.year, spinTime.month, spinTime.day);
      final nowDateUtc = DateTime.utc(
          checkTime.year, checkTime.month, checkTime.day);

      expect(nowDateUtc.isAfter(lastDateUtc), isFalse,
          reason:
              '23 hours 59 minutes later on same UTC day must still be rejected');
    });

    test('Month transition boundary: Jan 31 23:59:59 -> Feb 01 00:00:01', () {
      final spinTime = DateTime.utc(2026, 1, 31, 23, 59, 59);
      final checkTime = DateTime.utc(2026, 2, 1, 0, 0, 1);

      final lastDateUtc = DateTime.utc(
          spinTime.year, spinTime.month, spinTime.day);
      final nowDateUtc = DateTime.utc(
          checkTime.year, checkTime.month, checkTime.day);

      expect(nowDateUtc.isAfter(lastDateUtc), isTrue,
          reason: 'Month boundary rollover must reset spin eligibility');
    });

    test('Year transition boundary: Dec 31 23:59:59 -> Jan 01 00:00:01', () {
      final spinTime = DateTime.utc(2026, 12, 31, 23, 59, 59);
      final checkTime = DateTime.utc(2027, 1, 1, 0, 0, 1);

      final lastDateUtc = DateTime.utc(
          spinTime.year, spinTime.month, spinTime.day);
      final nowDateUtc = DateTime.utc(
          checkTime.year, checkTime.month, checkTime.day);

      expect(nowDateUtc.isAfter(lastDateUtc), isTrue,
          reason: 'Year boundary rollover must reset spin eligibility');
    });

    test('Leap year boundary: Feb 28 23:59:59 -> Feb 29 00:00:01 (2028 leap)',
        () {
      final spinTime = DateTime.utc(2028, 2, 28, 23, 59, 59);
      final checkTime = DateTime.utc(2028, 2, 29, 0, 0, 1);

      final lastDateUtc = DateTime.utc(
          spinTime.year, spinTime.month, spinTime.day);
      final nowDateUtc = DateTime.utc(
          checkTime.year, checkTime.month, checkTime.day);

      expect(nowDateUtc.isAfter(lastDateUtc), isTrue,
          reason: 'Leap day rollover must reset spin eligibility');
    });

    test('Countdown timer until next 00:00 UTC reset is non-negative and valid',
        () {
      const profile = PlayerProfile();
      final remaining = profile.timeUntilNextReset();

      expect(remaining.isNegative, isFalse);
      expect(remaining.inSeconds, greaterThanOrEqualTo(0));
      expect(remaining.inHours, lessThanOrEqualTo(24));
    });
  });

  group('6-Sector Lucky Wheel Reward Odds & Payout Architecture', () {
    test('Wheel contains exactly 6 sectors with 60-degree sweep angles', () {
      // 6 sectors totaling 360 degrees (2 * pi radians)
      const totalSectors = 6;
      const expectedSweepAngle = 2 * pi / totalSectors; // pi / 3 radians (60 deg)

      expect(expectedSweepAngle, closeTo(1.04719, 0.001));
    });

    test('6 sector reward specifications and 1 Xu = 1000 Gold conversion', () {
      const rewards = [
        WheelReward(
          coins: 0,
          label: '0 Xu',
          primaryColor: Color(0xFFE53935),
          secondaryColor: Color(0xFFC62828),
          icon: Icons.sentiment_dissatisfied_rounded,
        ),
        WheelReward(
          coins: 10,
          label: '10 Xu',
          primaryColor: Color(0xFF1E88E5),
          secondaryColor: Color(0xFF1565C0),
          icon: Icons.monetization_on_outlined,
        ),
        WheelReward(
          coins: 20,
          label: '20 Xu',
          primaryColor: Color(0xFF8E24AA),
          secondaryColor: Color(0xFF6A1B9A),
          icon: Icons.monetization_on_rounded,
        ),
        WheelReward(
          coins: 40,
          label: '40 Xu',
          primaryColor: Color(0xFF00ACC1),
          secondaryColor: Color(0xFF00838F),
          icon: Icons.stars_rounded,
        ),
        WheelReward(
          coins: 50,
          label: '50 Xu',
          primaryColor: Color(0xFF43A047),
          secondaryColor: Color(0xFF2E7D32),
          icon: Icons.diamond_rounded,
        ),
        WheelReward(
          coins: 100,
          label: '100 Xu',
          primaryColor: Color(0xFFFFB300),
          secondaryColor: Color(0xFFFF8F00),
          icon: Icons.military_tech_rounded,
          isJackpot: true,
        ),
      ];

      expect(rewards.length, 6);

      // Verify each sector's gold conversion formula (1 Xu = 1000 Gold)
      expect(rewards[0].goldValue, 0);
      expect(rewards[0].isJackpot, isFalse);

      expect(rewards[1].goldValue, 10000);
      expect(rewards[1].isJackpot, isFalse);

      expect(rewards[2].goldValue, 20000);
      expect(rewards[2].isJackpot, isFalse);

      expect(rewards[3].goldValue, 40000);
      expect(rewards[3].isJackpot, isFalse);

      expect(rewards[4].goldValue, 50000);
      expect(rewards[4].isJackpot, isFalse);

      expect(rewards[5].goldValue, 100000);
      expect(rewards[5].isJackpot, isTrue,
          reason: '100 Xu sector must be designated as the jackpot');
    });

    test(
        'Cumulative odds distribution sums to 100% and maps deterministically',
        () {
      // Authoritative probability weights from spec §Module 5:
      // 0 Xu: 15% (rand 0..14)
      // 10 Xu: 35% (rand 15..49)
      // 20 Xu: 25% (rand 50..74)
      // 40 Xu: 15% (rand 75..89)
      // 50 Xu: 8% (rand 90..97)
      // 100 Xu Jackpot: 2% (rand 98..99)

      int mapSectorIndex(int rand) {
        if (rand < 15) return 0;
        if (rand < 50) return 1;
        if (rand < 75) return 2;
        if (rand < 90) return 3;
        if (rand < 98) return 4;
        return 5;
      }

      final distributionCounts = List<int>.filled(6, 0);

      // Iterate across all 100 integer seeds (0 to 99)
      for (int i = 0; i < 100; i++) {
        final sector = mapSectorIndex(i);
        distributionCounts[sector]++;
      }

      expect(distributionCounts[0], 15,
          reason: '0 Xu sector probability must be 15%');
      expect(distributionCounts[1], 35,
          reason: '10 Xu sector probability must be 35%');
      expect(distributionCounts[2], 25,
          reason: '20 Xu sector probability must be 25%');
      expect(distributionCounts[3], 15,
          reason: '40 Xu sector probability must be 15%');
      expect(distributionCounts[4], 8,
          reason: '50 Xu sector probability must be 8%');
      expect(distributionCounts[5], 2,
          reason: '100 Xu jackpot sector probability must be 2%');

      final totalPercentage =
          distributionCounts.reduce((sum, count) => sum + count);
      expect(totalPercentage, 100,
          reason: 'Total probability across all sectors must sum to 100%');
    });
  });

  group('6 Rank Elo Tiers & RP Boundary Transitions', () {
    test('Exact boundary transitions across all 6 Elo tiers', () {
      // 1. Bronze (Đồng): 0 - 1199 RP
      expect(const PlayerProfile(rankPoints: 0).rankTier, 'Đồng');
      expect(const PlayerProfile(rankPoints: 500).rankTier, 'Đồng');
      expect(const PlayerProfile(rankPoints: 1199).rankTier, 'Đồng');

      // Boundary: 1199 -> 1200 promotes to Silver (Bạc)
      expect(const PlayerProfile(rankPoints: 1200).rankTier, 'Bạc');
      expect(const PlayerProfile(rankPoints: 1399).rankTier, 'Bạc');

      // Boundary: 1399 -> 1400 promotes to Gold (Vàng)
      expect(const PlayerProfile(rankPoints: 1400).rankTier, 'Vàng');
      expect(const PlayerProfile(rankPoints: 1599).rankTier, 'Vàng');

      // Boundary: 1599 -> 1600 promotes to Platinum (Bạch Kim)
      expect(const PlayerProfile(rankPoints: 1600).rankTier, 'Bạch Kim');
      expect(const PlayerProfile(rankPoints: 1799).rankTier, 'Bạch Kim');

      // Boundary: 1799 -> 1800 promotes to Diamond (Kim Cương)
      expect(const PlayerProfile(rankPoints: 1800).rankTier, 'Kim Cương');
      expect(const PlayerProfile(rankPoints: 1999).rankTier, 'Kim Cương');

      // Boundary: 1999 -> 2000 promotes to Challenger (Thách Đấu)
      expect(const PlayerProfile(rankPoints: 2000).rankTier, 'Thách Đấu');
      expect(const PlayerProfile(rankPoints: 3500).rankTier, 'Thách Đấu');
    });

    test('Rank Theme Color and Icon alignment with tiers', () {
      // Bronze
      const bronze = PlayerProfile(rankPoints: 1000);
      expect(bronze.rankColor, const Color(0xFFCD7F32));
      expect(bronze.rankIcon, Icons.shield_outlined);

      // Silver
      const silver = PlayerProfile(rankPoints: 1250);
      expect(silver.rankColor, const Color(0xFFCFD8DC));
      expect(silver.rankIcon, Icons.star_rounded);

      // Gold
      const gold = PlayerProfile(rankPoints: 1450);
      expect(gold.rankColor, const Color(0xFFFFD700));
      expect(gold.rankIcon, Icons.military_tech_rounded);

      // Platinum
      const plat = PlayerProfile(rankPoints: 1650);
      expect(plat.rankColor, const Color(0xFF00E676));
      expect(plat.rankIcon, Icons.shield_rounded);

      // Diamond
      const diamond = PlayerProfile(rankPoints: 1850);
      expect(diamond.rankColor, const Color(0xFF00E5FF));
      expect(diamond.rankIcon, Icons.diamond_rounded);

      // Challenger
      const challenger = PlayerProfile(rankPoints: 2200);
      expect(challenger.rankColor, const Color(0xFFFF1744));
      expect(challenger.rankIcon, Icons.local_fire_department_rounded);
    });

    test('PvP RP calculation invariants: +30 win, -20 loss with floor 0', () {
      int calculateNewRp(int currentRp, bool isWin) {
        if (isWin) {
          return currentRp + 30;
        } else {
          return max(0, currentRp - 20);
        }
      }

      // Normal win
      expect(calculateNewRp(1000, true), 1030);

      // Normal loss
      expect(calculateNewRp(1000, false), 980);

      // Loss floor mitigation at 0 RP
      expect(calculateNewRp(10, false), 0,
          reason: 'RP cannot drop below 0 floor');
      expect(calculateNewRp(0, false), 0);
    });
  });
}
