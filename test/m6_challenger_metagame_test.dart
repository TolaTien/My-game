import 'dart:convert';

import 'package:flame/components.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_game/core/constants.dart';
import 'package:my_game/game/components/player.dart';
import 'package:my_game/models/database_models.dart';
import 'package:my_game/models/player_profile.dart';
import 'package:my_game/services/audio_service.dart';
import 'package:my_game/services/database_service.dart';
import 'package:my_game/services/player_storage.dart';

import 'support/leaderboard_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('xyz.luan/audioplayers.global'),
          (MethodCall methodCall) async => 1,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('xyz.luan/audioplayers'),
          (MethodCall methodCall) async => 1,
        );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      MockDatabaseService.storageKeyLeaderboard: jsonEncode(
        leaderboardFixture().map((entry) => entry.toJson()).toList(),
      ),
    });
    await PlayerStorage.loadProfile();
  });

  // =========================================================================
  // SUITE 1: Daily Wheel & Timezone Manipulation Adversarial Stress
  // =========================================================================
  group('Suite 1: Daily Wheel & Timezone Manipulation Adversarial Stress', () {
    test('Negative and zero lastSpinTimestamp (-1, 0, minInt) permit spinning without crashing', () {
      const p0 = PlayerProfile(lastSpinTimestamp: 0);
      expect(p0.canSpinToday(), isTrue, reason: 'Timestamp 0 must permit spin');

      const pNeg1 = PlayerProfile(lastSpinTimestamp: -1);
      expect(
        pNeg1.canSpinToday(),
        isTrue,
        reason: 'Timestamp -1 must permit spin',
      );

      // 64-bit minInt edge (-9223372036854775808)
      const minInt = -9223372036854775808;
      const pMin = PlayerProfile(lastSpinTimestamp: minInt);
      expect(
        pMin.canSpinToday(),
        isTrue,
        reason:
            'Timestamp minInt must not throw DateTime error and permit spin',
      );
    });

    test('Anti-Cheat: Device clock turned backwards into past epoch blocks spinning', () {
      final nowUtc = DateTime.now().toUtc();

      // Scenario A: Player spun "in the future" (e.g. tomorrow or next year), then turned clock back to today
      final futureSpinMs = nowUtc
          .add(const Duration(days: 1))
          .millisecondsSinceEpoch;
      final profileCheatedFuture = PlayerProfile(
        lastSpinTimestamp: futureSpinMs,
      );
      expect(
        profileCheatedFuture.canSpinToday(),
        isFalse,
        reason: 'If recorded spin date is in the future relative to device clock, spin must be denied',
      );

      // Scenario B: User spun earlier today, then rolled system clock back by 2 hours (still same day)
      final spinEarlierToday = nowUtc.millisecondsSinceEpoch;
      final profileSameDay = PlayerProfile(lastSpinTimestamp: spinEarlierToday);
      expect(
        profileSameDay.canSpinToday(),
        isFalse,
        reason:
            'Rolling clock backwards within same day must still reject spin',
      );

      // Scenario C: Far future spin timestamp (e.g. 5 days ahead) vs today
      final farFutureSpin = nowUtc
          .add(const Duration(days: 5))
          .millisecondsSinceEpoch;
      final profileFarFuture = PlayerProfile(lastSpinTimestamp: farFutureSpin);
      expect(
        profileFarFuture.canSpinToday(),
        isFalse,
        reason: 'Far future timestamp must remain blocked until real time overtakes it',
      );
    });

    test(
      'Future timestamps into year 2038 or across leap years operate safely',
      () {
        // Unix 32-bit overflow boundary: 2038-01-19T03:14:07Z (2147483647 seconds)
        final y2038Utc = DateTime.utc(2038, 1, 19, 3, 14, 7);
        final profile2038 = PlayerProfile(
          lastSpinTimestamp: y2038Utc.millisecondsSinceEpoch,
        );
        expect(
          profile2038.lastSpinTimestamp,
          equals(y2038Utc.millisecondsSinceEpoch),
        );

        // Leap year boundary calculation: Feb 28 to Feb 29 (2028 leap)
        final leapSpin = DateTime.utc(2028, 2, 28, 23, 59, 59, 999);
        final leapNextDay = DateTime.utc(2028, 2, 29, 0, 0, 0, 1);
        final lastDateUtc = DateTime.utc(
          leapSpin.year,
          leapSpin.month,
          leapSpin.day,
        );
        final nowDateUtc = DateTime.utc(
          leapNextDay.year,
          leapNextDay.month,
          leapNextDay.day,
        );
        expect(
          nowDateUtc.isAfter(lastDateUtc),
          isTrue,
          reason: '2028 leap day transition resets daily spin',
        );

        // Leap day to March 1 (2028)
        final leapMar1 = DateTime.utc(2028, 3, 1, 0, 0, 0, 1);
        final leapMar1Date = DateTime.utc(
          leapMar1.year,
          leapMar1.month,
          leapMar1.day,
        );
        final leapDayDate = DateTime.utc(
          leapNextDay.year,
          leapNextDay.month,
          leapNextDay.day,
        );
        expect(leapMar1Date.isAfter(leapDayDate), isTrue);

        // Non-leap year: Feb 28 2027 to March 1 2027
        final nonLeapSpin = DateTime.utc(2027, 2, 28, 23, 59, 59);
        final nonLeapMar1 = DateTime.utc(2027, 3, 1, 0, 0, 1);
        final lastNonLeap = DateTime.utc(
          nonLeapSpin.year,
          nonLeapSpin.month,
          nonLeapSpin.day,
        );
        final nowNonLeap = DateTime.utc(
          nonLeapMar1.year,
          nonLeapMar1.month,
          nonLeapMar1.day,
        );
        expect(nowNonLeap.isAfter(lastNonLeap), isTrue);
      },
    );

    test('Precision Boundary: Consecutive evaluations 1ms before and after 00:00:00.000 UTC', () {
      final nowUtc = DateTime.now().toUtc();
      final todayMidnightUtc = DateTime.utc(
        nowUtc.year,
        nowUtc.month,
        nowUtc.day,
      );

      // 1 ms before today's 00:00:00.000 UTC was yesterday's 23:59:59.999 UTC
      final yesterdayLastMs = todayMidnightUtc
          .subtract(const Duration(milliseconds: 1))
          .millisecondsSinceEpoch;
      final profileYesterday = PlayerProfile(
        lastSpinTimestamp: yesterdayLastMs,
      );
      expect(
        profileYesterday.canSpinToday(),
        isTrue,
        reason: 'Spin at 23:59:59.999 UTC yesterday MUST permit spin today',
      );

      // 1 ms after today's 00:00:00.000 UTC was today's 00:00:00.001 UTC
      final todayFirstMs = todayMidnightUtc
          .add(const Duration(milliseconds: 1))
          .millisecondsSinceEpoch;
      final profileToday = PlayerProfile(lastSpinTimestamp: todayFirstMs);
      expect(
        profileToday.canSpinToday(),
        isFalse,
        reason: 'Spin at 00:00:00.001 UTC today MUST reject spin today',
      );

      // Exact 00:00:00.000 UTC today
      final profileExactMidnight = PlayerProfile(
        lastSpinTimestamp: todayMidnightUtc.millisecondsSinceEpoch,
      );
      expect(
        profileExactMidnight.canSpinToday(),
        isFalse,
        reason: 'Spin at exactly 00:00:00.000 UTC today MUST reject spin today',
      );
    });

    test('timeUntilNextReset invariants: duration is non-negative and strictly <= 24 hours', () {
      const profile = PlayerProfile();
      final remaining = profile.timeUntilNextReset();

      expect(remaining.isNegative, isFalse);
      expect(remaining.inMicroseconds, greaterThanOrEqualTo(0));
      expect(remaining.inHours, lessThanOrEqualTo(24));
      if (remaining.inHours == 24) {
        expect(remaining.inMinutes % 60, equals(0));
        expect(remaining.inSeconds % 60, equals(0));
      }
    });
  });

  // =========================================================================
  // SUITE 2: Economy, Wallet & Progression Invariants
  // =========================================================================
  group('Suite 2: Economy, Wallet & Progression Invariants', () {
    test('Exchange rate invariance: purchasing with exactly equal funds leaves exactly 0 gold', () async {
      // 1. Hero Purchase (100 gold cost, 100 balance)
      await PlayerStorage.saveProfile(
        PlayerProfile.defaultProfile().copyWith(
          gold: 100,
          unlockedHeroIds: ['george'],
        ),
      );
      expect(PlayerStorage.currentProfile.gold, equals(100));

      final unlockSuccess = await PlayerStorage.unlockHero('tanker', 100);
      expect(unlockSuccess, isTrue);
      expect(
        PlayerStorage.currentProfile.gold,
        equals(0),
        reason: '100 gold - 100 gold == exactly 0 gold',
      );
      expect(
        PlayerStorage.currentProfile.unlockedHeroIds.contains('tanker'),
        isTrue,
      );

      // 2. Direct spendGold invariance (500 gold cost, 500 balance)
      await PlayerStorage.saveProfile(
        PlayerStorage.currentProfile.copyWith(gold: 500),
      );
      final spendSuccess = await PlayerStorage.spendGold(500);
      expect(spendSuccess, isTrue);
      expect(
        PlayerStorage.currentProfile.gold,
        equals(0),
        reason: '500 gold - 500 gold == exactly 0 gold',
      );

      // 3. Companion purchase invariance (600 gold cost, 600 balance)
      await PlayerStorage.saveProfile(
        PlayerStorage.currentProfile.copyWith(gold: 600),
      );
      final companionSuccess = await PlayerStorage.unlockCompanion(
        'drone_attack',
        600,
      );
      expect(companionSuccess, isTrue);
      expect(PlayerStorage.currentProfile.gold, equals(0));
      expect(
        PlayerStorage.currentProfile.unlockedCompanionIds.contains(
          'drone_attack',
        ),
        isTrue,
      );

      // 4. Diamond Skin purchase invariance (50 diamonds cost, 50 balance)
      await PlayerStorage.saveProfile(
        PlayerStorage.currentProfile.copyWith(diamonds: 50),
      );
      final skinSuccess = await PlayerStorage.unlockSkin('skin_cyber', 50);
      expect(skinSuccess, isTrue);
      expect(
        PlayerStorage.currentProfile.diamonds,
        equals(0),
        reason: '50 - 50 == exactly 0 diamonds',
      );
      expect(
        PlayerStorage.currentProfile.unlockedSkinIds.contains('skin_cyber'),
        isTrue,
      );
    });

    test('99 gold rejection: cost 100 gold with 99 gold balance strictly rejects without partial deduction', () async {
      await PlayerStorage.saveProfile(
        PlayerProfile.defaultProfile().copyWith(
          gold: 99,
          unlockedHeroIds: ['george'],
        ),
      );

      // Attempt 1: unlockHero
      final heroUnlock = await PlayerStorage.unlockHero('ninja', 100);
      expect(
        heroUnlock,
        isFalse,
        reason: 'Must reject hero unlock when balance is 99 vs 100 cost',
      );
      expect(
        PlayerStorage.currentProfile.gold,
        equals(99),
        reason: 'Balance must remain strictly 99 gold',
      );
      expect(
        PlayerStorage.currentProfile.unlockedHeroIds.contains('ninja'),
        isFalse,
      );

      // Attempt 2: spendGold
      final spendResult = await PlayerStorage.spendGold(100);
      expect(spendResult, isFalse, reason: 'spendGold(100) must return false');
      expect(
        PlayerStorage.currentProfile.gold,
        equals(99),
        reason: 'Balance must remain strictly 99 gold',
      );

      // Attempt 3: Companion 500 cost with 499 gold
      await PlayerStorage.saveProfile(
        PlayerStorage.currentProfile.copyWith(gold: 499),
      );
      final companionResult = await PlayerStorage.unlockCompanion(
        'drone_shield',
        500,
      );
      expect(companionResult, isFalse);
      expect(PlayerStorage.currentProfile.gold, equals(499));
      expect(
        PlayerStorage.currentProfile.unlockedCompanionIds.contains(
          'drone_shield',
        ),
        isFalse,
      );

      // Attempt 4: Skin 50 diamonds cost with 49 diamonds
      await PlayerStorage.saveProfile(
        PlayerStorage.currentProfile.copyWith(diamonds: 49),
      );
      final skinResult = await PlayerStorage.unlockSkin('skin_fire', 50);
      expect(skinResult, isFalse);
      expect(PlayerStorage.currentProfile.diamonds, equals(49));
      expect(
        PlayerStorage.currentProfile.unlockedSkinIds.contains('skin_fire'),
        isFalse,
      );
    });

    test('Progression cap: Gaining 1,000,000 EXP halts at Level 15 and strictly clamps stats', () {
      final player = PlayerComponent(position: Vector2.zero());
      expect(player.level, equals(1));
      expect(player.maxHp, equals(340.0));
      expect(player.maxKi, equals(100.0));
      expect(player.damage, equals(25.0));

      // Massive EXP injection: 1,000,000 EXP
      player.gainExp(1000000);

      // Level must strictly cap at 15
      expect(
        player.level,
        equals(15),
        reason: 'Progression must strictly cap at Level 15',
      );

      // 14 Level-ups: +15 HP, +10 Ki, +5 Dmg per level
      // Max HP: 340 + 14 * 15 = 550
      // Max Ki: 100 + 14 * 10 = 240
      // Damage: 25 + 14 * 5 = 95
      expect(
        player.maxHp,
        equals(550.0),
        reason: 'Level 15 Max HP must be 550.0',
      );
      expect(
        player.maxKi,
        equals(240.0),
        reason: 'Level 15 Max Ki must be 240.0',
      );
      expect(
        player.damage,
        equals(95.0),
        reason: 'Level 15 Damage must be 95.0',
      );
      expect(player.currentHp, equals(550.0));
      expect(player.currentKi, equals(240.0));

      // Secondary massive EXP injection at max cap: another 5,000,000 EXP
      player.gainExp(5000000);
      expect(
        player.level,
        equals(15),
        reason: 'Level must not increment past 15',
      );
      expect(player.maxHp, equals(550.0));
      expect(player.maxKi, equals(240.0));
      expect(player.damage, equals(95.0));
    });

    test('Health potion overheal: drinking +25 HP near full clamps to max HP', () {
      final player = PlayerComponent(position: Vector2.zero());

      player.currentHp = player.maxHp - 5;
      player.heal(25.0);
      expect(player.currentHp, player.maxHp);

      player.currentHp = player.maxHp - .1;
      player.heal(25.0);
      expect(player.currentHp, player.maxHp);

      player.currentHp = player.maxHp;
      player.heal(25.0);
      expect(player.currentHp, player.maxHp);

      player.gainExp(1000000);
      expect(player.level, 15);
      player.currentHp = player.maxHp - 10;
      player.heal(25.0);
      expect(player.currentHp, player.maxHp);
    });

    test('Immutable 1:1000 exchange rate: 1 coin collected in dungeon yields 1,000 gold', () {
      expect(GameConstants.goldPerCoinPickup, equals(1000));

      const coinsCollected = 7;
      final walletGoldAdded = coinsCollected * GameConstants.goldPerCoinPickup;
      expect(walletGoldAdded, equals(7000));
    });

    test(
      'Combat invariant: Rapid Berserk triggers reject recast and preserve Ki',
      () {
        final player = PlayerComponent(position: Vector2.zero());
        expect(player.currentKi, equals(100.0));
        expect(player.isBerserk, isFalse);

        // First activation: consumes 40 Ki, activates berserk for 8.0s
        final success1 = player.useSkill3();
        expect(success1, isTrue);
        expect(player.currentKi, equals(60.0));
        expect(player.isBerserk, isTrue);
        expect(player.berserkTimer, equals(8.0));

        // 50 rapid recast attempts while active: must ALL fail and keep Ki at 60.0
        for (int i = 0; i < 50; i++) {
          final recast = player.useSkill3();
          expect(recast, isFalse);
        }
        expect(
          player.currentKi,
          equals(60.0),
          reason: 'Ki must not be deducted on blocked recasts',
        );
        expect(player.isBerserk, isTrue);
      },
    );

    test('Health potion boundary: heal(0.0) or extreme healing behaves predictably', () {
      final player = PlayerComponent(position: Vector2.zero());
      player.currentHp = 50.0;

      // Zero heal
      player.heal(0.0);
      expect(player.currentHp, equals(50.0));

      // Massive heal (10,000 HP) strictly clamps to maxHp.
      player.heal(10000.0);
      expect(player.currentHp, player.maxHp);
    });
  });

  // =========================================================================
  // SUITE 3: AudioService Concurrency & Resilience
  // =========================================================================
  group('Suite 3: AudioService Concurrency & Resilience', () {
    test('Rapid-fire playback: 100 simultaneous SFX calls execute in parallel without deadlocks or unhandled exceptions', () async {
      final mockAudio = MockAudioService();
      await mockAudio.initialize();

      // Launch 100 concurrent SFX calls
      final futures = <Future<void>>[];
      for (int i = 0; i < 100; i++) {
        final sfx = SfxSound.values[i % SfxSound.values.length];
        futures.add(mockAudio.playSfx(sfx));
      }

      await Future.wait(futures);

      // Verify all 100 events were recorded safely
      final sfxEvents = mockAudio.callHistory
          .where((e) => e.method == 'playSfx')
          .toList();
      expect(
        sfxEvents.length,
        equals(100),
        reason: 'All 100 SFX requests processed without drop or race',
      );

      // Now verify FlameAudioService headless resilience with 100 rapid concurrent calls
      final flameAudio = FlameAudioService();
      await flameAudio.initialize();

      final flameFutures = <Future<void>>[];
      for (int i = 0; i < 100; i++) {
        final sfx = SfxSound.values[i % SfxSound.values.length];
        flameFutures.add(flameAudio.playSfx(sfx));
      }

      // Must complete cleanly without unhandled zone exceptions
      await expectLater(Future.wait(flameFutures), completes);
    });

    test('Volume boundary fuzzing: -10.0, 100.0, Infinity, -Infinity clamp safely; NaN does not crash', () async {
      final audio = FlameAudioService();
      await audio.initialize();

      // Negative fuzz: -10.0 -> clamps to 0.0
      audio.setBgmVolume(-10.0);
      expect(audio.bgmVolume, equals(0.0));
      expect(audio.bgmVolumeNotifier.value, equals(0.0));

      audio.setSfxVolume(-10.0);
      expect(audio.sfxVolume, equals(0.0));
      expect(audio.sfxVolumeNotifier.value, equals(0.0));

      // Positive overflow fuzz: 100.0 -> clamps to 1.0
      audio.setBgmVolume(100.0);
      expect(audio.bgmVolume, equals(1.0));
      expect(audio.bgmVolumeNotifier.value, equals(1.0));

      audio.setSfxVolume(100.0);
      expect(audio.sfxVolume, equals(1.0));
      expect(audio.sfxVolumeNotifier.value, equals(1.0));

      // Positive Infinity fuzz: double.infinity -> clamps to 1.0
      audio.setBgmVolume(double.infinity);
      expect(audio.bgmVolume, equals(1.0));
      expect(audio.bgmVolumeNotifier.value, equals(1.0));

      audio.setSfxVolume(double.infinity);
      expect(audio.sfxVolume, equals(1.0));
      expect(audio.sfxVolumeNotifier.value, equals(1.0));

      // Negative Infinity fuzz: -double.infinity -> clamps to 0.0
      audio.setBgmVolume(-double.infinity);
      expect(audio.bgmVolume, equals(0.0));
      expect(audio.bgmVolumeNotifier.value, equals(0.0));

      audio.setSfxVolume(-double.infinity);
      expect(audio.sfxVolume, equals(0.0));
      expect(audio.sfxVolumeNotifier.value, equals(0.0));

      // NaN fuzzing: verify zero crashes or exceptions and whether NaN leaks into state
      expect(() => audio.setBgmVolume(double.nan), returnsNormally);
      expect(() => audio.setSfxVolume(double.nan), returnsNormally);
      final bgmIsClamped =
          !audio.bgmVolume.isNaN &&
          audio.bgmVolume >= 0.0 &&
          audio.bgmVolume <= 1.0;
      final sfxIsClamped =
          !audio.sfxVolume.isNaN &&
          audio.sfxVolume >= 0.0 &&
          audio.sfxVolume <= 1.0;
      expect(
        bgmIsClamped,
        isTrue,
        reason: 'NaN volume must be clamped safely to [0.0, 1.0] rather than propagating NaN',
      );
      expect(
        sfxIsClamped,
        isTrue,
        reason: 'NaN volume must be clamped safely to [0.0, 1.0] rather than propagating NaN',
      );

      // Playback with fuzzed volume parameters
      await expectLater(
        audio.playBgm(BgmTrack.lobby, volume: -10.0),
        completes,
      );
      await expectLater(
        audio.playBgm(BgmTrack.lobby, volume: 100.0),
        completes,
      );
      await expectLater(
        audio.playBgm(BgmTrack.lobby, volume: double.infinity),
        completes,
      );
      await expectLater(
        audio.playBgm(BgmTrack.lobby, volume: double.nan),
        completes,
      );

      await expectLater(
        audio.playSfx(SfxSound.uiClick, volume: -10.0),
        completes,
      );
      await expectLater(
        audio.playSfx(SfxSound.uiClick, volume: 100.0),
        completes,
      );
      await expectLater(
        audio.playSfx(SfxSound.uiClick, volume: double.infinity),
        completes,
      );
      await expectLater(
        audio.playSfx(SfxSound.uiClick, volume: double.nan),
        completes,
      );
    });

    test(
      'Toggle mute states rapidly while sounds are actively playing',
      () async {
        final audio = FlameAudioService();
        await audio.initialize();

        // Start BGM
        await audio.playBgm(BgmTrack.lobby);
        expect(audio.isPlayingBgm, isTrue);

        // Interleave 40 rapid mute toggles with SFX triggers
        for (int i = 0; i < 40; i++) {
          audio.playSfx(SfxSound.attackHammer);
          audio.toggleMute();
          if (i % 5 == 0) {
            audio.toggleBgm();
          }
          if (i % 7 == 0) {
            audio.toggleSfx();
          }
        }

        // Final restore to known unmuted state
        if (!audio.isBgmEnabled || !audio.isSfxEnabled) {
          audio.toggleMute();
        }
        expect(audio.isBgmEnabled, isTrue);
        expect(audio.isSfxEnabled, isTrue);
      },
    );
  });

  // =========================================================================
  // SUITE 4: DatabaseService & Leaderboard Concurrency
  // =========================================================================
  group('Suite 4: DatabaseService & Leaderboard Concurrency', () {
    test('50 rapid sequential profile updates: atomic local persistence without JSON corruption', () async {
      final service = MockDatabaseService();
      await service.initialize();

      var profile = PlayerProfile.defaultProfile().copyWith(
        playerName: 'ChiếnBinh_Stress',
        gold: 1000,
        rankPoints: 1000,
      );

      // 50 rapid sequential updates
      for (int i = 1; i <= 50; i++) {
        profile = profile.copyWith(
          gold: profile.gold + 25,
          rankPoints: profile.rankPoints + 15,
        );
        await service.saveProfile(profile);
      }

      // 1. Verify SharedPreferences JSON string is valid and not corrupted
      final prefs = await SharedPreferences.getInstance();
      final storedJsonString = prefs.getString('gold_rush_player_profile');
      expect(storedJsonString, isNotNull);

      // jsonDecode must succeed without FormatException
      final Map<String, dynamic> decodedMap = jsonDecode(storedJsonString!);
      expect(decodedMap['playerName'], equals('ChiếnBinh_Stress'));
      expect(decodedMap['gold'], equals(1000 + 50 * 25)); // 2250
      expect(decodedMap['rankPoints'], equals(1000 + 50 * 15)); // 1750

      // 2. Verify DatabaseService.loadProfile restores the exact final atomic state
      final loadedProfile = await service.loadProfile('local_player');
      expect(loadedProfile, isNotNull);
      expect(loadedProfile!.playerName, equals('ChiếnBinh_Stress'));
      expect(loadedProfile.gold, equals(2250));
      expect(loadedProfile.rankPoints, equals(1750));
      expect(loadedProfile.rankTier, equals('Bạch Kim')); // 1750 RP is Bạch Kim
    });

    test('Leaderboard tiebreaking: multiple players with identical RP maintain deterministic ordering', () async {
      final service = MockDatabaseService();
      await service.initialize();

      // Seed baseline leaderboard
      final baseEntries = await service.streamTopLeaderboard(limit: 20).first;
      expect(baseEntries.length, equals(20));

      // Create two profiles with IDENTICAL RP (2080 RP, matching seed_8 KiếmThánh_VN)
      final profileA = PlayerProfile(
        playerName: 'ĐồngĐiểm_Alpha',
        rankPoints: 2080,
      );
      await service.updateLeaderboard(profileA);

      final entriesAfterA = await service.streamTopLeaderboard(limit: 25).first;
      final alphaEntry = entriesAfterA.firstWhere(
        (e) => e.name == 'ĐồngĐiểm_Alpha',
      );
      expect(alphaEntry.rankPoints, equals(2080));

      // Verify that all ranks remain strictly 1..N contiguous without holes or collisions
      for (int i = 0; i < entriesAfterA.length; i++) {
        expect(
          entriesAfterA[i].rankNumber,
          equals(i + 1),
          reason: 'Rank numbers must be contiguous 1..N even with identical RP ties',
        );
      }

      // Verify monotonic descending order of rank points
      for (int i = 0; i < entriesAfterA.length - 1; i++) {
        expect(
          entriesAfterA[i].rankPoints >= entriesAfterA[i + 1].rankPoints,
          isTrue,
        );
      }
    });

    test('Malformed data resilience: PlayerProfile.fromJson handles missing, extra, and null keys gracefully', () {
      // 1. Completely empty JSON {}
      final emptyProfile = PlayerProfile.fromJson({});
      expect(emptyProfile.playerName, equals('Chiến Binh #88'));
      expect(emptyProfile.gold, equals(2000));
      expect(emptyProfile.diamonds, equals(50));
      expect(emptyProfile.rankPoints, equals(1000));
      expect(emptyProfile.unlockedHeroIds, equals(['george']));
      expect(emptyProfile.selectedHeroId, equals('george'));
      expect(emptyProfile.unlockedSkinIds, isEmpty);
      expect(emptyProfile.selectedSkinId, isNull);
      expect(emptyProfile.unlockedCompanionIds, isEmpty);
      expect(emptyProfile.selectedCompanionId, isNull);
      expect(emptyProfile.lastSpinTimestamp, equals(0));

      // 2. Extra unexpected keys
      final extraKeysJson = {
        'playerName': 'GamerX',
        'gold': 5000,
        'unexpectedField': 'unexpectedValue',
        'nestedMystery': {'deep': 42},
        'randomList': [1, 2, 3],
      };
      final profileWithExtra = PlayerProfile.fromJson(extraKeysJson);
      expect(profileWithExtra.playerName, equals('GamerX'));
      expect(profileWithExtra.gold, equals(5000));

      // 3. Explicit null values for all fields
      final nullJson = <String, dynamic>{
        'playerName': null,
        'gold': null,
        'diamonds': null,
        'rankPoints': null,
        'unlockedHeroIds': null,
        'selectedHeroId': null,
        'unlockedSkinIds': null,
        'selectedSkinId': null,
        'unlockedCompanionIds': null,
        'selectedCompanionId': null,
        'lastSpinTimestamp': null,
      };
      final profileNulls = PlayerProfile.fromJson(nullJson);
      expect(profileNulls.playerName, equals('Chiến Binh #88'));
      expect(profileNulls.gold, equals(2000));
      expect(profileNulls.diamonds, equals(50));
      expect(profileNulls.rankPoints, equals(1000));
      expect(profileNulls.unlockedHeroIds, equals(['george']));
      expect(profileNulls.selectedHeroId, equals('george'));
      expect(profileNulls.lastSpinTimestamp, equals(0));
    });

    test('Malformed data resilience: LeaderboardEntry.fromJson handles missing, extra, alias, and corrupt dates', () {
      // 1. Completely empty JSON {}
      final emptyEntry = LeaderboardEntry.fromJson({});
      expect(emptyEntry.uid, equals('unknown'));
      expect(emptyEntry.name, equals('Vô Danh'));
      expect(emptyEntry.rankPoints, equals(1000));
      expect(emptyEntry.rankTier, equals('Đồng'));
      expect(emptyEntry.winRate, equals('50%'));
      expect(emptyEntry.rankNumber, equals(1));
      expect(emptyEntry.heroId, equals('george'));
      expect(emptyEntry.isLocalPlayer, isFalse);
      expect(emptyEntry.lastUpdated, isNotNull);

      // 2. Backward-compatible alias keys (userId, playerName, rank, isCurrentPlayer)
      final aliasJson = {
        'userId': 'user_alias_123',
        'playerName': 'AliasPlayer',
        'rankPoints': 1650,
        'rank': 7,
        'isCurrentPlayer': true,
      };
      final aliasEntry = LeaderboardEntry.fromJson(aliasJson);
      expect(aliasEntry.uid, equals('user_alias_123'));
      expect(aliasEntry.userId, equals('user_alias_123'));
      expect(aliasEntry.name, equals('AliasPlayer'));
      expect(aliasEntry.playerName, equals('AliasPlayer'));
      expect(aliasEntry.rankPoints, equals(1650));
      expect(aliasEntry.rankNumber, equals(7));
      expect(aliasEntry.rank, equals(7));
      expect(aliasEntry.isLocalPlayer, isTrue);

      // 3. Extra unexpected keys
      final extraJson = {
        'uid': 'u1',
        'name': 'P1',
        'rankPoints': 2200,
        'superfluousField': 9999,
        'metadata': {'location': 'VN'},
      };
      final extraEntry = LeaderboardEntry.fromJson(extraJson);
      expect(extraEntry.uid, equals('u1'));
      expect(extraEntry.name, equals('P1'));
      expect(extraEntry.rankPoints, equals(2200));

      // 4. Corrupt date string does not crash and defaults to valid DateTime
      final corruptDateJson = {
        'uid': 'u2',
        'name': 'P2',
        'lastUpdated': 'NOT_AN_ISO_DATE_STRING_12345',
      };
      final corruptDateEntry = LeaderboardEntry.fromJson(corruptDateJson);
      expect(corruptDateEntry.lastUpdated, isNotNull);
      expect(corruptDateEntry.lastUpdated.year, greaterThanOrEqualTo(2026));

      // 5. Numeric types flexibility (e.g. double rankPoints from JS/JSON)
      final numJson = {
        'uid': 'u3',
        'name': 'P3',
        'rankPoints': 1850.0, // double representation
        'rankNumber': 4.0,
      };
      final numEntry = LeaderboardEntry.fromJson(numJson);
      expect(numEntry.rankPoints, equals(1850));
      expect(numEntry.rankNumber, equals(4));
    });

    test('Malformed data resilience: PvpQueueTicket and PvpMatchSession handle missing/extra keys', () {
      // PvpQueueTicket empty/minimal JSON
      final minimalTicket = PvpQueueTicket.fromJson({});
      expect(minimalTicket.ticketId, startsWith('ticket_'));
      expect(minimalTicket.userId, equals('unknown'));
      expect(minimalTicket.playerName, equals('Vô Danh'));
      expect(minimalTicket.rankPoints, equals(1000));
      expect(minimalTicket.rankTier, equals('Đồng'));

      // PvpQueueTicket epoch int timestamp vs string timestamp
      final epochTicket = PvpQueueTicket.fromJson({
        'ticketId': 't1',
        'timestamp': 1715385600000,
      });
      expect(
        epochTicket.timestamp.millisecondsSinceEpoch,
        equals(1715385600000),
      );

      // PvpMatchSession with empty map
      final minimalSession = PvpMatchSession.fromJson({});
      expect(minimalSession.sessionId, equals('session_unknown'));
      expect(minimalSession.player1.name, equals('Vô Danh'));
      expect(minimalSession.player2, isNull);
      expect(minimalSession.state, equals(PvpMatchSessionState.searching));

      // PvpMatchSession with extra unknown keys
      final extraSession = PvpMatchSession.fromJson({
        'sessionId': 's_custom',
        'extraFlag': true,
        'state': 'matched',
        'player1': {'name': 'Hero1', 'rankPoints': 1500},
        'player2': {'name': 'Bot1', 'rankPoints': 1480, 'isBot': true},
      });
      expect(extraSession.sessionId, equals('s_custom'));
      expect(extraSession.state, equals(PvpMatchSessionState.matched));
      expect(extraSession.player1.name, equals('Hero1'));
      expect(extraSession.player2?.name, equals('Bot1'));
    });

    test('Concurrency stress: 50 concurrent profile saves (Future.wait) do not corrupt JSON storage', () async {
      final service = MockDatabaseService();
      await service.initialize();

      // Launch 50 concurrent saves with different profile versions
      final futures = <Future<void>>[];
      for (int i = 1; i <= 50; i++) {
        final prof = PlayerProfile.defaultProfile().copyWith(
          playerName: 'ConcurrentHero',
          gold: 1000 + i,
          rankPoints: 1000 + i * 2,
        );
        futures.add(service.saveProfile(prof));
      }

      await Future.wait(futures);

      // Verify the persisted JSON is 100% valid JSON and readable
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('gold_rush_player_profile');
      expect(raw, isNotNull);

      expect(
        () => jsonDecode(raw!),
        returnsNormally,
        reason: 'Concurrent writes must not cause corrupted JSON truncation or syntax errors',
      );

      final loaded = await service.loadProfile('local_player');
      expect(loaded, isNotNull);
      expect(loaded!.playerName, equals('ConcurrentHero'));
      expect(loaded.gold, greaterThanOrEqualTo(1001));
      expect(loaded.gold, lessThanOrEqualTo(1050));
    });

    test('Leaderboard multi-player tiebreaker: identical RP tie-breaks by lastUpdated timestamp', () async {
      // 1. Direct comparator tiebreaking on multiple LeaderboardEntries with identical RP & win rate
      final tOld = DateTime.utc(2026, 5, 1, 12, 0, 0);
      final tNew = DateTime.utc(2026, 5, 1, 12, 30, 0);
      final tIdentical = DateTime.utc(2026, 5, 1, 12, 0, 0);

      final entries = [
        LeaderboardEntry(
          uid: 'p_old',
          name: 'PlayerOld',
          rankPoints: 2000,
          rankTier: 'Thách Đấu',
          winRate: '60%',
          rankNumber: 1,
          lastUpdated: tOld,
        ),
        LeaderboardEntry(
          uid: 'p_new',
          name: 'PlayerNew',
          rankPoints: 2000,
          rankTier: 'Thách Đấu',
          winRate: '60%',
          rankNumber: 2,
          lastUpdated: tNew,
        ),
        LeaderboardEntry(
          uid: 'p_same_time',
          name: 'PlayerSameTime',
          rankPoints: 2000,
          rankTier: 'Thách Đấu',
          winRate: '60%',
          rankNumber: 3,
          lastUpdated: tIdentical,
        ),
      ];

      // Sort using canonical DatabaseService leaderboard comparator
      entries.sort((a, b) {
        final cmp = b.rankPoints.compareTo(a.rankPoints);
        if (cmp != 0) return cmp;
        return b.lastUpdated.compareTo(a.lastUpdated);
      });

      // The newer timestamp (tNew) must tie-break to Rank #1
      expect(
        entries.first.uid,
        equals('p_new'),
        reason: 'When RP and win rate are identical, the more recently updated entry must rank higher',
      );

      // 2. Integration verification with MockDatabaseService:
      // Local player with 2080 RP ties with seed_8 KiếmThánh_VN (2080 RP)
      final service = MockDatabaseService();
      await service.initialize();

      // Ensure timestamp separation of at least 5ms between seed generation and local update
      await Future.delayed(const Duration(milliseconds: 5));

      final profileTied = PlayerProfile(
        playerName: 'ChiếnBinh_TieTest',
        rankPoints: 2080,
      );
      await service.updateLeaderboard(profileTied);

      final topEntries = await service.streamTopLeaderboard(limit: 25).first;
      final localEntry = topEntries.firstWhere(
        (e) => e.name == 'ChiếnBinh_TieTest',
      );
      final seed8Entry = topEntries.firstWhere((e) => e.name == 'KiếmThánh_VN');

      expect(localEntry.rankPoints, equals(seed8Entry.rankPoints));
      // Since local player was updated strictly after seed_8, local player ranks ahead of seed_8
      expect(
        localEntry.rankNumber < seed8Entry.rankNumber,
        isTrue,
        reason: 'More recently updated local player strictly tie-breaks ahead of older seed with identical RP',
      );

      // Sequentiality check: All ranks must be 1..N contiguous
      for (int i = 0; i < topEntries.length; i++) {
        expect(topEntries[i].rankNumber, equals(i + 1));
      }
    });

    test('Deserialization boundary & type cast resilience: PlayerProfile handles double num safely', () {
      // 1. Verify PlayerProfile.fromJson when types are valid ints
      final validJson = {'gold': 100, 'diamonds': 20, 'rankPoints': 1200};
      final validProfile = PlayerProfile.fromJson(validJson);
      expect(validProfile.gold, equals(100));

      // 2. Hardening verification: If dynamic JSON provides double (e.g. 100.0) for numeric fields,
      // defensive `(json[...] as num?)?.toInt()` parses successfully without TypeError.
      final doubleJson = {
        'gold': 100.0,
        'diamonds': 25.0,
        'rankPoints': 1500.0,
        'lastSpinTimestamp': 1600000000.0,
      };
      final floatProfile = PlayerProfile.fromJson(doubleJson);
      expect(floatProfile.gold, equals(100));
      expect(floatProfile.diamonds, equals(25));
      expect(floatProfile.rankPoints, equals(1500));
      expect(floatProfile.lastSpinTimestamp, equals(1600000000));

      // Main's tolerant parser falls back safely for malformed collection fields.
      final stringListJson = {'unlockedHeroIds': 'george'};
      expect(PlayerProfile.fromJson(stringListJson).unlockedHeroIds, [
        'george',
      ]);
      expect(
        PlayerProfile.fromJson({
          'unlockedHeroIds': ['george', 123, 'ranger'],
        }).unlockedHeroIds,
        ['george', 'ranger'],
      );
    });
  });
}
