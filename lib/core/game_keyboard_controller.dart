import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Helper kiểm tra nền tảng thiết bị
class GamePlatformHelper {
  /// Trả về true nếu đang chạy trên điện thoại thuần (Android / iOS không phải Web)
  static bool get isMobile {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  /// Trả về true nếu đang chạy trên Web (Chrome, Edge...) hoặc Desktop (Windows, macOS, Linux)
  static bool get isDesktopOrWeb => !isMobile;
}

/// Bộ điều khiển bàn phím máy tính (WASD di chuyển, 1 2 3 skill, Space/J tấn công)
class GameKeyboardController {
  final Set<LogicalKeyboardKey> _pressedKeys = {};
  Vector2 _currentDirection = Vector2.zero();

  final Function(Vector2 direction) onMoveDirectionChanged;
  final VoidCallback onBasicAttack;
  final VoidCallback onSkill1;
  final VoidCallback onSkill2;
  final VoidCallback onSkill3;
  final VoidCallback? onCompanionSkill;

  GameKeyboardController({
    required this.onMoveDirectionChanged,
    required this.onBasicAttack,
    required this.onSkill1,
    required this.onSkill2,
    required this.onSkill3,
    this.onCompanionSkill,
  });

  Vector2 get currentDirection => _currentDirection;
  bool get hasKeyboardMovement => !_currentDirection.isZero();

  /// Đăng ký lắng nghe sự kiện phần cứng
  void attach() {
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  /// Hủy đăng ký lắng nghe
  void detach() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _pressedKeys.clear();
    _currentDirection = Vector2.zero();
    onMoveDirectionChanged(Vector2.zero());
  }

  /// Reset trạng thái di chuyển (ví dụ khi mất focus / chuyển tab)
  void resetMovement() {
    _pressedKeys.clear();
    _currentDirection = Vector2.zero();
    onMoveDirectionChanged(Vector2.zero());
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      _pressedKeys.add(event.logicalKey);

      // Kích hoạt Skill 1 (Phím 1 hoặc Numpad 1)
      if (event.logicalKey == LogicalKeyboardKey.digit1 ||
          event.logicalKey == LogicalKeyboardKey.numpad1) {
        onSkill1();
        return true;
      }

      // Kích hoạt Skill 2 (Phím 2 hoặc Numpad 2)
      if (event.logicalKey == LogicalKeyboardKey.digit2 ||
          event.logicalKey == LogicalKeyboardKey.numpad2) {
        onSkill2();
        return true;
      }

      // Kích hoạt Skill 3 (Phím 3 hoặc Numpad 3)
      if (event.logicalKey == LogicalKeyboardKey.digit3 ||
          event.logicalKey == LogicalKeyboardKey.numpad3) {
        onSkill3();
        return true;
      }

      // Kích hoạt Kỹ năng Trợ thủ (Phím E hoặc Phím 4)
      if (event.logicalKey == LogicalKeyboardKey.keyE ||
          event.logicalKey == LogicalKeyboardKey.digit4 ||
          event.logicalKey == LogicalKeyboardKey.numpad4) {
        onCompanionSkill?.call();
        return true;
      }

      // Kích hoạt Đánh thường (Phím Space hoặc J)
      if (event.logicalKey == LogicalKeyboardKey.space ||
          event.logicalKey == LogicalKeyboardKey.keyJ) {
        onBasicAttack();
        return true;
      }

      _updateMovement();
      return _isMovementKey(event.logicalKey);
    } else if (event is KeyUpEvent) {
      _pressedKeys.remove(event.logicalKey);
      _updateMovement();
      return _isMovementKey(event.logicalKey);
    }

    return false;
  }

  bool _isMovementKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.keyW ||
        key == LogicalKeyboardKey.keyS ||
        key == LogicalKeyboardKey.keyA ||
        key == LogicalKeyboardKey.keyD ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight;
  }

  void _updateMovement() {
    double dx = 0;
    double dy = 0;

    // Tiến lên: W hoặc ArrowUp
    if (_pressedKeys.contains(LogicalKeyboardKey.keyW) ||
        _pressedKeys.contains(LogicalKeyboardKey.arrowUp)) {
      dy -= 1;
    }
    // Lùi xuống: S hoặc ArrowDown
    if (_pressedKeys.contains(LogicalKeyboardKey.keyS) ||
        _pressedKeys.contains(LogicalKeyboardKey.arrowDown)) {
      dy += 1;
    }
    // Sang trái: A hoặc ArrowLeft
    if (_pressedKeys.contains(LogicalKeyboardKey.keyA) ||
        _pressedKeys.contains(LogicalKeyboardKey.arrowLeft)) {
      dx -= 1;
    }
    // Sang phải: D hoặc ArrowRight
    if (_pressedKeys.contains(LogicalKeyboardKey.keyD) ||
        _pressedKeys.contains(LogicalKeyboardKey.arrowRight)) {
      dx += 1;
    }

    final dir = Vector2(dx, dy);
    if (!dir.isZero()) {
      dir.normalize();
    }
    _currentDirection = dir;
    onMoveDirectionChanged(dir);
  }
}
