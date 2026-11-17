import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/models/player_profile.dart';
import 'package:my_game/screens/widgets/expedition_lobby.dart';

void main() {
  testWidgets('Camp fits desktop and landscape phones and routes its actions', (
    tester,
  ) async {
    final animation = AnimationController(
      vsync: tester,
      duration: const Duration(seconds: 3),
    );
    addTearDown(animation.dispose);
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());
    tester.view.devicePixelRatio = 1;
    var selected = '';
    final boundaryKey = GlobalKey();
    if (Platform.environment['CAPTURE_LOBBY'] == '1') {
      await tester.runAsync(() async {
        final font = FontLoader('LobbyPreview')
          ..addFont(
            Future.value(
              ByteData.sublistView(
                await File('C:/Windows/Fonts/arial.ttf').readAsBytes(),
              ),
            ),
          );
        await font.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
      });
    }
    for (final size in [
      const Size(1440, 810),
      const Size(2560, 1470),
      const Size(844, 390),
      const Size(2560, 1080),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            fontFamily: Platform.environment['CAPTURE_LOBBY'] == '1'
                ? 'LobbyPreview'
                : null,
          ),
          home: Scaffold(
            body: RepaintBoundary(
              key: boundaryKey,
              child: ExpeditionLobby(
                profile: const PlayerProfile(gold: 22100),
                heroName: 'George',
                heroTitle: 'Chiến binh búa sấm sét',
                heroColor: Colors.amber,
                ambience: animation,
                startAction: ElevatedButton(
                  onPressed: () => selected = 'play',
                  child: const Text('KHÁM PHÁ'),
                ),
                onShop: () => selected = 'shop',
                onHeroes: () => selected = 'heroes',
                onSkins: () => selected = 'skins',
                onCompanions: () => selected = 'companions',
                onWheel: () => selected = 'wheel',
                onParty: () => selected = 'party',
                onChat: () => selected = 'chat',
                onLeaderboard: () => selected = 'rank',
                onCodex: () => selected = 'codex',
              ),
            ),
          ),
        ),
      );
      if (size.width == 1440) {
        await tester.runAsync(() async {
          await precacheImage(
            const AssetImage('assets/images/ui/expedition_camp.png'),
            tester.element(find.byType(ExpeditionLobby)),
          );
        });
      }
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull, reason: 'Layout at $size');
      final background = find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName.endsWith(
              'expedition_camp.png',
            ),
      );
      expect(tester.getRect(background).topLeft.dx, closeTo(0, .1));
      expect(tester.getRect(background).topLeft.dy, closeTo(0, .1));
      expect(tester.getRect(background).width, closeTo(size.width, .1));
      expect(tester.getRect(background).height, closeTo(size.height, .1));
      for (final entry in {
        'TƯỚNG': 'heroes',
        'TRỢ THỦ': 'companions',
        'SKIN': 'skins',
        'TỔ ĐỘI': 'party',
        'CỬA HÀNG': 'shop',
        'KHÁM PHÁ': 'play',
      }.entries) {
        await tester.tap(find.text(entry.key));
        expect(selected, entry.value);
      }
      if (size.width == 1440 && Platform.environment['CAPTURE_LOBBY'] == '1') {
        await tester.pump();
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('output').create(recursive: true);
          await File('output/expedition-lobby-preview.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
