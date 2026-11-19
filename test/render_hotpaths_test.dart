import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/game/ai/chase_navigation.dart';
import 'package:my_game/game/components/companion_component.dart';
import 'package:my_game/game/components/dungeon_map.dart';
import 'package:my_game/game/components/floating_combat_text.dart';
import 'package:my_game/game/components/player.dart';
import 'package:my_game/game/gold_rush_game.dart';
import 'package:my_game/game/hud/game_hud.dart';
import 'package:my_game/game/hud/virtual_joystick.dart';

ui.Picture _record(void Function(ui.Canvas) draw) {
  final recorder = ui.PictureRecorder();
  draw(ui.Canvas(recorder));
  return recorder.endRecording();
}

List<ui.Picture> _observePictures() {
  final pictures = <ui.Picture>[];
  final previous = ui.Picture.onCreate;
  ui.Picture.onCreate = (picture) {
    previous?.call(picture);
    pictures.add(picture);
  };
  addTearDown(() => ui.Picture.onCreate = previous);
  return pictures;
}

List<List<bool>> _grid() => List.generate(14, (_) => List.filled(14, true));

Vector2 _step(ChaseNavigation nav, List<List<bool>> grid) => nav.step(
  position: Vector2(112, 112),
  target: Vector2(272, 112),
  grid: grid,
  speed: 80,
  dt: .5,
);

