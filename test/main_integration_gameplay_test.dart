import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/game/components/dungeon_map.dart';
import 'package:my_game/game/components/hero_projectile.dart';
import 'package:my_game/game/components/player.dart';
import 'package:my_game/game/gold_rush_game.dart';
import 'package:my_game/models/player_profile.dart';
import 'package:my_game/services/audio_service.dart';

import 'support/legacy_pve_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockAudioService audio;
  setUp(() {
    audio = MockAudioService();
    AudioService.setInstance(audio);
  });

  test('Directional main sprites and guarded Duy cone agree on facing', () {
    final player = PlayerComponent(position: Vector2.zero());
    player.faceDirection(Vector2(0, -1));
    player.performBasicAttack();
    expect(player.facingRow, 4);
    expect(player.canHitBasicAttack(Vector2(0, -40)), isTrue);
    expect(player.canHitBasicAttack(Vector2(40, 0)), isFalse);
    player.faceDirection(Vector2(-1, 1));
    expect(player.facingRow, 1);
    expect(player.isFacingRight, isFalse);
    expect(player.canHitBasicAttack(Vector2(-25, 25)), isTrue);
  });

  testWidgets(
    'Main ranged attack fires once only after Duy action acceptance',
    (tester) async {
      final game = GoldRushGame(
        selectedMapConfig: legacyTestMap,
        playerProfile: PlayerProfile.defaultProfile().copyWith(
          selectedHeroId: 'ranger',
        ),
      );
      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      game.player.position = Vector2(400, 300);
      final target = game.enemies.first;
      target.position = Vector2(460, 300);
      target.currentHp = 1000;
      audio.callHistory.clear();
      game.onBasicAttack();
      game.onBasicAttack();
      expect(target.currentHp, 1000);
      await tester.pump();
      final arrows = game.world.children.whereType<HeroProjectile>().toList();
      expect(arrows.length, 1);
      expect(
        audio.callHistory
            .where(
              (event) =>
                  event.method == 'playSfx' &&
                  event.target == SfxSound.attackArrow,
            )
            .length,
        1,
      );
      game.pauseEngine();
      arrows.single.update(.3);
      expect(target.currentHp, 1000 - game.player.effectiveDamage);
      arrows.single.update(.3);
      expect(target.currentHp, 1000 - game.player.effectiveDamage);
    },
  );

  for (final wall in [false, true]) {
    testWidgets(
      'Swept ranged projectile ${wall ? 'stops at wall' : 'hits target once'} with a long frame',
      (tester) async {
        final game = GoldRushGame(selectedMapConfig: legacyTestMap);
        await tester.pumpWidget(GameWidget(game: game));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        game.player.position = Vector2(400, 300);
        final target = game.enemies.first;
        target.position = Vector2(460, 300);
        target.currentHp = 1000;
        if (wall) {
          await game.dungeonMap.add(
            WallBlock(position: Vector2(420, 280), size: Vector2(16, 40)),
          );
        }
        var hits = 0;
        final arrow = HeroProjectile(
          position: Vector2(400, 300),
          direction: Vector2(1, 0),
          damage: 20,
          type: HeroProjectileType.arrow,
          isFromPlayer: true,
          onHit: (_, _) => hits++,
        );
        await game.world.add(arrow);
        await tester.pump();
        game.pauseEngine();
        arrow.update(1);
        arrow.update(1);
        expect(target.currentHp, wall ? 1000 : 980);
        expect(hits, wall ? 0 : 1);
      },
    );
  }
}
