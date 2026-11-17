import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/game/combat/hero_combat.dart';
import 'package:my_game/game/combat/combat_status.dart';
import 'package:my_game/game/components/player.dart';
import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:my_game/game/gold_rush_game.dart';
import 'package:my_game/models/player_profile.dart';
import 'package:my_game/game/components/pvp_bot_player.dart';
import 'package:my_game/models/pvp_match.dart';
import 'package:my_game/game/pvp_arena_game.dart';

class Dummy extends PositionComponent with CombatStatus {
  double hp = 1000;
  Dummy(double x, double y)
    : super(position: Vector2(x, y), size: Vector2.all(32));
  CombatTarget get target => CombatTarget(
    this,
    () => hp,
    1000,
    (damage) => hp -= absorbCombatDamage(damage),
  );
}

void main() {
  testWidgets(
    'Mounted PvP bot waits for fight and shoots through the shared kit',
    (tester) async {
      final game = PvpArenaGame(
        playerCurrentRp: 1000,
        opponentInfo: const PvpOpponentInfo(
          name: 'Ranger',
          rankPoints: 1000,
          rankTier: 'Đồng',
          heroId: 'ranger',
        ),
      );
      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump();
      expect(game.bot.heroCombat.parent, game.world);
      final ki = game.bot.currentKi;
      game.bot.executeSkill1();
      expect(
        game.bot.currentKi,
        ki,
        reason: 'No skill casting during round introduction',
      );
      game.matchState = PvpMatchState.fighting;
      game.player.position = Vector2(200, 320);
      game.bot.position = Vector2(400, 320);
      final hp = game.player.currentHp;
      game.bot.performBasicAttack();
      expect(game.player.currentHp, hp);
      game.bot.heroCombat.update(.5);
      expect(game.player.currentHp, hp - game.bot.damage);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Mounted PvE Ranger fires a visible projectile and retry clears combat',
    (tester) async {
      final game = GoldRushGame(
        playerProfile: const PlayerProfile(selectedHeroId: 'ranger'),
      );
      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump();
      final victim = game.enemies.first;
      for (final enemy in [...game.enemies, ...game.skeletons]) {
        enemy.position = Vector2(1000, 600);
      }
      game.boss?.position = Vector2(1050, 600);
      game.player.position = Vector2(400, 300);
      victim.position = Vector2(500, 300);
      final hp = victim.currentHp;
      game.onBasicAttack();
      expect(victim.currentHp, hp);
      expect(game.heroCombat.projectiles, hasLength(1));
      game.heroCombat.update(.3);
      expect(victim.currentHp, hp - game.player.attackDamage);
      game.onSkill3();
      expect(game.heroCombat.zones, isNotEmpty);
      game.retryFloor();
      expect(game.heroCombat.zones, isEmpty);
      expect(game.player.skill3VisualCd, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'Ranger bot also shoots projectiles instead of instant melee damage',
    () {
      final target = PlayerComponent(position: Vector2(200, 0));
      final bot = PvpBotPlayerComponent(
        position: Vector2.zero(),
        targetPlayer: target,
        opponentInfo: const PvpOpponentInfo(
          name: 'Ranger',
          heroId: 'ranger',
          rankPoints: 1000,
          rankTier: 'Đồng',
          difficulty: BotDifficulty.bronzeSilver,
        ),
        enableAi: false,
      );
      bot.performBasicAttack();
      expect(target.currentHp, target.maxHp);
      bot.heroCombat.update(.5);
      expect(target.currentHp, target.maxHp - bot.damage);
      bot.resetRound(Vector2.zero());
      expect(bot.heroCombat.projectiles, isEmpty);
    },
  );
  late PlayerComponent player;
  late List<Dummy> enemies;
  late HeroCombat combat;
  bool Function(Vector2) walkable = (_) => true;
  void setup(String hero) {
    player = PlayerComponent(position: Vector2.zero(), heroId: hero);
    player.damage = 25;
    enemies = [Dummy(150, 0)];
    walkable = (_) => true;
    combat = HeroCombat(
      owner: player,
      heroId: hero,
      damage: () => player.attackDamage,
      facing: () => Vector2(1, 0),
      targets: () => enemies.map((e) => e.target).toList(),
      canWalk: (point) => walkable(point),
      enabled: () => player.currentHp > 0,
      rage: (duration) {
        player.isBerserk = true;
        player.berserkTimer = duration;
      },
      maxHp: player.maxHp,
    );
  }

  test('Ranger shoots: no instant damage, flight then one collision hit', () {
    setup('ranger');
    combat.basic(1);
    expect(enemies.single.hp, 1000);
    expect(combat.projectiles, hasLength(1));
    combat.update(.1);
    expect(enemies.single.hp, 1000);
    combat.update(.3);
    expect(enemies.single.hp, 1000 - player.damage);
    combat.update(1);
    expect(enemies.single.hp, 1000 - player.damage);
  });
  test('Arrow is blocked by walls even on a long frame', () {
    setup('ranger');
    walkable = (point) => point.x < 80;
    combat.basic(1);
    combat.update(1);
    expect(enemies.single.hp, 1000);
    expect(combat.projectiles, isEmpty);
  });
  test('Arrow cannot hit beyond maximum range', () {
    setup('ranger');
    enemies.single.position.x = 400;
    combat.basic(1);
    combat.update(2);
    expect(enemies.single.hp, 1000);
    expect(combat.projectiles, isEmpty);
  });
  test('Ranger spread launches three differently directed arrows', () {
    setup('ranger');
    combat.skill(1);
    expect(combat.projectiles, hasLength(3));
    expect(combat.projectiles.first.direction.y, lessThan(0));
    expect(combat.projectiles.last.direction.y, greaterThan(0));
  });
  test('Retreat moves away and trap triggers once with crowd control', () {
    setup('ranger');
    combat.skill(2);
    expect(player.position.x, lessThan(-90));
    enemies.single.position = Vector2.zero();
    combat.update(.2);
    expect(enemies.single.hp, 970);
    expect(enemies.single.isStunned, isTrue);
    combat.update(2);
    expect(enemies.single.hp, 970);
  });
  test('Rain telegraphs then damages a fixed location in four pulses', () {
    setup('ranger');
    combat.skill(3);
    combat.update(.4);
    expect(enemies.single.hp, 1000);
    combat.update(.2);
    expect(enemies.single.hp, 986.25);
    combat.update(2.3);
    expect(enemies.single.hp, closeTo(945, .001));
    expect(combat.zones, isEmpty);
  });
  test('Tanker shield absorbs damage and expires', () {
    setup('tanker');
    combat.skill(2);
    expect(player.barrierHp, 35);
    player.takeDamage(20);
    expect(player.currentHp, 100);
    player.takeDamage(30);
    expect(player.currentHp, 85);
    player.tickCombatStatus(5);
    expect(player.barrierHp, 0);
  });
  test('Tanker shield bash stuns and pushes only enemies ahead', () {
    setup('tanker');
    enemies = [Dummy(40, 0), Dummy(-40, 0)];
    combat.skill(1);
    expect(enemies.first.hp, 965);
    expect(enemies.first.position.x, greaterThan(40));
    expect(enemies.first.isStunned, isTrue);
    expect(enemies.last.hp, 1000);
    enemies.first.tickCombatStatus(1.1);
    expect(enemies.first.isStunned, isFalse);
  });
  test('Earthquake has a delay then stun and slow', () {
    setup('tanker');
    enemies.single.position.x = 80;
    combat.skill(3);
    combat.update(.5);
    expect(enemies.single.hp, 1000);
    combat.update(.15);
    expect(enemies.single.hp, 942.5);
    expect(enemies.single.isStunned, isTrue);
    expect(enemies.single.combatMoveFactor, .55);
  });
  test('Ninja projectile pierces two targets and never hits one twice', () {
    setup('ninja');
    enemies = [Dummy(100, 0), Dummy(170, 0)];
    combat.skill(1);
    combat.update(.5);
    combat.update(.1);
    expect(enemies.map((e) => e.hp), everyElement(967.5));
  });
  test('Ninja dash stops before a wall and smoke reduces incoming damage', () {
    setup('ninja');
    walkable = (point) => point.x < 60;
    combat.skill(2);
    expect(player.position.x, lessThan(48));
    player.takeDamage(50);
    expect(player.currentHp, closeTo(80, .001));
    player.tickCombatStatus(2.1);
    player.takeDamage(50);
    expect(player.currentHp, closeTo(30, .001));
  });
  test(
    'Execution closes distance and deals extra damage to low health target',
    () {
      setup('ninja');
      enemies.single.hp = 250;
      combat.skill(3);
      expect(player.position.x, greaterThan(100));
      expect(enemies.single.hp, 140);
    },
  );
  test('George spin is circular but slam is directional; rage boosts damage temporarily', () {
    setup('george');
    enemies = [Dummy(40, 0), Dummy(-40, 0)];
    combat.skill(1);
    expect(enemies.map((e) => e.hp), everyElement(955));
    combat.skill(2);
    expect(enemies.first.hp, 900);
    expect(enemies.last.hp, 955);
    combat.skill(3);
    expect(player.attackDamage, 40);
    player.damage = 35;
    player.update(8.1);
    expect(player.damage, 35);
    expect(player.attackDamage, 35);
  });
  test(
    'Resource checks enforce real cooldowns, stun and basic attack cadence',
    () {
      setup('ranger');
      expect(player.performBasicAttack(), isTrue);
      player.isAttacking = false;
      expect(player.performBasicAttack(), isFalse);
      expect(player.useSkill1(), isTrue);
      final ki = player.currentKi;
      expect(player.useSkill1(), isFalse);
      expect(player.currentKi, ki);
      player.stunRemaining = 1;
      expect(player.useSkill2(), isFalse);
      player.update(5.1);
      expect(player.useSkill1(), isTrue);
      player.resetCombat();
      expect(player.skill1VisualCd, 0);
      expect(player.isStunned, isFalse);
    },
  );
  test(
    'Reset or dead caster removes old projectiles and delayed damage zones',
    () {
      setup('ranger');
      combat.basic(1);
      combat.skill(3);
      combat.reset();
      combat.update(3);
      expect(enemies.single.hp, 1000);
      combat.skill(3);
      player.currentHp = 0;
      combat.update(3);
      expect(enemies.single.hp, 1000);
    },
  );
}
