import 'dart:math' as math;
import 'dart:ui';

import '../../registry/sprite_image_cache.dart';

/// Presentation clocks never change attack lockouts, hitboxes or movement speed.
class HeroSpriteAnimator {
  double locomotionTime = 0;
  double actionElapsed = 0;
  double actionDuration = 0;
  double movementWeight = 0;
  static const double strideLength = 72;
  double gaitDistance = 0;
  double get stridePhase => (gaitDistance / strideLength) % 1;
  double _transitionElapsed = 1;
  bool _moving = false;
  SpriteMotion? _lastMotion;
  HeroSpriteSet? _lastSprites;
  SpriteFrame? _lastFrame;
  SpriteFrame? _transitionFrom;
  final SpriteFramePainter painter = SpriteFramePainter();

  bool get isPlayingAction => actionElapsed < actionDuration;
  double get actionProgress => actionDuration <= 0
      ? 1
      : (actionElapsed / actionDuration).clamp(0.0, 1.0);

  void playAction(double duration) {
    actionDuration = duration;
    actionElapsed = 0;
  }

  void update(double dt, {required bool moving, double distanceTravelled = 0}) {
    if (!dt.isFinite || dt <= 0) return;
    // Large corrections and skill dashes are not walking strides.
    final walked =
        distanceTravelled.isFinite &&
        distanceTravelled > .001 &&
        distanceTravelled <= 48;
    _moving = moving && walked;
    if (_moving) gaitDistance += distanceTravelled;
    locomotionTime += dt;
    actionElapsed = math.min(actionDuration, actionElapsed + dt);
    _transitionElapsed += dt;
    movementWeight +=
        ((_moving ? 1 : 0) - movementWeight) * (1 - math.exp(-14 * dt));
  }

  void reset() {
    actionElapsed = actionDuration = locomotionTime = movementWeight = 0;
    _lastMotion = null;
    _lastSprites = null;
    _lastFrame = _transitionFrom = null;
    _transitionElapsed = 1;
    _moving = false;
    gaitDistance = 0;
  }

  SpriteFrame frame(HeroSpriteSet sprites) {
    final motion = isPlayingAction
        ? SpriteMotion.attack
        : _moving
        ? SpriteMotion.run
        : SpriteMotion.idle;
    final clip = switch (motion) {
      SpriteMotion.idle => sprites.idle,
      SpriteMotion.run => sprites.run,
      SpriteMotion.attack => sprites.attack,
    };
    final result = motion == SpriteMotion.attack
        ? clip.frameAt(actionElapsed, normalizedProgress: actionProgress)
        : motion == SpriteMotion.run
        ? clip.frameAt(clip.duration * stridePhase)
        : clip.frameAt(locomotionTime);
    if (_lastMotion != null &&
        (_lastMotion != motion || !identical(_lastSprites, sprites))) {
      _transitionFrom = _lastFrame;
      _transitionElapsed = 0;
    }
    _lastMotion = motion;
    _lastSprites = sprites;
    _lastFrame = result;
    return result;
  }

  void render(Canvas canvas, HeroSpriteSet sprites, Offset foot) {
    final current = frame(sprites);
    final mix = (_transitionElapsed / .065).clamp(0.0, 1.0);
    if (_transitionFrom != null && mix < 1) {
      painter.draw(canvas, _transitionFrom!, foot, opacity: 1 - mix);
      painter.draw(canvas, current, foot, opacity: mix);
    } else {
      painter.draw(canvas, current, foot);
      _transitionFrom = null;
    }
  }
}

/// Shared pixel filtering and normalized anchors for actors and skill artwork.
class SpriteFramePainter {
  final Paint _paint = Paint()
    ..filterQuality = FilterQuality.none
    ..isAntiAlias = false;

  void draw(
    Canvas canvas,
    SpriteFrame frame,
    Offset anchor, {
    double? height,
    double opacity = 1,
  }) {
    if (opacity <= 0) return;
    final h = height ?? frame.worldHeight;
    final w = h * frame.source.width / frame.source.height;
    _paint.color = Color.fromARGB(
      (opacity.clamp(0.0, 1.0) * 255).round(),
      255,
      255,
      255,
    );
    canvas.drawImageRect(
      frame.image,
      frame.source,
      Rect.fromLTWH(
        anchor.dx - w * frame.anchor.dx,
        anchor.dy - h * frame.anchor.dy,
        w,
        h,
      ),
      _paint,
    );
  }
}
