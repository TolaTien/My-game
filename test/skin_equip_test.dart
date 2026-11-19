import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_game/core/hero_skin_style.dart';
import 'package:my_game/game/components/player.dart';
import 'package:my_game/models/player_profile.dart';
import 'package:my_game/screens/shop_dialog.dart';
import 'package:my_game/screens/widgets/hero_showcase_painter.dart';
import 'package:my_game/services/player_storage.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PlayerStorage.loadProfile();
  });

  test(
    'Buy with gold, equip correct hero, reject wrong/unowned skin and persist',
    () async {
      await PlayerStorage.saveProfile(
        const PlayerProfile(
          selectedHeroId: 'tanker',
          unlockedHeroIds: ['george', 'tanker'],
          gold: 1000,
        ),
      );
      expect(await PlayerStorage.unlockSkin('skin_tanker_magma', 130), isTrue);
      expect(PlayerStorage.currentProfile.gold, 870);
      expect(PlayerStorage.currentProfile.selectedSkinId, 'skin_tanker_magma');
      expect(await PlayerStorage.selectSkin(null), isTrue);
      expect(await PlayerStorage.selectSkin('skin_george_gold'), isFalse);
      expect(await PlayerStorage.selectSkin('skin_tanker_magma'), isTrue);
      await PlayerStorage.loadProfile();
      expect(PlayerStorage.currentProfile.selectedSkinId, 'skin_tanker_magma');
      await PlayerStorage.selectHero('george');
      expect(PlayerStorage.currentProfile.selectedSkinId, isNull);
      expect(await PlayerStorage.selectSkin('skin_tanker_magma'), isFalse);
      expect(PlayerStorage.currentProfile.selectedSkinId, isNull);
    },
  );
  test(
    'Buying another hero skin adds ownership without changing current outfit',
    () async {
      await PlayerStorage.saveProfile(
        const PlayerProfile(
          gold: 1000,
          unlockedSkinIds: ['skin_george_gold'],
          selectedSkinId: 'skin_george_gold',
        ),
      );
      await PlayerStorage.unlockSkin('skin_tanker_magma', 130);
      expect(
        PlayerStorage.currentProfile.unlockedSkinIds,
        contains('skin_tanker_magma'),
      );
      expect(PlayerStorage.currentProfile.selectedSkinId, 'skin_george_gold');
      expect(HeroSkinStyle.resolve('kale', 'skin_kaelen_emperor'), isNotNull);
    },
  );

  testWidgets(
    'Equipping and removing skin change lobby pixels and restore original',
    (tester) async {
      final key = GlobalKey();
      Future<Uint8List> capture(String? skin) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: RepaintBoundary(
                key: key,
                child: TickerMode(
                  enabled: false,
                  child: HeroShowcaseWidget(
                    heroId: 'tanker',
                    themeColor: Colors.lightBlue,
                    skinId: skin,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        return (await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          final pixels = Uint8List.fromList(data!.buffer.asUint8List());
          image.dispose();
          return pixels;
        }))!;
      }

      final normal = await capture(null);
      final magma = await capture('skin_tanker_magma');
      expect(magma, isNot(orderedEquals(normal)));
      expect(await capture(null), orderedEquals(normal));
      expect(await capture('skin_george_gold'), orderedEquals(normal));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Combat renderer applies skin but HP, Ki, damage and speed are unchanged',
    (tester) async {
      final plain = PlayerComponent(position: Vector2.zero(), heroId: 'tanker');
      final skin = PlayerComponent(
        position: Vector2.zero(),
        heroId: 'tanker',
        skinId: 'skin_tanker_magma',
      );
      expect(
        [skin.maxHp, skin.maxKi, skin.damage, skin.speed],
        [plain.maxHp, plain.maxKi, plain.damage, plain.speed],
      );
      await tester.runAsync(() async {
        Future<Uint8List> pixels(PlayerComponent p) async {
          final recorder = ui.PictureRecorder();
          p.render(ui.Canvas(recorder)..translate(50, 50));
          final picture = recorder.endRecording();
          final image = await picture.toImage(140, 140);
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          final result = Uint8List.fromList(data!.buffer.asUint8List());
          image.dispose();
          picture.dispose();
          return result;
        }

        expect(await pixels(skin), isNot(orderedEquals(await pixels(plain))));
      });
    },
  );

  testWidgets(
    'Shop rejects mismatched skin and switches equip button after valid selection',
    (tester) async {
      await PlayerStorage.saveProfile(
        const PlayerProfile(
          unlockedHeroIds: ['george', 'tanker'],
          unlockedSkinIds: ['skin_tanker_magma'],
        ),
      );
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ShopDialog())),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('TRANG PHỤC (SKIN)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('MẶC'));
      await tester.pumpAndSettle();
      expect(PlayerStorage.currentProfile.selectedSkinId, isNull);
      expect(
        find.text('Hãy chọn tướng Hiệp Sĩ Tanker trước khi mặc skin này.'),
        findsOneWidget,
      );
      await PlayerStorage.selectHero('tanker');
      await tester.pumpAndSettle();
      await tester.tap(find.text('MẶC'));
      await tester.pumpAndSettle();
      expect(PlayerStorage.currentProfile.selectedSkinId, 'skin_tanker_magma');
      expect(find.text('GỠ SKIN'), findsOneWidget);
      await tester.tap(find.text('GỠ SKIN'));
      await tester.pumpAndSettle();
      expect(PlayerStorage.currentProfile.selectedSkinId, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
