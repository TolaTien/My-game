import 'package:flame/components.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/core/constants.dart';
import 'package:my_game/core/pve_balance.dart';
import 'package:my_game/core/stat_growth_formula.dart';
import 'package:my_game/game/components/arrow_projectile.dart';
import 'package:my_game/game/components/boss_enemy.dart';
import 'package:my_game/game/components/player.dart';
import 'package:my_game/registry/asset_registry.dart';

String _number(num value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

/// Reads production actors and shared formulas. No combat balance constants are
/// maintained here; the output assumes neutral, unbuffed, in-run level one.
String buildGameplayBalanceReport() {
  final registry = GameAssetRegistry.instance;
  if (!registry.isInitialized) {
    throw StateError('Initialize the production asset registry first.');
  }
  final heroes = registry.heroes.toList()..sort((a, b) => a.id.compareTo(b.id));
  final out = StringBuffer();
  void line([String text = '']) => out.writeln(text);
  PlayerComponent player(String id, int level) => PlayerComponent(
    position: Vector2.zero(),
    heroId: id,
    userHeroLevel: level,
  );

  line('# Gameplay Balance Measurement');
  line();
  line('Reproduce from the project root:');
  line();
  line('```powershell');
  line('flutter test tool/gameplay_balance.dart --no-pub --reporter expanded');
  line('flutter test test/gameplay_balance_test.dart --no-pub');
  line('```');
  line();
  line(
    'The first command prints this Markdown between BEGIN/END markers. '
    'Flutter is required because the production registry, player and '
    'StatGrowthFormula depend on Flutter. Plain `dart run` is not supported. '
    'The generator does not write files.',
  );
  line();
  line(
    'This is a reproducible numerical measurement, not a pacing target or '
    'autoplay result. No balance values were changed and no user pacing '
    'approval is assumed. Hero level means permanent mastery; in-run level '
    'remains one. There are no active skills, shields, companions, items, '
    'misses or regeneration in the neutral hit tables.',
  );
  line();
  line('## Spawn And Reward Values');
  line();
  line(
    '| Floor | Enemy scale | Zombie HP | Zombie damage | Skeleton HP | '
    'Boss HP | Completion gold entering this floor |',
  );
  line('| --- | --- | --- | --- | --- | --- | --- |');
  for (final floor in [1, 2, 5, 10]) {
    line(
      '| $floor | ${_number(PveBalance.enemyScale(floor))} | '
      '${_number(PveBalance.zombieMaxHp(floor))} | '
      '${_number(PveBalance.zombieDamage(floor))} | '
      '${_number(PveBalance.skeletonMaxHp(floor))} | '
      '${_number(PveBalance.bossMaxHp(floor))} | '
      '${PveBalance.floorCompletionGold(floor)} |',
    );
  }
  line();
  line(
    'The reward helper accepts the destination floor: clearing floor one '
    'and advancing to floor two pays '
    '${PveBalance.floorCompletionGold(2)} gold. Its floor-one result is a '
    'formula boundary, not a reward paid when a new game starts.',
  );
  line();
  line('## Registry Versus Actual Initial Player');
  line();
  line(
    'Each tuple is HP / Ki / attack / speed. Registry columns come from '
    'StatGrowthFormula; runtime columns come from PlayerComponent.',
  );
  line();
  line('| Hero | Registry at level 1 | Actual at level 1 |');
  line('| --- | --- | --- |');
  for (final hero in heroes) {
    final scaled = StatGrowthFormula.computeStatsForLevel(
      heroId: hero.id,
      level: 1,
    );
    final actual = player(hero.id, 1);
    line(
      '| ${hero.id} | ${_number(scaled.maxHp)} / '
      '${_number(scaled.maxKi)} / ${_number(scaled.attackDamage)} / '
      '${_number(scaled.moveSpeed)} | ${_number(actual.maxHp)} / '
      '${_number(actual.maxKi)} / ${_number(actual.effectiveDamage)} / '
      '${_number(actual.effectiveSpeed)} |',
    );
  }
  line();
  line(
    'PlayerComponent starts every hero from GameConstants: '
    '${_number(GameConstants.playerMaxHp)} HP, '
    '${_number(GameConstants.playerMaxKi)} Ki, '
    '${_number(GameConstants.playerBaseDamage)} attack and '
    '${_number(GameConstants.playerBaseSpeed)} speed. At mastery levels '
    'above one it adds StatGrowthFormula bonuses to those constants, '
    'rather than adopting the registry base stats. Speed remains the '
    'player constant. The report preserves this existing mismatch.',
  );
  line();

  void hitHeader() {
    line(
      '| Hero | Hero level | Floor | Actual HP | Ki | Neutral attack | '
      'Hits to kill Z / S / B | HP / Z damage, floored | Hits to KO |',
    );
    line('| --- | --- | --- | --- | --- | --- | --- | --- | --- |');
  }

  void hitRow(HeroAssetConfig hero, int level, int floor) {
    final actual = player(hero.id, level);
    final attack = actual.effectiveDamage;
    final z = (PveBalance.zombieMaxHp(floor) / attack).ceil();
    final s = (PveBalance.skeletonMaxHp(floor) / attack).ceil();
    final b = (PveBalance.bossMaxHp(floor) / attack).ceil();
    final damage = PveBalance.zombieDamage(floor);
    line(
      '| ${hero.id} | $level | $floor | ${_number(actual.maxHp)} | '
      '${_number(actual.maxKi)} | ${_number(attack)} | $z / $s / $b | '
      '${(actual.maxHp / damage).floor()} | '
      '${(actual.maxHp / damage).ceil()} |',
    );
  }

  line('## All Heroes At Mastery Level One');
  line();
  line(
    'Z / S / B means zombie / skeleton / boss. Hit counts are '
    '`ceil(target HP / actual neutral attack)`, not elapsed TTK. The '
    'floored survival column is whole damage budgets; an exact division '
    'includes the lethal hit. Hits to KO uses ceil; strictly nonlethal '
    'hits are Hits to KO minus one.',
  );
  line();
  hitHeader();
  for (final hero in heroes) {
    for (final floor in [1, 5, 10]) {
      hitRow(hero, 1, floor);
    }
  }
  line();
  line('## Mastery Levels 10, 50 And 100 At Floor 10');
  line();
  hitHeader();
  for (final hero in heroes) {
    for (final level in [10, 50, 100]) {
      hitRow(hero, level, 10);
    }
  }
  line();
  line('## Initial Skill Budget');
  line();
  line(
    'Each cost / cooldown entry comes from the same slot configuration '
    'captured by the initial player. Neutral skill damage is the nominal '
    'total against one target if every hit lands; periodic damage uses '
    'the configured total multiplier, not that multiplier per tick. '
    'Self delivery deals zero direct damage. Buffs, misses, travel, '
    'other targets and active-cast overlap are excluded.',
  );
  line();
  line(
    '| Hero | S1 Ki / CD | S2 Ki / CD | S3 Ki / CD | '
    'Neutral damage S1 / S2 / S3 | Full Ki | All three Ki | '
    'All three affordable initially |',
  );
  line('| --- | --- | --- | --- | --- | --- | --- | --- |');
  for (final hero in heroes) {
    final actual = player(hero.id, 1);
    final configs = [
      for (var slot = 1; slot <= 3; slot++) actual.skillConfig(slot),
    ];
    final budget = configs.fold<double>(0, (sum, skill) => sum + skill.kiCost);
    final costs = configs
        .map((skill) => '${_number(skill.kiCost)} / ${_number(skill.cooldown)}')
        .join(' | ');
    final damage = configs
        .map(
          (skill) => _number(
            skill.effects.delivery == SkillDelivery.self
                ? 0
                : actual.effectiveDamage * skill.damageMultiplier,
          ),
        )
        .join(' / ');
    line(
      '| ${hero.id} | $costs | $damage | ${_number(actual.maxKi)} | '
      '${_number(budget)} | ${budget <= actual.maxKi ? 'yes' : 'no'} |',
    );
  }
  line();
  final kaelen = player('kaelen', 1);
  final ultimate = kaelen.skillConfig(3);
  line(
    'Kaelen illustrates the distinction: ultimate cost '
    '${_number(ultimate.kiCost)} Ki fits the actual initial '
    '${_number(kaelen.maxKi)} Ki; its registry base Ki is '
    '${_number(registry.getHero('kaelen').baseStats.ki)}. Affordability '
    'of one skill does not imply the three-skill sequence is affordable '
    'without regeneration. Costs and cooldowns are now configuration '
    'values, not the historical universal 25 / 35 / 40 Ki and visual '
    '5 / 8 / 12 seconds. Those historical values are audit context only.',
  );
  line();
  line('## Preserved Quirks And Limits');
  line();
  final arrow = ArrowProjectile(
    position: Vector2.zero(),
    direction: Vector2(1, 0),
  );
  line(
    '- Floor one boss HP is ${_number(PveBalance.bossMaxHp(1))}; higher '
    'floors scale from a different base. Floor two is '
    '${_number(PveBalance.bossMaxHp(2))}, not a scaled floor-one baseline.',
  );
  line(
    '- Skeleton HP scales but its arrow damage remains '
    '${_number(arrow.damage)} at every floor. The shared spawn helper '
    'deliberately has no skeleton-damage formula.',
  );
  line(
    '- Boss HP scales; its attack constants remain '
    '${_number(BossEnemy.meleeDamage)} melee / '
    '${_number(BossEnemy.groundSlamDamage)} slam / '
    '${_number(BossEnemy.flameBurstDamage)} per radial projectile. '
    'Boss-summoned minions still use component defaults instead of '
    'the ordinary floor spawn scaling.',
  );
  line(
    '- Registry enemy definitions are not used by the current ordinary '
    'spawn formulas. Reward measurement covers the existing floor '
    'completion grant only, not loot, coin conversion, mastery EXP or '
    'total run income.',
  );
  line(
    '- A target can die sooner or later in play due to positioning, '
    'control, buff timing, missed projectiles, multiple attackers and '
    'level-ups. Attack intervals, encounter duration, mobile readability '
    'and player pacing are not verified by these arithmetic tables.',
  );
  line();
  line('## Verification');
  line();
  line(
    'The companion test file checks formula boundaries, rejects floors '
    'below one, mounts the real production GoldRushGame at floors '
    '1 / 5 / 10, and compares ordinary spawn values with PveBalance. '
    'Its report test checks actual player values against the generator. '
    'Test pass/fail must be read from the command output; this generated '
    'document does not assert that those tests have passed.',
  );
  return out.toString();
}

/// Run with Flutter's test runner so production Flutter imports and rootBundle
/// use the same initialization as the application and existing registry tests.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('print production gameplay balance report', () async {
    await GameAssetRegistry.instance.initialize(bundle: rootBundle);
    expect(GameAssetRegistry.instance.isInitialized, isTrue);
    expect(GameAssetRegistry.instance.heroes, hasLength(10));
    expect(GameAssetRegistry.instance.skills, hasLength(30));
    // ignore: avoid_print
    print(
      'BEGIN GAMEPLAY BALANCE REPORT\n'
      '${buildGameplayBalanceReport()}END GAMEPLAY BALANCE REPORT',
    );
  });
}
