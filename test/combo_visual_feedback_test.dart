import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/game/components/player.dart';
import 'package:my_game/registry/asset_registry.dart';
import 'package:my_game/registry/sprite_image_cache.dart';
import 'package:my_game/services/audio_service.dart';

List<({Rect bounds, double sweep, Paint paint})> _renderArcs(
  PlayerComponent player,
) {
  final canvas = TestRecordingCanvas();
  player.render(canvas);
  return [
    for (final entry in canvas.invocations)
      if (entry.invocation.memberName == #drawArc)
        (
          bounds: entry.invocation.positionalArguments[0] as Rect,
          sweep: entry.invocation.positionalArguments[2] as double,
          paint: entry.invocation.positionalArguments[4] as Paint,
        ),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    final previous = AudioService.instance;
    AudioService.setInstance(MockAudioService());
    addTearDown(() => AudioService.setInstance(previous));
  });

  for (final heroId in ['george', 'garrick']) {
    test('$heroId renders a distinct cue at each actual swing start', () async {
      if (heroId == 'garrick') {
        await GameAssetRegistry.instance.initialize();
        await SpriteImageCache.instance.preloadHero(heroId);
      }
      final player = PlayerComponent(position: Vector2.zero(), heroId: heroId);
      expect(
        SpriteImageCache.instance.getHeroAnimations(
          heroId,
          facingRow: player.facingRow,
        ),
        heroId == 'garrick' ? isNotNull : isNull,
      );
      expect(_renderArcs(player), isEmpty);

      expect(player.performBasicAttack(), isTrue);
      final first = _renderArcs(player).single;
      expect(first.bounds.width, greaterThan(first.bounds.height));
      player.update(.06);
      final fading = _renderArcs(player).single;
      expect(fading.paint.color.a, inExclusiveRange(0, first.paint.color.a));
      player.update(.09);
      expect(player.isAttacking, isTrue);
      expect(_renderArcs(player), isEmpty);

      expect(player.performBasicAttack(), isFalse);
      expect(
        _renderArcs(player),
        isEmpty,
        reason: 'A queued press is not a hit',
      );
      player.update(.1);
      expect(player.comboStep, 2);
      final second = _renderArcs(player).single;
      expect(second.bounds.height, greaterThan(second.bounds.width));
      expect(second.paint.strokeWidth, greaterThan(first.paint.strokeWidth));

      player.update(.15);
      expect(_renderArcs(player), isEmpty);
      expect(player.performBasicAttack(), isFalse);
      expect(_renderArcs(player), isEmpty);
      player.update(.1);
      expect(player.comboStep, 3);
      final third = _renderArcs(player);
      expect(third, hasLength(4));
      expect(third.first.sweep, greaterThan(second.sweep));
      expect(
        third.first.paint.strokeWidth,
        greaterThan(second.paint.strokeWidth),
      );
      expect(third.first.paint.color.a, greaterThan(second.paint.color.a));
      for (final arc in third) {
        expect(arc.paint.color.a, lessThanOrEqualTo(.7));
        expect(arc.paint.style, PaintingStyle.stroke);
      }
      player.update(.15);
      final expanded = _renderArcs(player);
      expect(expanded, hasLength(4));
      expect(expanded.last.bounds.width, greaterThan(third.last.bounds.width));
      expect(expanded.last.bounds.width, lessThanOrEqualTo(74));
      player.update(.05);
      expect(player.isAttacking, isTrue);
      expect(_renderArcs(player), isEmpty);
    });
  }

  test('Combat reset clears the active impact cue', () {
    final player = PlayerComponent(position: Vector2.zero());
    expect(player.performBasicAttack(), isTrue);
    expect(_renderArcs(player), isNotEmpty);

    player.resetCombatState();

    expect(_renderArcs(player), isEmpty);
  });
}
