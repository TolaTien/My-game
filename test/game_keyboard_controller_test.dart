import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/core/game_keyboard_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GameKeyboardController Tests', () {
    late GameKeyboardController controller;
    Vector2 lastDirection = Vector2.zero();
    int basicAttackCount = 0;
    int skill1Count = 0;
    int skill2Count = 0;
    int skill3Count = 0;

    setUp(() {
      lastDirection = Vector2.zero();
      basicAttackCount = 0;
      skill1Count = 0;
      skill2Count = 0;
      skill3Count = 0;

      controller = GameKeyboardController(
        onMoveDirectionChanged: (dir) => lastDirection = dir.clone(),
        onBasicAttack: () => basicAttackCount++,
        onSkill1: () => skill1Count++,
        onSkill2: () => skill2Count++,
        onSkill3: () => skill3Count++,
      );
      controller.attach();
    });

    tearDown(() {
      controller.detach();
    });

    test('W key moves UP (0, -1)', () async {
      await simulateKeyDownEvent(LogicalKeyboardKey.keyW);
      expect(lastDirection.x, closeTo(0, 0.001));
      expect(lastDirection.y, closeTo(-1, 0.001));

      await simulateKeyUpEvent(LogicalKeyboardKey.keyW);
      expect(lastDirection.x, closeTo(0, 0.001));
      expect(lastDirection.y, closeTo(0, 0.001));
    });

    test('S key moves DOWN (0, 1)', () async {
      await simulateKeyDownEvent(LogicalKeyboardKey.keyS);
      expect(lastDirection.x, closeTo(0, 0.001));
      expect(lastDirection.y, closeTo(1, 0.001));

      await simulateKeyUpEvent(LogicalKeyboardKey.keyS);
      expect(lastDirection.isZero(), isTrue);
    });

    test('A key moves LEFT (-1, 0)', () async {
      await simulateKeyDownEvent(LogicalKeyboardKey.keyA);
      expect(lastDirection.x, closeTo(-1, 0.001));
      expect(lastDirection.y, closeTo(0, 0.001));

      await simulateKeyUpEvent(LogicalKeyboardKey.keyA);
      expect(lastDirection.isZero(), isTrue);
    });

    test('D key moves RIGHT (1, 0)', () async {
      await simulateKeyDownEvent(LogicalKeyboardKey.keyD);
      expect(lastDirection.x, closeTo(1, 0.001));
      expect(lastDirection.y, closeTo(0, 0.001));

      await simulateKeyUpEvent(LogicalKeyboardKey.keyD);
      expect(lastDirection.isZero(), isTrue);
    });

    test('Arrow keys also control movement', () async {
      await simulateKeyDownEvent(LogicalKeyboardKey.arrowUp);
      expect(lastDirection.y, closeTo(-1, 0.001));
      await simulateKeyUpEvent(LogicalKeyboardKey.arrowUp);

      await simulateKeyDownEvent(LogicalKeyboardKey.arrowRight);
      expect(lastDirection.x, closeTo(1, 0.001));
      await simulateKeyUpEvent(LogicalKeyboardKey.arrowRight);
    });

    test('Diagonal movement (W + D) normalizes to unit length 1.0', () async {
      await simulateKeyDownEvent(LogicalKeyboardKey.keyW);
      await simulateKeyDownEvent(LogicalKeyboardKey.keyD);

      expect(lastDirection.length, closeTo(1.0, 0.001));
      expect(lastDirection.x, closeTo(0.7071, 0.01));
      expect(lastDirection.y, closeTo(-0.7071, 0.01));

      // Releasing W leaves only D
      await simulateKeyUpEvent(LogicalKeyboardKey.keyW);
      expect(lastDirection.x, closeTo(1, 0.001));
      expect(lastDirection.y, closeTo(0, 0.001));

      await simulateKeyUpEvent(LogicalKeyboardKey.keyD);
      expect(lastDirection.isZero(), isTrue);
    });

    test('Skill 1 triggered by Key 1 and Numpad 1', () async {
      await simulateKeyDownEvent(LogicalKeyboardKey.digit1);
      expect(skill1Count, equals(1));

      await simulateKeyUpEvent(LogicalKeyboardKey.digit1);
      expect(skill1Count, equals(1));

      await simulateKeyDownEvent(LogicalKeyboardKey.numpad1);
      expect(skill1Count, equals(2));
      await simulateKeyUpEvent(LogicalKeyboardKey.numpad1);
    });

    test('Skill 2 triggered by Key 2 and Numpad 2', () async {
      await simulateKeyDownEvent(LogicalKeyboardKey.digit2);
      expect(skill2Count, equals(1));
      await simulateKeyUpEvent(LogicalKeyboardKey.digit2);

      await simulateKeyDownEvent(LogicalKeyboardKey.numpad2);
      expect(skill2Count, equals(2));
      await simulateKeyUpEvent(LogicalKeyboardKey.numpad2);
    });

    test('Skill 3 triggered by Key 3 and Numpad 3', () async {
      await simulateKeyDownEvent(LogicalKeyboardKey.digit3);
      expect(skill3Count, equals(1));
      await simulateKeyUpEvent(LogicalKeyboardKey.digit3);

      await simulateKeyDownEvent(LogicalKeyboardKey.numpad3);
      expect(skill3Count, equals(2));
      await simulateKeyUpEvent(LogicalKeyboardKey.numpad3);
    });

    test('Basic Attack triggered by Space and J', () async {
      await simulateKeyDownEvent(LogicalKeyboardKey.space);
      expect(basicAttackCount, equals(1));
      await simulateKeyUpEvent(LogicalKeyboardKey.space);

      await simulateKeyDownEvent(LogicalKeyboardKey.keyJ);
      expect(basicAttackCount, equals(2));
      await simulateKeyUpEvent(LogicalKeyboardKey.keyJ);
    });

    test('resetMovement zeroes out movement immediately', () async {
      await simulateKeyDownEvent(LogicalKeyboardKey.keyW);
      expect(controller.hasKeyboardMovement, isTrue);

      controller.resetMovement();
      expect(controller.hasKeyboardMovement, isFalse);
      expect(lastDirection.isZero(), isTrue);
    });
  });

  group('GamePlatformHelper Tests', () {
    test('Platform detection returns consistent boolean values', () {
      expect(GamePlatformHelper.isMobile, isA<bool>());
      expect(GamePlatformHelper.isDesktopOrWeb, equals(!GamePlatformHelper.isMobile));
    });
  });
}
