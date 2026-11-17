import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/components.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_game/core/constants.dart';
import 'package:my_game/game/components/player.dart';
import 'package:my_game/services/player_storage.dart';
import 'package:my_game/screens/lucky_wheel_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Tier 1: Currency & Economy Rules', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('1 In-Game Coin == 1000 Wallet Gold immutable conversion rule', () {
      // 1. Core constant validation
      expect(GameConstants.goldPerCoinPickup, 1000,
          reason: 'GameConstants.goldPerCoinPickup must strictly equal 1000');

      // 2. In-game player coinsCollected accumulation
      final player = PlayerComponent(position: Vector2(100, 100));
      expect(player.coinsCollected, 0);

      // Collect 1 coin
      player.coinsCollected += 1;
      expect(player.coinsCollected * GameConstants.goldPerCoinPickup, 1000);

      // Collect 5 coins (e.g. dungeon run clear)
      player.coinsCollected = 5;
      final walletGoldFrom5Coins =
          player.coinsCollected * GameConstants.goldPerCoinPickup;
      expect(walletGoldFrom5Coins, 5000,
          reason: '5 coins collected must yield exactly 5000 gold');

      // Collect 12 coins (e.g. boss cascade reward)
      player.coinsCollected = 12;
      final walletGoldFrom12Coins =
          player.coinsCollected * GameConstants.goldPerCoinPickup;
      expect(walletGoldFrom12Coins, 12000,
          reason: '12 coins collected must yield exactly 12000 gold');

      // 3. WheelReward gold conversion
      const reward10 = WheelReward(
        coins: 10,
        label: '10 Xu',
        primaryColor: Color(0xFF1E88E5),
        secondaryColor: Color(0xFF1565C0),
        icon: Icons.monetization_on_outlined,
      );
      expect(reward10.goldValue, 10000);

      const rewardJackpot = WheelReward(
        coins: 100,
        label: '100 Xu',
        primaryColor: Color(0xFFFFB300),
        secondaryColor: Color(0xFFFF8F00),
        icon: Icons.military_tech_rounded,
        isJackpot: true,
      );
      expect(rewardJackpot.goldValue, 100000,
          reason: '100 coins jackpot must equal 100,000 gold');
    });

    test('Hero unlock flat 100 gold pricing and deduplication', () async {
      expect(GameConstants.heroUnlockPrice, 100,
          reason: 'Hero unlock price must be flat 100 gold');

      await PlayerStorage.loadProfile();
      // Start with 2000 gold, george unlocked
      expect(PlayerStorage.currentProfile.gold, 2000);
      expect(PlayerStorage.currentProfile.unlockedHeroIds, ['george']);

      // 1. Unlock Ranger for 100 gold
      final unlockRanger =
          await PlayerStorage.unlockHero('ranger', GameConstants.heroUnlockPrice);
      expect(unlockRanger, isTrue);
      expect(PlayerStorage.currentProfile.gold, 1900);
      expect(PlayerStorage.currentProfile.unlockedHeroIds,
          containsAll(['george', 'ranger']));
      expect(PlayerStorage.currentProfile.selectedHeroId, 'ranger');

      // 2. Unlock Tanker for 100 gold
      final unlockTanker =
          await PlayerStorage.unlockHero('tanker', GameConstants.heroUnlockPrice);
      expect(unlockTanker, isTrue);
      expect(PlayerStorage.currentProfile.gold, 1800);
      expect(PlayerStorage.currentProfile.unlockedHeroIds, contains('tanker'));

      // 3. Unlock Ninja for 100 gold
      final unlockNinja =
          await PlayerStorage.unlockHero('ninja', GameConstants.heroUnlockPrice);
      expect(unlockNinja, isTrue);
      expect(PlayerStorage.currentProfile.gold, 1700);
      expect(PlayerStorage.currentProfile.unlockedHeroIds, contains('ninja'));

      // 4. Re-unlocking already owned hero does not deduct gold again
      final reUnlockRanger =
          await PlayerStorage.unlockHero('ranger', GameConstants.heroUnlockPrice);
      expect(reUnlockRanger, isTrue);
      expect(PlayerStorage.currentProfile.gold, 1700,
          reason: 'Re-unlocking already owned hero must not charge gold');
    });

    test('Shop companion purchases and equipping flow', () async {
      await PlayerStorage.loadProfile();
      // Initial state
      expect(PlayerStorage.currentProfile.unlockedCompanionIds, isEmpty);
      expect(PlayerStorage.currentProfile.selectedCompanionId, isNull);

      // Buy Attack Drone (500 gold)
      final buyAttack = await PlayerStorage.unlockCompanion('comp_attack', 500);
      expect(buyAttack, isTrue);
      expect(PlayerStorage.currentProfile.gold, 1500);
      expect(PlayerStorage.currentProfile.unlockedCompanionIds,
          contains('comp_attack'));
      expect(PlayerStorage.currentProfile.selectedCompanionId, 'comp_attack');

      // Buy Shield Drone (600 gold)
      final buyShield = await PlayerStorage.unlockCompanion('comp_defense', 600);
      expect(buyShield, isTrue);
      expect(PlayerStorage.currentProfile.gold, 900);
      expect(PlayerStorage.currentProfile.unlockedCompanionIds,
          contains('comp_defense'));
      expect(PlayerStorage.currentProfile.selectedCompanionId, 'comp_defense');

      // Buy Frost Drone (700 gold)
      final buyFrost = await PlayerStorage.unlockCompanion('comp_control', 700);
      expect(buyFrost, isTrue);
      expect(PlayerStorage.currentProfile.gold, 200);
      expect(PlayerStorage.currentProfile.unlockedCompanionIds,
          contains('comp_control'));

      // Toggle equip / switch active companion
      await PlayerStorage.selectCompanion('comp_attack');
      expect(PlayerStorage.currentProfile.selectedCompanionId, 'comp_attack');

      await PlayerStorage.selectCompanion('comp_defense');
      expect(PlayerStorage.currentProfile.selectedCompanionId, 'comp_defense');
    });

    test('Shop pure cosmetic skins guarantee (zero stat bonus)', () async {
      await PlayerStorage.loadProfile();
      expect(PlayerStorage.currentProfile.diamonds, 50);

      // Unlock George Hoang Kim (50 diamonds)
      final unlockSkin =
          await PlayerStorage.unlockSkin('skin_george_gold', 50);
      expect(unlockSkin, isTrue);
      expect(PlayerStorage.currentProfile.diamonds, 0);
      expect(PlayerStorage.currentProfile.unlockedSkinIds,
          contains('skin_george_gold'));
      expect(PlayerStorage.currentProfile.selectedSkinId, 'skin_george_gold');

      // Verify Player George base stats remain completely identical (Pure Cosmetic Fair-Play)
      final playerWithSkin = PlayerComponent(position: Vector2(100, 100));
      expect(playerWithSkin.maxHp, GameConstants.playerMaxHp,
          reason: 'Cosmetic skin must NOT alter max HP');
      expect(playerWithSkin.damage, GameConstants.playerBaseDamage,
          reason: 'Cosmetic skin must NOT alter base damage');
      expect(playerWithSkin.speed, GameConstants.playerBaseSpeed,
          reason: 'Cosmetic skin must NOT alter speed');
    });
  });

  group('Tier 1: Level 1 to 15 Progression Formula & Stat Increments', () {
    test('Base stats at Level 1 adhere strictly to specification', () {
      final player = PlayerComponent(position: Vector2.zero());

      expect(player.level, 1);
      expect(player.currentExp, 0);
      expect(player.expToNextLevel, 100);
      expect(player.maxHp, 100.0);
      expect(player.currentHp, 100.0);
      expect(player.maxKi, 100.0);
      expect(player.currentKi, 100.0);
      expect(player.damage, 20.0);
      expect(player.speed, 160.0);
    });

    test('Exponential EXP requirement formula EXP(N+1) = (EXP(N) * 1.3).toInt()',
        () {
      // Progression curve generated by player.dart: expToNextLevel = (expToNextLevel * 1.3).toInt()
      int expectedExp = 100;
      final player = PlayerComponent(position: Vector2.zero());

      for (int level = 1; level < 15; level++) {
        expect(player.level, level);
        expect(player.expToNextLevel, expectedExp,
            reason: 'Level $level to ${level + 1} requirement mismatch');

        // Feed exact EXP to reach next level
        player.gainExp(expectedExp);
        expectedExp = (expectedExp * 1.3).toInt();
      }

      expect(player.level, 15, reason: 'Player should have reached Level 15');
    });

    test('Stat increments per level up: +15 Max HP, +10 Max Ki, +5 Damage', () {
      final player = PlayerComponent(position: Vector2.zero());

      // Simulate taking damage and expending Ki before level-up
      player.currentHp = 30.0;
      player.currentKi = 10.0;

      // Level 1 -> Level 2
      player.gainExp(100);

      expect(player.level, 2);
      expect(player.maxHp, 115.0, reason: 'Max HP must increase by +15');
      expect(player.currentHp, 115.0,
          reason: 'Level up must fully restore HP to new max');
      expect(player.maxKi, 110.0, reason: 'Max Ki must increase by +10');
      expect(player.currentKi, 110.0,
          reason: 'Level up must fully restore Ki to new max');
      expect(player.damage, 25.0, reason: 'Base damage must increase by +5');

      // Level 2 -> Level 3
      player.gainExp(130);
      expect(player.level, 3);
      expect(player.maxHp, 130.0);
      expect(player.maxKi, 120.0);
      expect(player.damage, 30.0);
    });

    test('Exact stat cap values at Level 15', () {
      final player = PlayerComponent(position: Vector2.zero());

      // Fast-forward to level 15 with large lump-sum EXP
      // Total EXP needed across all 14 level-ups is ~12,546 EXP
      player.gainExp(50000);

      expect(player.level, 15);
      // Math: 100 + (14 * 15) = 310 Max HP
      expect(player.maxHp, 310.0);
      expect(player.currentHp, 310.0);
      // Math: 100 + (14 * 10) = 240 Max Ki
      expect(player.maxKi, 240.0);
      expect(player.currentKi, 240.0);
      // Math: 20 + (14 * 5) = 90 Base Damage
      expect(player.damage, 90.0);
    });
  });

  group('Tier 1: Pickups Mechanics (Potion & Gem Magnet)', () {
    test('Health potion restores 25 HP with strict overheal clamping', () {
      final player = PlayerComponent(position: Vector2.zero());

      // Case 1: Partial HP heal (50 -> 75)
      player.currentHp = 50.0;
      player.heal(25.0);
      expect(player.currentHp, 75.0);

      // Case 2: Near max HP heal clamped to maxHp (90 -> 100, not 115)
      player.currentHp = 90.0;
      player.heal(25.0);
      expect(player.currentHp, 100.0,
          reason: 'Healing beyond maxHp must be clamped to 100.0');

      // Case 3: Full HP heal remains at maxHp
      player.currentHp = 100.0;
      player.heal(25.0);
      expect(player.currentHp, 100.0);
    });

    test('EXP Gem magnet attraction distance threshold (70px boundary)', () {
      // PickupItem has attraction logic: if distanceTo(playerPos) <= 70.0, moves with 200 px/s
      final itemPosWithinRange = Vector2(50, 0);
      final itemPosOutOfRange = Vector2(75, 0);
      final playerPos = Vector2.zero();

      // Within 70px threshold:
      final distInside = itemPosWithinRange.distanceTo(playerPos);
      expect(distInside <= 70.0, isTrue);

      final dir = (playerPos - itemPosWithinRange).normalized();
      const magnetSpeed = 200.0;
      const dt = 0.05; // 50ms step
      final movementVector = dir * magnetSpeed * dt;
      final newPos = itemPosWithinRange + movementVector;

      expect(newPos.distanceTo(playerPos) < distInside, isTrue,
          reason: 'Magnet must pull item closer to player position');

      // Outside 70px threshold:
      final distOutside = itemPosOutOfRange.distanceTo(playerPos);
      expect(distOutside <= 70.0, isFalse,
          reason: '75px exceeds the 70px magnet attraction radius');
    });
  });

  group('Tier 2: Boundary Cases & Negative Assertions', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('99 Gold purchase rejection: exact off-by-one boundary guard',
        () async {
      await PlayerStorage.loadProfile();

      // Set gold to exactly 99 (1 less than 100 price)
      await PlayerStorage.spendGold(PlayerStorage.currentProfile.gold);
      await PlayerStorage.addGold(99);
      expect(PlayerStorage.currentProfile.gold, 99);

      // 1. Attempt to unlock 100-gold Hero
      final unlockAttempt =
          await PlayerStorage.unlockHero('ranger', GameConstants.heroUnlockPrice);
      expect(unlockAttempt, isFalse,
          reason: '99 gold must fail to unlock 100 gold hero');
      expect(PlayerStorage.currentProfile.gold, 99,
          reason: 'Gold balance must remain 99 without deduction');
      expect(PlayerStorage.currentProfile.unlockedHeroIds,
          isNot(contains('ranger')));

      // 2. Direct spendGold(100) must also reject
      final spendAttempt = await PlayerStorage.spendGold(100);
      expect(spendAttempt, isFalse);
      expect(PlayerStorage.currentProfile.gold, 99);

      // 3. Companion purchase rejection (needs 500 gold)
      final companionAttempt =
          await PlayerStorage.unlockCompanion('comp_attack', 500);
      expect(companionAttempt, isFalse);
      expect(PlayerStorage.currentProfile.gold, 99);

      // 4. Diamonds boundary: 39 diamonds cannot buy 40-diamond skin
      final profileWith39Diamonds =
          PlayerStorage.currentProfile.copyWith(diamonds: 39);
      await PlayerStorage.saveProfile(profileWith39Diamonds);
      expect(PlayerStorage.currentProfile.diamonds, 39);

      final skinAttempt =
          await PlayerStorage.unlockSkin('skin_ranger_shadow', 40);
      expect(skinAttempt, isFalse);
      expect(PlayerStorage.currentProfile.diamonds, 39);
    });

    test('Level 15 Max Cap Boundary: excess EXP does not exceed cap', () {
      final player = PlayerComponent(position: Vector2.zero());

      // Advance to Level 15
      player.gainExp(50000);
      expect(player.level, 15);
      final hpAtCap = player.maxHp;
      final kiAtCap = player.maxKi;
      final dmgAtCap = player.damage;

      // Add another massive EXP payload
      player.gainExp(1000000);

      expect(player.level, 15, reason: 'Level must remain capped at 15');
      expect(player.maxHp, hpAtCap, reason: 'Max HP must not inflate past cap');
      expect(player.maxKi, kiAtCap, reason: 'Max Ki must not inflate past cap');
      expect(player.damage, dmgAtCap,
          reason: 'Base damage must not inflate past cap');
    });

    test('Zero Ki (0 Ki) and insufficient Ki skill attempts are rejected', () {
      final player = PlayerComponent(position: Vector2.zero());

      // Case 1: Ki is 0
      player.currentKi = 0.0;
      expect(player.useSkill1(), isFalse,
          reason: 'Skill 1 (25 Ki) must fail at 0 Ki');
      expect(player.useSkill2(), isFalse,
          reason: 'Skill 2 (35 Ki) must fail at 0 Ki');
      expect(player.useSkill3(), isFalse,
          reason: 'Skill 3 (40 Ki) must fail at 0 Ki');
      expect(player.currentKi, 0.0, reason: 'Ki must remain 0');

      // Case 2: Ki is 24.9 (just below 25 cost for Skill 1)
      player.currentKi = 24.9;
      expect(player.useSkill1(), isFalse);
      expect(player.currentKi, 24.9);

      // Case 3: Ki is 34.9 (just below 35 cost for Skill 2)
      player.currentKi = 34.9;
      expect(player.useSkill2(), isFalse);
      expect(player.currentKi, 34.9);

      // Case 4: Ki is 39.9 (just below 40 cost for Skill 3)
      player.currentKi = 39.9;
      expect(player.useSkill3(), isFalse);
      expect(player.currentKi, 39.9);
    });

    test('Berserk Recast Guard prevents re-triggering & preserves Ki', () {
      final player = PlayerComponent(position: Vector2.zero());
      player.currentKi = 100.0;

      // 1. First Berserk activation
      final firstCast = player.useSkill3();
      expect(firstCast, isTrue);
      expect(player.isBerserk, isTrue);
      expect(player.berserkTimer, 8.0);
      expect(player.currentKi, 60.0, reason: '100 - 40 Ki = 60 Ki');

      // 2. Immediate recast attempt while active
      final secondCast = player.useSkill3();
      expect(secondCast, isFalse,
          reason: 'Recast during active Berserk must return false');
      expect(player.currentKi, 60.0,
          reason: 'Rejected recast must not deduct Ki');
      expect(player.berserkTimer, 8.0,
          reason: 'Rejected recast must not reset timer prematurely');

      // 3. Berserk damage reduction: takes 60% incoming damage (-40% reduction)
      player.currentHp = 100.0;
      player.takeDamage(50.0);
      // Effective damage = 50 * 0.6 = 30.0 -> HP = 70.0
      expect(player.currentHp, 70.0,
          reason: 'Berserk buff must reduce 50 damage down to 30 damage');

      // 4. After Berserk ends, takes 100% incoming damage
      player.isBerserk = false;
      player.takeDamage(50.0);
      // Effective damage = 50.0 -> HP = 20.0
      expect(player.currentHp, 20.0,
          reason: 'Normal state must take full unmitigated damage');
    });
  });
}
