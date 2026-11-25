import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/game/components/hero_projectile.dart';
import 'package:my_game/game/gold_rush_game.dart';
import 'package:my_game/models/player_profile.dart';
import 'package:my_game/registry/asset_registry.dart';
import 'package:my_game/services/audio_service.dart';

import 'support/legacy_pve_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AudioService previousAudio;
  late MockAudioService audio;

  setUpAll(() async {
    await GameAssetRegistry.instance.initialize();
  });

  setUp(() {
    previousAudio = AudioService.instance;
    audio = MockAudioService();
    AudioService.setInstance(audio);
  });

  tearDown(() => AudioService.setInstance(previousAudio));

  Future<GoldRushGame> loadGame(WidgetTester tester, String heroId) async {
    final game = GoldRushGame(
      selectedMapConfig: legacyTestMap,
      playerProfile: PlayerProfile.defaultProfile().copyWith(
        selectedHeroId: heroId,
      ),
    );
    await tester.pumpWidget(GameWidget(game: game));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return game;
  }

  void silenceUnrelatedTargets(GoldRushGame game) {
    for (var i = 0; i < game.enemies.length; i++) {
      game.enemies[i]
        ..position = Vector2(1000 + i * 48, 700)
        ..stunTimer = 1000;
    }
    for (var i = 0; i < game.skeletons.length; i++) {
      game.skeletons[i]
        ..position = Vector2(1000 + i * 48, 800)
        ..stunTimer = 1000;
    }
    game.boss!
      ..position = Vector2(1000, 900)
      ..stunTimer = 1000;
  }

  Future<List<HeroProjectile>> castAndGetProjectiles(
    WidgetTester tester,
    GoldRushGame game,
  ) async {
    game.onSkill1();
    await tester.pump();
    game.pauseEngine();
    return game.world.children.whereType<HeroProjectile>().toList();
  }

  testWidgets('Ranger Multishot creates a captured five-direction fan', (
    tester,
  ) async {
    final game = await loadGame(tester, 'ranger');
    silenceUnrelatedTargets(game);
    game.player.position = Vector2(400, 200);
    game.player.faceDirection(Vector2(1, 0));

    final config = game.player.skillConfig(1);
    final kiBefore = game.player.currentKi;
    final configuredSfxBefore = audio.callHistory
        .where(
          (event) =>
              event.method == 'playSfx' && event.target == SfxSound.attackArrow,
        )
        .length;
    final projectiles = await castAndGetProjectiles(tester, game);
    game.player.faceDirection(Vector2(0, -1));

    expect(config.id, 'ranger_multishot');
    expect(projectiles, hasLength(5));
    expect(game.player.currentKi, closeTo(kiBefore - config.kiCost, .00001));
    expect(game.player.skillRuntime(1).cooldownRemaining, config.cooldown);
    expect(
      audio.callHistory
              .where(
                (event) =>
                    event.method == 'playSfx' &&
                    event.target == SfxSound.attackArrow,
              )
              .length -
          configuredSfxBefore,
      1,
    );

    final angles =
        projectiles
            .map(
              (projectile) =>
                  math.atan2(projectile.direction.y, projectile.direction.x),
            )
            .toList()
          ..sort();
    expect(angles, hasLength(5));
    for (var i = 0; i < angles.length; i++) {
      expect(angles[i], closeTo((i - 2) * math.pi / 15, .0001));
    }
  });

  testWidgets(
    'each of the five arrows can damage a target once at full strength',
    (tester) async {
      final game = await loadGame(tester, 'ranger');
      silenceUnrelatedTargets(game);
      game.player.position = Vector2(400, 200);
      game.player.faceDirection(Vector2(1, 0));
      final target = game.enemies.first
        ..position = Vector2(445, 200)
        ..currentHp = 1000
        ..stunTimer = 10;
      final hpBefore = target.currentHp;
      final configuredCastDamage =
          game.player.effectiveDamage *
          game.player.skillConfig(1).damageMultiplier;
      final configuredShotDamage = configuredCastDamage;

      final projectiles = await castAndGetProjectiles(tester, game);
      expect(projectiles, hasLength(5));
      for (final projectile in projectiles) {
        final beforeHit = target.currentHp;
        projectile.update(1);
        expect(
          beforeHit - target.currentHp,
          closeTo(configuredShotDamage, .00001),
        );
        projectile.update(1);
        expect(
          beforeHit - target.currentHp,
          closeTo(configuredShotDamage, .00001),
        );
      }

      expect(
        hpBefore - target.currentHp,
        closeTo(5 * configuredShotDamage, .00001),
      );
    },
  );

  testWidgets('missed arrows do not redistribute their damage', (tester) async {
    final game = await loadGame(tester, 'ranger');
    silenceUnrelatedTargets(game);
    game.player.position = Vector2(400, 200);
    game.player.faceDirection(Vector2(1, 0));
    final target = game.enemies.first
      ..position = Vector2(450, 200)
      ..currentHp = 1000
      ..stunTimer = 10;

    final projectiles = await castAndGetProjectiles(tester, game);
    expect(projectiles, hasLength(5));
    target.position = Vector2(450, 320);
    for (final projectile in projectiles) {
      projectile.update(1);
    }

    expect(target.currentHp, 1000);
  });

  testWidgets('the map wall blocks the complete fan before its target', (
    tester,
  ) async {
    final game = await loadGame(tester, 'ranger');
    silenceUnrelatedTargets(game);
    game.player.position = Vector2(520, 336);
    game.player.faceDirection(Vector2(1, 0));
    final target = game.enemies.first
      ..position = Vector2(600, 336)
      ..currentHp = 1000
      ..stunTimer = 10;

    final projectiles = await castAndGetProjectiles(tester, game);
    expect(projectiles, hasLength(5));
    for (final projectile in projectiles) {
      projectile.update(1);
    }

    expect(target.currentHp, 1000);
    expect(projectiles.every((projectile) => projectile.isRemoving), isTrue);
  });

  testWidgets('Ember slot 1 fires its three explosive fireballs', (
    tester,
  ) async {
    final game = await loadGame(tester, 'ember_02');
    silenceUnrelatedTargets(game);
    game.player.position = Vector2(400, 200);
    game.player.faceDirection(Vector2(1, 0));

    final projectiles = await castAndGetProjectiles(tester, game);

    expect(projectiles, hasLength(3));
    expect(
      projectiles.every(
        (p) => p.type == HeroProjectileType.fireball && p.splashRadius == 45,
      ),
      isTrue,
    );
    expect(projectiles[1].direction.x, closeTo(1, .00001));
  });
}
