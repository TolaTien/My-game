import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/game/components/player.dart';
import 'package:my_game/game/hud/virtual_joystick.dart';
import 'package:my_game/registry/asset_registry.dart';
import 'package:my_game/registry/sprite_image_cache.dart';
import 'package:my_game/screens/game_play_screen.dart';
import 'package:my_game/screens/lobby_screen.dart';
import 'package:my_game/screens/pvp_arena_screen.dart';

void main() {
  testWidgets('GamePlayScreen renders clean touch buttons on Mobile', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: GamePlayScreen(
            initialMapConfig: GameAssetRegistry.defaultSanctumMap,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Joystick and ATK buttons exist
      expect(find.byType(VirtualJoystick), findsOneWidget);
      expect(find.text('ATK'), findsOneWidget);

      // No desktop hotkey badges on mobile
      expect(find.text('SPACE'), findsNothing);
      expect(find.text('W A S D'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('GamePlayScreen renders joystick and action buttons with hotkeys on Desktop/Web', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: GamePlayScreen(
            initialMapConfig: GameAssetRegistry.defaultSanctumMap,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(VirtualJoystick), findsOneWidget);
      expect(find.text('SPACE'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('W A S D'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('GamePlayScreen toggles on-screen touch controls on Desktop/Web', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: GamePlayScreen(
            initialMapConfig: GameAssetRegistry.defaultSanctumMap,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Initially visible
      expect(find.byType(VirtualJoystick), findsOneWidget);

      // Tap toggle button to hide touch controls
      final toggleFinder = find.byKey(const Key('toggle_touch_controls_button'));
      expect(toggleFinder, findsOneWidget);
      await tester.tap(toggleFinder);
      await tester.pump();

      // Now touch controls are hidden, keyboard hint bar is shown
      expect(find.byType(VirtualJoystick), findsNothing);
      expect(find.textContaining('Di chuyển: WASD'), findsOneWidget);

      // Tap toggle again to restore
      await tester.tap(toggleFinder);
      await tester.pump();

      expect(find.byType(VirtualJoystick), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('PvpArenaScreen renders matchmaking view safely without crash', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PvpArenaScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(PvpArenaScreen), findsOneWidget);
    expect(find.textContaining('ĐANG TÌM TRẬN ĐỐI KHÁNG'), findsOneWidget);

    // Tap bot button
    final botBtn = find.text('GHÉP NGAY (AI BOT)');
    expect(botBtn, findsOneWidget);
    await tester.tap(botBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('LobbyScreen renders sanhcho.png background and sci-fi HUD buttons cleanly', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LobbyScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(LobbyScreen), findsOneWidget);
    expect(find.text('VÒNG QUAY'), findsOneWidget);
    expect(find.text('CỬA HÀNG'), findsOneWidget);
    expect(find.text('TỔ ĐỘI'), findsOneWidget);
    expect(find.text('CHAT AI'), findsOneWidget);
    expect(find.text('RANKING'), findsOneWidget);
    expect(find.text('1V1 ĐẤU ĐƠN'), findsOneWidget);
    expect(find.text('2V2 SONG ĐẤU'), findsOneWidget);
    expect(find.text('4V4 QUÂN ĐOÀN'), findsOneWidget);
    expect(find.text('TÌM TRẬN RANK'), findsOneWidget);

    // Bấm vào chế độ để chuyển sang PvE: mục 1v1 2v2 4v4 phải được ẩn đi
    final pvpModePill = find.textContaining('CHẾ ĐỘ: ĐẤU TRƯỜNG PVP');
    expect(pvpModePill, findsOneWidget);
    await tester.tap(pvpModePill);
    await tester.pump();

    // Trong chế độ PvE: mục 1v1 2v2 4v4 bị ẩn hoàn toàn
    expect(find.textContaining('CHẾ ĐỘ: VƯỢT ẢI HẦM NGỤC (PVE)'), findsOneWidget);
    expect(find.text('BẮT ĐẦU'), findsOneWidget);
    expect(find.text('1V1 ĐẤU ĐƠN'), findsNothing);
    expect(find.text('2V2 SONG ĐẤU'), findsNothing);
    expect(find.text('4V4 QUÂN ĐOÀN'), findsNothing);

    // Bấm lại chế độ để quay về PvP: mục 1v1 2v2 4v4 xuất hiện lại
    final pveModePill = find.textContaining('CHẾ ĐỘ: VƯỢT ẢI HẦM NGỤC (PVE)');
    await tester.tap(pveModePill);
    await tester.pump();

    expect(find.textContaining('CHẾ ĐỘ: ĐẤU TRƯỜNG PVP'), findsOneWidget);
    expect(find.text('1V1 ĐẤU ĐƠN'), findsOneWidget);
    expect(find.text('2V2 SONG ĐẤU'), findsOneWidget);
    expect(find.text('4V4 QUÂN ĐOÀN'), findsOneWidget);
    expect(find.text('TÌM TRẬN RANK'), findsOneWidget);
  });

  test('4 Original system heroes (george, ranger, tanker, ninja) render across all actions', () {
    const originalHeroes = ['george', 'ranger', 'tanker', 'ninja'];

    for (final heroId in originalHeroes) {
      final player = PlayerComponent(
        position: Vector2(100, 100),
        heroId: heroId,
      );

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // 1. Idle
      player.render(canvas);

      // 2. Run Right
      player.moveDirection = Vector2(1, 0);
      player.update(0.1);
      player.render(canvas);

      // 3. Run Up (Sau lưng)
      player.moveDirection = Vector2(0, -1);
      player.update(0.1);
      player.render(canvas);

      // 4. Run Left (Quay trái)
      player.moveDirection = Vector2(-1, 0);
      player.update(0.1);
      player.render(canvas);

      // 5. Tấn công thường
      player.performBasicAttack();
      player.update(0.1);
      player.render(canvas);

      // 6. Skill 1, 2, 3
      player.useSkill1();
      player.update(0.1);
      player.render(canvas);

      player.useSkill2();
      player.update(0.1);
      player.render(canvas);

      player.useSkill3();
      player.update(0.1);
      player.render(canvas);

      final picture = recorder.endRecording();
      expect(picture, isNotNull);
    }
  });

  test('New heroes (nova_blade, kaelen, shadow_01, ember) render across all actions in game and lobby', () {
    const newHeroes = ['nova_blade', 'kaelen', 'shadow_01', 'kale', 'shadow', 'ember_02', 'ember'];

    for (final heroId in newHeroes) {
      final player = PlayerComponent(
        position: Vector2(100, 100),
        heroId: heroId,
      );

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // 1. Idle (Đứng im - lobby & in-game animated)
      player.render(canvas);

      // 2. Run Right
      player.moveDirection = Vector2(1, 0);
      player.update(0.1);
      player.render(canvas);

      // 3. Run Up (sau lưng)
      player.moveDirection = Vector2(0, -1);
      player.update(0.1);
      player.render(canvas);

      // 4. Run Left (quay trái)
      player.moveDirection = Vector2(-1, 0);
      player.update(0.1);
      player.render(canvas);

      // 5. Run Diagonals
      player.moveDirection = Vector2(1, 1);
      player.update(0.1);
      player.render(canvas);

      player.moveDirection = Vector2(-1, -1);
      player.update(0.1);
      player.render(canvas);

      // 6. Attack (tấn công)
      player.performBasicAttack();
      player.update(0.1);
      player.render(canvas);

      final picture = recorder.endRecording();
      expect(picture, isNotNull);
    }
  });

  testWidgets('Can load Ember idle and run assets via rootBundle', (tester) async {
    final idleData = await rootBundle.load('assets/images/heroes/ember/Ember-idle.png');
    expect(idleData.lengthInBytes, greaterThan(1000000));
    final runData = await rootBundle.load('assets/images/heroes/ember/ember-run.png');
    expect(runData.lengthInBytes, greaterThan(1000000));

    await tester.runAsync(() async {
      final idleCodec = await ui.instantiateImageCodec(idleData.buffer.asUint8List());
      final idleFrame = await idleCodec.getNextFrame();
      expect(idleFrame.image.width, 1280);
      expect(idleFrame.image.height, 1280);

      final runCodec = await ui.instantiateImageCodec(runData.buffer.asUint8List());
      final runFrame = await runCodec.getNextFrame();
      expect(runFrame.image.width, 2048);
      expect(runFrame.image.height, 1536);
    });
  });
}
