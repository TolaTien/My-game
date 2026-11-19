// Run with: flutter test tool/render_benchmark.dart --no-pub --reporter expanded
// Measures CPU update and Canvas command recording, not raster/GPU time or FPS.
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/game/components/boss_enemy.dart';
import 'package:my_game/game/components/companion_component.dart';
import 'package:my_game/game/components/enemy_skeleton.dart';
import 'package:my_game/game/components/enemy_zombie.dart';
import 'package:my_game/game/gold_rush_game.dart';
import 'package:my_game/models/player_profile.dart';
import 'package:my_game/registry/asset_registry.dart';
import 'package:my_game/registry/sprite_image_cache.dart';
import 'package:my_game/services/audio_service.dart';

const _samples = 120;
const _warmup = 30;
const _dt = 1 / 60;

Map<String, double> _stats(List<double> samples) {
  final sorted = [...samples]..sort();
  double percentile(double p) => sorted[(p * sorted.length).ceil() - 1];
  return {
    'avg_ms': samples.reduce((a, b) => a + b) / samples.length,
    'p95_ms': percentile(.95),
    'p99_ms': percentile(.99),
  };
}

Future<GoldRushGame> _scene(WidgetTester tester, int zombies, int skeletons,
    int companions) async {
  final game = GoldRushGame(
    selectedMapConfig: GameAssetRegistry.instance.getMap('sunken_golden_sanctum'),
    playerProfile: const PlayerProfile(
      selectedHeroId: 'kaelen',
      unlockedHeroIds: ['kaelen'],
      heroLevels: {'kaelen': 1},
    ),
  );
  await tester.pumpWidget(Directionality(
    textDirection: TextDirection.ltr,
    child: GameWidget<GoldRushGame>(game: game),
  ));
  await tester.pump();
  await tester.runAsync(() async {
    // This file is a flutter_test entrypoint outside test/.
    // ignore: invalid_use_of_visible_for_testing_member
    await game.toBeLoaded();
    await game.ready();
  });
  game.pauseEngine();
  for (final actor in [...game.enemies, ...game.skeletons, ...game.pickups]) {
    actor.removeFromParent();
  }
  game.boss?.removeFromParent();
  game.enemies.clear();
  game.skeletons.clear();
  game.pickups.clear();
  await tester.runAsync(game.ready);
  game.player.position.setValues(400, 300);
  game.player.currentHp = game.player.maxHp;
  game.player.resetCombatState();
  final points = <Vector2>[];
  for (var x = 4; x < 23; x++) {
    for (var y = 3; y < 19; y++) {
      final point = Vector2(x * 32 + 16, y * 32 + 16);
      if (game.walkableGrid[x][y] &&
          point.distanceTo(game.player.position) > 60 &&
          point.distanceTo(game.player.position) < 250) {
        points.add(point);
      }
    }
  }
  points.shuffle(Random(731));
  for (var i = 0; i < zombies; i++) {
    final enemy = ZombieEnemy(
      position: points[i].clone(),
      player: game.player,
      random: Random(1000 + i),
    )..currentHp = 1000000;
    game.enemies.add(enemy);
    await game.world.add(enemy);
  }
  for (var i = 0; i < skeletons; i++) {
    final enemy = SkeletonEnemy(
      position: points[zombies + i].clone(),
      player: game.player,
      random: Random(2000 + i),
    )..currentHp = 1000000;
    game.skeletons.add(enemy);
    await game.world.add(enemy);
  }
  game.boss = BossEnemy(
    position: Vector2(700, 380),
    player: game.player,
    random: Random(3000),
  )..currentHp = 1000000;
  await game.world.add(game.boss!);
  const ids = ['aegis_x9', 'orbit_03', 'cyber_drone', 'luna_fox'];
  for (var i = 0; i < companions; i++) {
    final companion = CompanionComponent(
      companionId: ids[i],
      player: game.player,
      orbitRadius: 45 + i * 12,
    )..orbitAngle = i * pi / 2;
    if (i == 0) game.companion = companion;
    await game.world.add(companion);
  }
  await tester.runAsync(game.ready);
  expect(game.player.isMounted, isTrue);
  expect(game.enemies.every((e) => e.isMounted), isTrue);
  expect(game.skeletons.every((e) => e.isMounted), isTrue);
  game.isVictoryTriggered = false;
  game.isGameOverTriggered = false;
  game.resumeEngine();
  return game;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('CPU render benchmark, fixed input, three scenes x three runs',
      (tester) async {
    AudioService.setInstance(MockAudioService());
    await tester.runAsync(() async {
      await GameAssetRegistry.instance.initialize(bundle: rootBundle);
      await SpriteImageCache.instance.preloadAll();
    });
    expect(GameAssetRegistry.instance.getHero('kaelen'), isNotNull);
    expect(SpriteImageCache.instance.getHeroImage('kaelen'), isNotNull);
    final results = <Map<String, Object>>[];
    for (final scene in [
      (name: 'normal', zombies: 5, skeletons: 3, companions: 1, skills: false),
      (name: 'stress', zombies: 24, skeletons: 12, companions: 4, skills: false),
      (name: 'stress_skills', zombies: 24, skeletons: 12, companions: 4, skills: true),
    ]) {
      for (var run = 1; run <= 3; run++) {
        final game = await _scene(
            tester, scene.zombies, scene.skeletons, scene.companions);
        final updates = <double>[];
        final recordings = <double>[];
        final watch = Stopwatch();
        for (var frame = 0; frame < _warmup + _samples; frame++) {
          // Fixture replenishment is outside the measured regions. Keep deaths,
          // victories and resource exhaustion from changing scene populations.
          game.player.currentHp = game.player.maxHp;
          game.player.currentKi = game.player.maxKi;
          game.player.moveDirection.setZero();
          watch.reset();
          watch.start();
          if (scene.skills && frame % 30 == 0) {
            game.player.resetCombatState();
            game.onSkill1();
            game.onSkill2();
            game.player.currentKi = game.player.maxKi;
            game.onSkill3();
          }
          if (frame % 15 == 0) game.onBasicAttack();
          game.update(_dt);
          watch.stop();
          final updateMs = watch.elapsedTicks * 1000 / watch.frequency;
          // Drain normal Flame additions/removals outside update measurement;
          // effects created by the real skill APIs must actually mount/render.
          await tester.runAsync(game.ready);
          final recorder = ui.PictureRecorder();
          final canvas = ui.Canvas(recorder);
          watch.reset();
          watch.start();
          game.render(canvas);
          final picture = recorder.endRecording();
          watch.stop();
          final recordingMs = watch.elapsedTicks * 1000 / watch.frequency;
          picture.dispose();
          if (frame >= _warmup) {
            updates.add(updateMs);
            recordings.add(recordingMs);
          }
        }
        results.add({
          'scene': scene.name,
          'run': run,
          'samples': _samples,
          'warmup': _warmup,
          'zombies': scene.zombies,
          'skeletons': scene.skeletons,
          'companions': scene.companions,
          'update_cpu': _stats(updates),
          'canvas_record_cpu': _stats(recordings),
        });
        game.pauseEngine();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    }
    // One JSON payload; no file output, forced exit or synthetic FPS claim.
    // ignore: avoid_print
    print(jsonEncode({'benchmark': 'render_hotpaths_v1', 'results': results}));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
