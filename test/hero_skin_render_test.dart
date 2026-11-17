import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/core/hero_skin_style.dart';
import 'package:my_game/game/components/player.dart';
import 'package:my_game/screens/widgets/hero_showcase_painter.dart';
import 'package:flame/components.dart';

void main() {
  test('Skin belongs to its hero and does not change combat stats', () {
    expect(
      HeroSkinStyle.resolve('tanker', 'skin_tanker_magma')?.name,
      'Hiệp Sĩ Dung Nham',
    );
    expect(HeroSkinStyle.resolve('george', 'skin_tanker_magma'), isNull);
    final plain = PlayerComponent(position: Vector2.zero(), heroId: 'tanker');
    final skinned = PlayerComponent(
      position: Vector2.zero(),
      heroId: 'tanker',
      skinId: 'skin_tanker_magma',
    );
    expect(
      [skinned.maxHp, skinned.maxKi, skinned.damage, skinned.speed],
      [plain.maxHp, plain.maxKi, plain.damage, plain.speed],
    );
  });

  testWidgets(
    'Equipping magma changes rendered hero pixels and removing restores them',
    (tester) async {
      final key = GlobalKey();
      Future<Uint8List> render(String? skin) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: RepaintBoundary(
                key: key,
                child: TickerMode(
                  enabled: false,
                  child: HeroShowcaseWidget(
                    heroId: 'tanker',
                    themeColor: Colors.cyan,
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
          final bytes = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          image.dispose();
          return Uint8List.fromList(bytes!.buffer.asUint8List());
        }))!;
      }

      final before = await render(null);
      final equipped = await render('skin_tanker_magma');
      expect(equipped, isNot(orderedEquals(before)));
      final removed = await render(null);
      expect(removed, orderedEquals(before));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