Future<void> _hud(
  WidgetTester tester,
  GoldRushGame game, {
  Widget? sibling,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Stack(
        children: [
          GameHudOverlay(key: const Key('hud'), game: game),
          ?sibling,
        ],
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Fixed map picture survives viewport resize and disposes on removal',
    () {
      final pictures = _observePictures();
      final map = DungeonMapComponent();
      _record(map.render).dispose();
      expect(pictures, hasLength(2)); // Retained floor + outer frame.
      final floor = pictures.first;
      expect(floor.debugDisposed, isFalse);
      for (var i = 0; i < 12; i++) {
        map.onGameResize(Vector2(640 + i * 20, 360 + i * 10));
        _record(map.render).dispose();
      }
      expect(pictures, hasLength(14));
      expect(map.walkableGrid.length, DungeonMapComponent.mapWidthTiles);
      expect(map.walkableGrid.first.length, DungeonMapComponent.mapHeightTiles);
      map.onRemove();
      expect(floor.debugDisposed, isTrue);
      // Reattaching the same component must not reuse a disposed native handle.
      _record(map.render).dispose();
      expect(pictures, hasLength(16));
      map.onRemove();
      expect(pictures[pictures.length - 2].debugDisposed, isTrue);
    },
  );

  test(
    'Wall cache invalidates on geometry change and releases old pictures',
    () {
      final pictures = _observePictures();
      final wall = WallBlock(position: Vector2.zero(), size: Vector2(32, 32));
      _record(wall.render).dispose();
      final original = pictures.first;
      _record(wall.render).dispose();
      expect(pictures, hasLength(3));
      wall.size.setValues(64, 64);
      _record(wall.render).dispose();
      expect(pictures, hasLength(5));
      expect(original.debugDisposed, isTrue);
      final resized = pictures[3];
      wall.onRemove();
      expect(resized.debugDisposed, isTrue);
    },
  );

  test(
    'Small footprints retain travel budget and read live grid mutations',
    () {
      final grid = _grid();
      final before = ChaseNavigation.debugPlanningGridBuildCount;
      final nav = ChaseNavigation(random: Random(7), halfSize: Vector2(10, 14));
      final movement = _step(nav, grid);
      expect(movement.x, closeTo(40, 1e-8));
      expect(movement.y, closeTo(0, 1e-8));
      expect(ChaseNavigation.debugPlanningGridBuildCount, before);
      // Mutation is on the existing object and must affect the very next route.
      for (var row = 0; row < grid[4].length; row++) {
        grid[4][row] = false;
      }
      final next = _step(nav, grid);
      expect(next.length, 0);
      expect(ChaseNavigation.debugPlanningGridBuildCount, before);
    },
  );

  test(
    'Large footprints share plans but invalidate mutated source geometry',
    () {
      final grid = _grid();
      final before = ChaseNavigation.debugPlanningGridBuildCount;
      ChaseNavigation nav() =>
          ChaseNavigation(random: Random(2), halfSize: Vector2(22, 28));
      _step(nav(), grid);
      _step(nav(), grid);
      expect(ChaseNavigation.debugPlanningGridBuildCount, before + 1);
      grid[5][5] = false;
      _step(nav(), grid);
      expect(ChaseNavigation.debugPlanningGridBuildCount, before + 2);
      _step(
        ChaseNavigation(random: Random(2), halfSize: Vector2(24, 28)),
        grid,
      );
      expect(ChaseNavigation.debugPlanningGridBuildCount, before + 3);
      _step(nav(), [
        for (final column in grid) [...column],
      ]);
      expect(ChaseNavigation.debugPlanningGridBuildCount, before + 4);
    },
  );

  test('Exactly half a tile still tests the adjacent cell', () {
    final grid = _grid()..[4][3] = false;
    Vector2 vertical(double halfWidth) =>
        ChaseNavigation(
          random: Random(3),
          halfSize: Vector2(halfWidth, 10),
        ).step(
          position: Vector2(112, 112),
          target: Vector2(112, 272),
          grid: grid,
          speed: 80,
          dt: .5,
        );
    expect(vertical(15.9).y, greaterThan(0));
    expect(vertical(16).length, 0);
  });

  test('Planning cache bounds retained maps', () {
    final grids = List.generate(5, (_) => _grid());
    final before = ChaseNavigation.debugPlanningGridBuildCount;
    for (final grid in grids) {
      _step(
        ChaseNavigation(random: Random(1), halfSize: Vector2(22, 28)),
        grid,
      );
    }
    _step(
      ChaseNavigation(random: Random(1), halfSize: Vector2(22, 28)),
      grids.first,
    );
    expect(ChaseNavigation.debugPlanningGridBuildCount, before + 6);
  });

  test('Companion static pictures survive animation and dispose together', () {
    final pictures = _observePictures();
    final player = PlayerComponent(position: Vector2(100, 100));
    // Alias intentionally exercises the procedural fallback, not lazy I/O.
    final companion = CompanionComponent(companionId: 'frost', player: player);
    _record(companion.render).dispose();
    expect(pictures, hasLength(4)); // Field, runes, chassis + outer frame.
    final retained = pictures.take(3).toList();
    for (var i = 0; i < 10; i++) {
      companion.update(1 / 60);
      player.position.x += 2;
      _record(companion.render).dispose();
    }
    expect(pictures, hasLength(14));
    companion.onRemove();
    expect(retained.every((picture) => picture.debugDisposed), isTrue);
  });

  test(
    'Combat layouts reuse opaque glyphs across movement, scale and actors',
    () {
      final before = FloatingCombatText.debugLayoutBuildCount;
      final text = FloatingCombatText(position: Vector2.zero(), text: '-73192');
      for (var i = 0; i < 20; i++) {
        _record(text.render).dispose();
        text.update(1 / 60);
      }
      expect(FloatingCombatText.debugLayoutBuildCount, before + 2);
      final same = FloatingCombatText(
        position: Vector2(20, 20),
        text: '-73192',
      );
      _record(same.render).dispose();
      expect(FloatingCombatText.debugLayoutBuildCount, before + 2);
      final critical = FloatingCombatText(
        position: Vector2.zero(),
        text: '-73192',
        type: CombatTextType.criticalDamage,
      );
      _record(critical.render).dispose();
      expect(FloatingCombatText.debugLayoutBuildCount, before + 4);
      text.update(.25); // Fade changes the actual paragraph paint style.
      _record(text.render).dispose();
      final faded = FloatingCombatText.debugLayoutBuildCount;
      _record(text.render).dispose();
      expect(FloatingCombatText.debugLayoutBuildCount, faded);
      expect(text.text, '-73192');
    },
  );

  test('Layout eviction bounds memory without suppressing any damage text', () {
    final before = FloatingCombatText.debugLayoutBuildCount;
    for (var i = 0; i < 210; i++) {
      final text = FloatingCombatText(
        position: Vector2.zero(),
        text: 'cache-$i',
      );
      _record(text.render).dispose();
      expect(text.text, 'cache-$i');
    }
    expect(FloatingCombatText.debugLayoutBuildCount, before + 420);
    expect(FloatingCombatText.debugCachedLayoutCount, lessThanOrEqualTo(192));
    _record(
      FloatingCombatText(position: Vector2.zero(), text: 'cache-0').render,
    ).dispose();
    expect(FloatingCombatText.debugLayoutBuildCount, before + 422);
  });

  testWidgets(
    'Stable HUD notifications do not rebuild and joystick is retained',
    (tester) async {
      final game = GoldRushGame();
      await _hud(tester, game);
      final hp = tester.widget(find.text('HP'));
      final joystick = tester.widget<VirtualJoystick>(
        find.byType(VirtualJoystick),
      );
      for (var frame = 0; frame < 60; frame++) {
        game.onPlayerStatsChanged?.call();
        await tester.pump(const Duration(milliseconds: 16));
        expect(identical(tester.widget(find.text('HP')), hp), isTrue);
      }
      game.player.currentHp = 81;
      game.onPlayerStatsChanged?.call();
      await tester.pump();
      expect(find.text('81/100'), findsOneWidget);
      expect(identical(tester.widget(find.text('HP')), hp), isFalse);
      expect(
        identical(tester.widget(find.byType(VirtualJoystick)), joystick),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(game.onPlayerStatsChanged, isNull);
    },
  );

  testWidgets(
    'Fractional Ki events coalesce but affordability changes immediately',
    (tester) async {
      final game = GoldRushGame();
      game.player.currentKi = 40.01;
      await _hud(tester, game);
      final hp = tester.widget(find.text('HP'));
      for (var i = 0; i < 8; i++) {
        game.player.currentKi += .001;
        game.onPlayerStatsChanged?.call();
        await tester.pump();
      }
      expect(identical(tester.widget(find.text('HP')), hp), isTrue);
      final cost = game.player.skillConfig(1).kiCost;
      game.player.currentKi = cost - .001;
      game.onPlayerStatsChanged?.call();
      await tester.pump();
      final before = tester.widget(find.text('HP'));
      game.player.currentKi = cost;
      game.onPlayerStatsChanged?.call();
      await tester.pump();
      expect(identical(tester.widget(find.text('HP')), before), isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Cooldown clock works at full Ki and stops advancing while paused',
    (tester) async {
      final game = GoldRushGame();
      game.player.skill1VisualCd = 1;
      await _hud(tester, game);
      expect(find.text('1.0s'), findsOneWidget);
      game.player.update(.2);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('0.8s'), findsOneWidget);
      game.pauseEngine();
      game.player.skill1VisualCd = .4;
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('0.8s'), findsOneWidget);
      game.resumeEngine();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('0.4s'), findsOneWidget);
      game.player.skill1VisualCd = 0;
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('0.4s'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Persistent build notifications still defer state safely', (
    tester,
  ) async {
    final game = GoldRushGame();
    final signal = ValueNotifier(false);
    addTearDown(signal.dispose);
    await _hud(
      tester,
      game,
      sibling: ValueListenableBuilder<bool>(
        valueListenable: signal,
        builder: (context, notify, _) {
          if (notify) {
            game.player.currentHp = 77;
            game.onPlayerStatsChanged?.call();
          }
          return const SizedBox.shrink();
        },
      ),
    );
    signal.value = true;
    await tester.pump();
    await tester.pump();
    expect(find.text('77/100'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
