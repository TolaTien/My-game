import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_game/screens/shop_dialog.dart';
import 'package:my_game/screens/widgets/shop_visuals.dart';
import 'package:my_game/services/player_storage.dart';

void main() {
  testWidgets(
    'Shop portraits and restored companions decode and Ember has transparent frames',
    (tester) async {
      await tester.runAsync(() async {
        final assets = [
          'assets/images/heroes/kale/kaelen_portrait.png',
          'assets/images/heroes/ember/Ember-idle.png',
          for (final name in [
            'aegis_x9',
            'cyber_drone',
            'pyro_frost_dragon',
            'gem_tumbler',
            'luna_fox',
            'orbit_03',
          ])
            'assets/images/companions/$name.png',
        ];
        for (final asset in assets) {
          final data = await rootBundle.load(asset);
          final codec = await ui.instantiateImageCodec(
            data.buffer.asUint8List(),
          );
          final frame = await codec.getNextFrame();
          expect(frame.image.width, greaterThan(0), reason: asset);
          if (asset.endsWith('Ember-idle.png')) {
            expect(frame.image.width % 5, 0);
            expect(frame.image.height % 5, 0);
            final pixels = await frame.image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            expect(
              pixels!.getUint8(3),
              0,
              reason: 'Existing sprite sheet has a transparent background',
            );
          }
          frame.image.dispose();
          codec.dispose();
        }
      });
    },
  );

  testWidgets('Final shop pages render with real portraits at desktop size', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await PlayerStorage.loadProfile();
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final previewDir = Platform.environment['SHOP_PREVIEW_DIR'];
    if (previewDir != null) {
      await tester.runAsync(() async {
        final font = FontLoader('ShopPreview')
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
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: previewDir != null ? 'ShopPreview' : null),
        home: Scaffold(
          body: RepaintBoundary(key: key, child: const ShopDialog()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    var index = 0;
    for (final tab in ['NHÂN VẬT', 'TRỢ THỦ AI', 'TRANG PHỤC (SKIN)']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byTooltip('Cuộn sang phải').hitTestable().first);
        await tester.pumpAndSettle();
      }
      // Allow real asset decoding to complete outside the fake test clock.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      if (index == 0) {
        final kale = tester.widget<ShopSpritePreview>(
          find.byKey(const ValueKey('shop_hero_kaelen')),
        );
        expect(kale.asset, 'assets/images/heroes/kale/kaelen_portrait.png');
        final ember = tester.widget<ShopSpritePreview>(
          find.byKey(const ValueKey('shop_hero_ember_02')),
        );
        expect(ember.columns, 5);
        expect(ember.rows, 5);
      }
      expect(tester.takeException(), isNull, reason: tab);
      if (previewDir != null) {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$previewDir/shop-fixed-$index.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      index++;
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
