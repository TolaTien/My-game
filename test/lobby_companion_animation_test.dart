import 'dart:ui' as ui;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/registry/sprite_image_cache.dart';
import 'package:my_game/registry/companion_texture.dart';
import 'package:my_game/screens/widgets/hero_showcase_painter.dart';
import 'package:my_game/screens/widgets/lobby_companion.dart';
import 'package:my_game/screens/shop_dialog.dart';
import 'package:my_game/models/player_profile.dart';
import 'package:my_game/services/player_storage.dart';
import 'package:my_game/game/rendering/fox_spirit_visual.dart';
import 'package:my_game/game/rendering/dragon_spirit_visual.dart';

Future<List<int>> raster(String id, double progress) async {
  final recorder = ui.PictureRecorder();
  CompanionLobbyPainter(
    id,
    AlwaysStoppedAnimation(progress),
  ).paint(Canvas(recorder), const Size(100, 120));
  final picture = recorder.endRecording();
  final image = await picture.toImage(100, 120);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final result = bytes!.buffer.asUint8List().toList();
  image.dispose();
  picture.dispose();
  return result;
}

class _CountingCompanionBundle extends CachingAssetBundle {
  final loads = <String, int>{};

  @override
  Future<ByteData> load(String key) async {
    loads.update(key, (count) => count + 1, ifAbsent: () => 1);
    return rootBundle.load(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Concurrent companion lookups share final cleaned images and atlases',
    () async {
      final bundle = _CountingCompanionBundle();
      final cache = SpriteImageCache.forTesting(bundle);
      cache.getCompanionImage('luna_fox');
      cache.getCompanionImage('luna_fox');
      cache.getCompanionIdleSheet('luna_fox');
      cache.getCompanionRunSheet('luna_fox');
      cache.getCompanionIdleSheet('pyro_frost_dragon');
      await Future.wait([cache.preloadAll(), cache.preloadAll()]);
      expect(bundle.loads.values, everyElement(1));
      final portrait = cache.getCompanionImage('luna_fox');
      expect(portrait, isNotNull);
      expect(await portrait!.toByteData(), isNotNull);
      expect(cache.getCompanionImage('luna_fox'), same(portrait));
      expect(cache.getCompanionIdleSheet('luna_fox'), isNotNull);
      expect(cache.getCompanionRunSheet('luna_fox'), isNotNull);
      expect(cache.getCompanionIdleSheet('pyro_frost_dragon'), isNotNull);
      expect(cache.getCompanionRunSheet('pyro_frost_dragon'), isNull);
      expect(cache.getCompanionImage('gem_tumbler'), isNull);
      expect(cache.getHeroAnimations('nova'), isNull);
      await cache.preloadHero('nova');
      expect(cache.getHeroAnimations('nova', facingRow: 0), isNotNull);
      expect(cache.getHeroAnimations('nova', facingRow: 4), isNotNull);
      for (final id in [
        'nova_blade',
        'shadow_01',
        'ember_02',
        'valeria',
        'garrick',
        'kaelen',
      ]) {
        await cache.preloadHero(id);
        for (var slot = 1; slot <= 3; slot++) {
          expect(
            cache.getSkillAnimation(id, slot),
            isNotNull,
            reason: '$id slot $slot',
          );
        }
      }
    },
  );
  test(
    'Dragon has eight transparent wingbeat frames and a seamless timed loop',
    () async {
      ui.Image? sheet;
      for (var i = 0; i < 200 && sheet == null; i++) {
        sheet = SpriteImageCache.instance.getCompanionIdleSheet(
          'pyro_frost_dragon',
        );
        if (sheet == null) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }
      expect(sheet, isNotNull);
      final bytes = (await sheet!.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      expect(bytes[3], 0);
      for (var frame = 0; frame < 8; frame++) {
        var count = 0;
        final left = (frame % 4) * sheet.width ~/ 4,
            top = (frame ~/ 4) * sheet.height ~/ 2;
        for (var y = top; y < top + sheet.height ~/ 2; y += 6) {
          for (var x = left; x < left + sheet.width ~/ 4; x += 6) {
            if (bytes[(y * sheet.width + x) * 4 + 3] > 128) count++;
          }
        }
        expect(count, greaterThan(100), reason: 'Dragon frame $frame');
        expect(DragonSpiritVisual.frameAt(frame / 8), frame);
      }
      expect(DragonSpiritVisual.frameAt(0), DragonSpiritVisual.frameAt(1));
      expect(
        await raster('pyro_frost_dragon', 0),
        isNot(equals(await raster('pyro_frost_dragon', .05))),
      );
    },
  );
  test(
    'Lobby fox walks both directions and rests at the ends without teleporting',
    () {
      expect(FoxLobbyMotion.at(.5).running, isFalse);
      expect(FoxLobbyMotion.at(1.75).running, isTrue);
      expect(FoxLobbyMotion.at(1.75).facingRight, isTrue);
      expect(FoxLobbyMotion.at(3).running, isFalse);
      expect(FoxLobbyMotion.at(4.25).facingRight, isFalse);
      expect(FoxLobbyMotion.at(4.25).running, isTrue);
      expect(FoxLobbyMotion.at(0).x, FoxLobbyMotion.at(6).x);
      for (var i = 0; i < 600; i++) {
        final a = FoxLobbyMotion.at(i / 100),
            b = FoxLobbyMotion.at((i + 1) / 100);
        expect(a.x, inInclusiveRange(32, 68));
        expect((a.x - b.x).abs(), lessThan(.3));
      }
    },
  );
  test(
    'Fox run atlas decodes with transparency and distinct running poses',
    () async {
      ui.Image? sheet;
      for (var i = 0; i < 200 && sheet == null; i++) {
        sheet = SpriteImageCache.instance.getCompanionRunSheet('luna_fox');
        if (sheet == null) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }
      expect(sheet, isNotNull);
      final data = (await sheet!.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      expect(data[3], 0);
      expect(
        await raster('luna_fox', .2),
        isNot(equals(await raster('luna_fox', .25))),
      );
    },
  );
  test(
    'Combat fox aura animates and strengthens during its existing skill',
    () async {
      Future<List<int>> draw(double seconds, bool active) async {
        final recorder = ui.PictureRecorder();
        FoxSpiritVisual.drawAura(
          Canvas(recorder),
          center: const Offset(32, 32),
          seconds: seconds,
          empowered: active,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(64, 64);
        final data = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List().toList();
        image.dispose();
        picture.dispose();
        return data;
      }

      expect(await draw(.3, false), isNot(equals(await draw(.6, false))));
      expect(await draw(.3, true), isNot(equals(await draw(.3, false))));
      expect(FoxSpiritVisual.frameAt(0), FoxSpiritVisual.frameAt(2));
    },
  );
  test(
    'Fox animation atlas has eight visible poses and a transparent backdrop',
    () async {
      ui.Image? sheet;
      for (var i = 0; i < 200 && sheet == null; i++) {
        sheet = SpriteImageCache.instance.getCompanionIdleSheet('luna_fox');
        if (sheet == null) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }
      expect(sheet, isNotNull);
      final bytes = (await sheet!.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      expect(bytes[3], 0, reason: 'No opaque rectangle behind the fox');
      for (var frame = 0; frame < 8; frame++) {
        var opaque = 0;
        final left = (frame % 4) * sheet.width ~/ 4,
            top = (frame ~/ 4) * sheet.height ~/ 2;
        for (var y = top; y < top + sheet.height ~/ 2; y += 4) {
          for (var x = left; x < left + sheet.width ~/ 4; x += 4) {
            if (bytes[(y * sheet.width + x) * 4 + 3] > 128) opaque++;
          }
        }
        expect(
          opaque,
          greaterThan(100),
          reason: 'Frame $frame contains its fox',
        );
      }
      expect(
        await raster('luna_fox', 0),
        isNot(equals(await raster('luna_fox', .05))),
      );
    },
  );
  test('Basic companions have distinct role colors', () async {
    final attack = await raster('comp_attack', .1);
    final defense = await raster('comp_defense', .1);
    final control = await raster('comp_control', .1);
    expect(attack, isNot(equals(defense)));
    expect(defense, isNot(equals(control)));
    expect(attack, isNot(equals(control)));
  });
  test(
    'Removes detached black debris while preserving attached outlines',
    () async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(4, 4, 4, 4),
        Paint()..color = Colors.black,
      );
      canvas.drawRect(
        const Rect.fromLTWH(5, 5, 2, 2),
        Paint()..color = Colors.cyan,
      );
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 1, 1),
        Paint()..color = Colors.black,
      );
      final picture = recorder.endRecording();
      final source = await picture.toImage(12, 12);
      final cleaned = await cleanCompanionTexture(source);
      final bytes = (await cleaned.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      expect(bytes[3], 0);
      expect(bytes.sublist(0, 4), [
        0,
        0,
        0,
        0,
      ], reason: 'Transparent debris must not leave colored sampling streaks');
      expect(bytes[(4 * 12 + 4) * 4 + 3], 255);
      expect(bytes[(5 * 12 + 5) * 4 + 3], 255);
      cleaned.dispose();
      source.dispose();
      picture.dispose();
    },
  );
  test(
    'Every textured companion loads and changes shape across animation frames',
    () async {
      for (final id in SpriteImageCache.companionSpritePaths.keys) {
        ui.Image? loaded;
        for (var i = 0; i < 200 && loaded == null; i++) {
          loaded = SpriteImageCache.instance.getCompanionImage(id);
          if (loaded == null) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        }
        expect(loaded, isNotNull, reason: id);
        final first = await raster(id, 0);
        final next = await raster(id, .237);
        expect(next, isNot(equals(first)), reason: '$id must animate');
      }
      final preview = Platform.environment['COMPANION_PREVIEW'];
      if (preview != null) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawColor(const Color(0xFFB9D4EC), BlendMode.src);
        var row = 0;
        for (final id in SpriteImageCache.companionSpritePaths.keys) {
          for (var frame = 0; frame < 4; frame++) {
            canvas.save();
            canvas.translate(frame * 180.0, row * 180.0);
            CompanionLobbyPainter(
              id,
              AlwaysStoppedAnimation(frame * .137),
            ).paint(canvas, const Size(180, 180));
            canvas.restore();
          }
          row++;
        }
        final picture = recorder.endRecording();
        final image = await picture.toImage(720, row * 180);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(preview).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
        picture.dispose();
      }
    },
  );

  for (final size in [const Size(640, 320), const Size(844, 390)]) {
    testWidgets('Compact companion shop retains all eight offers at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      final previous = PlayerStorage.currentProfile;
      PlayerStorage.profileNotifier.value = const PlayerProfile(gold: 5000);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        PlayerStorage.profileNotifier.value = previous;
      });
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ShopDialog())),
      );
      await tester.tap(find.text('TRỢ THỦ AI'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      for (final entry in {
        'comp_attack': 2000,
        'comp_defense': 2500,
        'comp_control': 3000,
        'cyber_drone': 4000,
        'luna_fox': 4500,
        'orbit_03': 5000,
        'aegis_x9': 8000,
        'pyro_frost_dragon': 10000,
      }.entries) {
        final preview = find.byWidgetPredicate(
          (widget) =>
              widget is LobbyCompanion && widget.companionId == entry.key,
        );
        for (var drag = 0; drag < 15 && preview.evaluate().isEmpty; drag++) {
          await tester.drag(
            find.byType(ListView).hitTestable(),
            const Offset(-130, 0),
          );
          await tester.pump(const Duration(milliseconds: 100));
          expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 1);
        }
        expect(preview, findsOneWidget, reason: entry.key);
        final card = find
            .ancestor(of: preview, matching: find.byType(Column))
            .first;
        expect(
          find.descendant(of: card, matching: find.text('${entry.value} VÀNG')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
      expect(find.textContaining('Gem-Tumbler'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'Hero stage equips, switches and removes animated companion without overflow',
    (tester) async {
      Future<void> show(String? id) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: HeroShowcaseWidget(
                heroId: 'george',
                themeColor: Colors.amber,
                companionId: id,
                width: 180,
                height: 190,
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 150));
        expect(tester.takeException(), isNull);
      }

      await show('pyro_frost_dragon');
      expect(find.byType(LobbyCompanion), findsOneWidget);
      final stage = tester.getRect(find.byType(HeroShowcaseWidget));
      final companion = tester.getRect(find.byType(LobbyCompanion));
      expect(companion.left, greaterThanOrEqualTo(stage.left));
      expect(companion.right, lessThanOrEqualTo(stage.right));
      expect(companion.top, greaterThanOrEqualTo(stage.top));
      expect(companion.bottom, lessThanOrEqualTo(stage.bottom));
      await show('luna_fox');
      expect(
        tester.widget<LobbyCompanion>(find.byType(LobbyCompanion)).companionId,
        'luna_fox',
      );
      await show(null);
      expect(find.byType(LobbyCompanion), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
