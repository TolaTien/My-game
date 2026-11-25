import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/game/components/hero_projectile.dart';
import 'package:my_game/game/components/hero_sprite_animator.dart';
import 'package:my_game/game/components/player.dart';
import 'package:my_game/game/components/pvp_bot_player.dart';
import 'package:my_game/game/components/player_skill_effect.dart';
import 'package:my_game/game/gold_rush_game.dart';
import 'package:my_game/models/player_profile.dart';
import 'package:my_game/models/pvp_match.dart';
import 'package:my_game/registry/asset_registry.dart';
import 'package:my_game/registry/sprite_image_cache.dart';
import 'package:my_game/services/audio_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ui.Image image;
  late SpriteFrame red, blue;
  late HeroSpriteSet sprites;
  setUpAll(() async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 8, 8),
      ui.Paint()..color = const ui.Color(0xFFFF0000),
    );
    canvas.drawRect(
      const ui.Rect.fromLTWH(8, 0, 8, 8),
      ui.Paint()..color = const ui.Color(0xFF0000FF),
    );
    final picture = recorder.endRecording();
    image = await picture.toImage(16, 8);
    picture.dispose();
    red = SpriteFrame(image: image, source: const ui.Rect.fromLTWH(0, 0, 8, 8));
    blue = SpriteFrame(
      image: image,
      source: const ui.Rect.fromLTWH(8, 0, 8, 8),
    );
    sprites = HeroSpriteSet(
      idle: SpriteClip([red], .2, loop: true),
      run: SpriteClip([red, blue], .1, loop: true),
      attack: SpriteClip([red, blue], .1, loop: false),
    );
  });
  tearDownAll(() => image.dispose());
  setUp(() => AudioService.setInstance(MockAudioService()));

  test(
    'Action frame progress uses elapsed seconds and returns to locomotion',
    () {
      final animation = HeroSpriteAnimator();
      expect(animation.frame(sprites), same(red));
      animation.playAction(.25);
      animation.update(.13, moving: false);
      expect(animation.frame(sprites), same(blue));
      animation.update(.13, moving: false);
      expect(animation.isPlayingAction, isFalse);
      expect(animation.frame(sprites), same(red));
    },
  );

  test('Run frames progress and speed easing is frame-rate independent', () {
    final oneStep = HeroSpriteAnimator()
      ..update(.1, moving: true, distanceTravelled: 40);
    final tenSteps = HeroSpriteAnimator();
    for (var i = 0; i < 10; i++) {
      tenSteps.update(.01, moving: true, distanceTravelled: 4);
    }
    expect(oneStep.frame(sprites), same(blue));
    expect(oneStep.movementWeight, closeTo(tenSteps.movementWeight, .0000001));
    expect(oneStep.movementWeight, inExclusiveRange(0, 1));
    oneStep.update(.1, moving: false);
    expect(oneStep.movementWeight, lessThan(tenSteps.movementWeight));
  });

  test(
    'Stride phase follows travelled distance rather than time or input alone',
    () {
      final fast = HeroSpriteAnimator()
        ..update(.1, moving: true, distanceTravelled: 40);
      final slow = HeroSpriteAnimator()
        ..update(.5, moving: true, distanceTravelled: 40);
      expect(fast.stridePhase, slow.stridePhase);
      expect(fast.frame(sprites), same(slow.frame(sprites)));
      final phase = fast.stridePhase;
      fast.update(.5, moving: true, distanceTravelled: 0);
      expect(fast.stridePhase, phase);
      expect(fast.frame(sprites), same(red));
    },
  );

  test('Teleports and skill dashes do not spin the run cycle', () {
    final animation = HeroSpriteAnimator()
      ..update(.1, moving: true, distanceTravelled: 16);
    final phase = animation.stridePhase;
    animation.update(.1, moving: true, distanceTravelled: 180);
    expect(animation.stridePhase, phase);
    expect(animation.frame(sprites), same(red));
  });

  test('Collision rollback produces no phantom walking steps', () {
    final player = PlayerComponent(position: Vector2.zero());
    player.moveDirection = Vector2(1, 0);
    player.update(.1);
    player.position.setZero();
    player.update(.1);
    expect(player.visualAnimator.gaitDistance, 0);
    player.update(.1);
    expect(player.visualAnimator.gaitDistance, greaterThan(0));
  });

  test('Reset clears visual transitions and handles a long frame without stuck pose', () {
    final animation = HeroSpriteAnimator()..playAction(.25);
    animation.update(10, moving: false);
    expect(animation.isPlayingAction, isFalse);
    animation.playAction(.55);
    animation.update(.2, moving: true);
    animation.reset();
    expect(animation.movementWeight, 0);
    expect(animation.frame(sprites), same(red));
  });

  test('Painter preserves frame crop and planted-foot anchor', () async {
    final recorder = ui.PictureRecorder();
    SpriteFramePainter().draw(
      ui.Canvas(recorder),
      blue,
      const ui.Offset(10, 10),
      height: 8,
    );
    final picture = recorder.endRecording();
    final output = await picture.toImage(20, 20);
    picture.dispose();
    final rgba = await output.toByteData(format: ui.ImageByteFormat.rawRgba);
    output.dispose();
    final pixels = rgba!.buffer.asUint8List();
    expect(pixels[(5 * 20 + 10) * 4 + 2], 255);
    expect(pixels[(5 * 20 + 10) * 4], 0);
    expect(pixels[(11 * 20 + 10) * 4 + 3], 0);
  });

  test('Rejected attacks do not restart accepted visual actions', () {
    final player = PlayerComponent(position: Vector2.zero());
    expect(player.performBasicAttack(), isTrue);
    player.update(.1);
    final elapsed = player.visualAnimator.actionElapsed;
    expect(elapsed, greaterThan(0));
    expect(player.performBasicAttack(), isFalse);
    expect(player.visualAnimator.actionElapsed, elapsed);
    player.resetCombatState();
    expect(player.visualAnimator.isPlayingAction, isFalse);
  });

  test('PvP round reset clears an in-flight cast pose at the new spawn', () {
    final target = PlayerComponent(position: Vector2.zero());
    final bot = PvpBotPlayerComponent(
      position: Vector2(200, 200),
      opponentInfo: PvpOpponentInfo.generateBot(100),
      targetPlayer: target,
      enableAi: false,
    );
    bot.executeSkill1();
    expect(bot.visualAnimator.isPlayingAction, isTrue);
    bot.update(.1);
    bot.resetRound(Vector2(10, 20));
    expect(bot.visualAnimator.isPlayingAction, isFalse);
    expect(bot.visualAnimator.locomotionTime, 0);
    expect(bot.attackTimer, 0);
    expect(bot.berserkTimer, 0);
    expect(bot.speechBubbleTimer, 0);
    expect(bot.position, Vector2(10, 20));
  });

  for (final hero in [
    'nova_blade',
    'shadow_01',
    'ember_02',
    'valeria',
    'garrick',
    'kaelen',
  ]) {
    testWidgets(
      '$hero production actor and three casts consume cached artwork',
      (tester) async {
        await tester.runAsync(() async {
          await GameAssetRegistry.instance.initialize();
          await SpriteImageCache.instance.preloadHero(hero);
        });
        final sprites = SpriteImageCache.instance.getHeroAnimations(hero)!;
        final game = GoldRushGame(
          playerProfile: PlayerProfile.defaultProfile().copyWith(
            selectedHeroId: hero,
          ),
        );
        await tester.pumpWidget(GameWidget(game: game));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        game.player.position = Vector2(400, 300);
        for (final enemy in game.enemies) {
          enemy.currentHp = 1000000;
        }
        game.player.performBasicAttack();
        game.player.update(.16);
        expect(
          game.player.visualAnimator.frame(sprites),
          same(sprites.attack.frameAt(.16, normalizedProgress: .16 / .25)),
        );
        for (var slot = 1; slot <= 3; slot++) {
          game.player.currentKi = 1000;
          switch (slot) {
            case 1:
              game.onSkill1();
              break;
            case 2:
              game.onSkill2();
              break;
            case 3:
              game.onSkill3();
              break;
          }
          await tester.pump();
          final clip = SpriteImageCache.instance.getSkillAnimation(hero, slot);
          expect(
            clip,
            isNotNull,
            reason: '$hero:$slot must use its preserved skill art',
          );
          expect(
            game.world.children.any(
              (child) =>
                  child is HeroProjectile && identical(child.animation, clip) ||
                  child is PlayerSkillProjectile &&
                      identical(child.animation, clip) ||
                  child is PlayerSkillArea && identical(child.animation, clip),
            ),
            isTrue,
          );
        }
        final recorder = ui.PictureRecorder();
        game.player.render(ui.Canvas(recorder));
        recorder.endRecording().dispose();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
