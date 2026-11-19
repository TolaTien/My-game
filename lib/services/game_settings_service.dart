import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Quản lý toàn bộ cấu hình trò chơi (Đồ họa, Hiệu năng, Chiến đấu, Điều khiển)
class GameSettingsService {
  GameSettingsService._();
  static final GameSettingsService instance = GameSettingsService._();

  static const String _keyTargetFps = 'setting_target_fps';
  static const String _keyGraphicsQuality = 'setting_graphics_quality';
  static const String _keyDamageNumbers = 'setting_damage_numbers';
  static const String _keySkillRange = 'setting_skill_range';
  static const String _keyAutoAim = 'setting_auto_aim';
  static const String _keyHapticFeedback = 'setting_haptic_feedback';
  static const String _keyScreenShake = 'setting_screen_shake';

  final ValueNotifier<int> targetFpsNotifier = ValueNotifier<int>(60);
  final ValueNotifier<String> graphicsQualityNotifier = ValueNotifier<String>('high');
  final ValueNotifier<bool> showDamageNumbersNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<bool> showSkillRangeNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<bool> autoAimNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<bool> hapticFeedbackNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<bool> screenShakeNotifier = ValueNotifier<bool>(true);

  int get targetFps => targetFpsNotifier.value;
  String get graphicsQuality => graphicsQualityNotifier.value;
  bool get showDamageNumbers => showDamageNumbersNotifier.value;
  bool get showSkillRange => showSkillRangeNotifier.value;
  bool get autoAim => autoAimNotifier.value;
  bool get hapticFeedback => hapticFeedbackNotifier.value;
  bool get screenShake => screenShakeNotifier.value;

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final fps = prefs.getInt(_keyTargetFps);
      if (fps != null) targetFpsNotifier.value = fps;

      final gfx = prefs.getString(_keyGraphicsQuality);
      if (gfx != null) graphicsQualityNotifier.value = gfx;

      final dmg = prefs.getBool(_keyDamageNumbers);
      if (dmg != null) showDamageNumbersNotifier.value = dmg;

      final range = prefs.getBool(_keySkillRange);
      if (range != null) showSkillRangeNotifier.value = range;

      final aim = prefs.getBool(_keyAutoAim);
      if (aim != null) autoAimNotifier.value = aim;

      final haptic = prefs.getBool(_keyHapticFeedback);
      if (haptic != null) hapticFeedbackNotifier.value = haptic;

      final shake = prefs.getBool(_keyScreenShake);
      if (shake != null) screenShakeNotifier.value = shake;
    } catch (e) {
      debugPrint('GameSettingsService initialize warning: $e');
    }
  }

  Future<void> setTargetFps(int fps) async {
    targetFpsNotifier.value = fps;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyTargetFps, fps);
  }

  Future<void> setGraphicsQuality(String quality) async {
    graphicsQualityNotifier.value = quality;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyGraphicsQuality, quality);
  }

  Future<void> setShowDamageNumbers(bool value) async {
    showDamageNumbersNotifier.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDamageNumbers, value);
  }

  Future<void> setShowSkillRange(bool value) async {
    showSkillRangeNotifier.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySkillRange, value);
  }

  Future<void> setAutoAim(bool value) async {
    autoAimNotifier.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoAim, value);
  }

  Future<void> setHapticFeedback(bool value) async {
    hapticFeedbackNotifier.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHapticFeedback, value);
  }

  Future<void> setScreenShake(bool value) async {
    screenShakeNotifier.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyScreenShake, value);
  }

  Future<void> resetToDefaults() async {
    targetFpsNotifier.value = 60;
    graphicsQualityNotifier.value = 'high';
    showDamageNumbersNotifier.value = true;
    showSkillRangeNotifier.value = true;
    autoAimNotifier.value = true;
    hapticFeedbackNotifier.value = true;
    screenShakeNotifier.value = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyTargetFps);
      await prefs.remove(_keyGraphicsQuality);
      await prefs.remove(_keyDamageNumbers);
      await prefs.remove(_keySkillRange);
      await prefs.remove(_keyAutoAim);
      await prefs.remove(_keyHapticFeedback);
      await prefs.remove(_keyScreenShake);
    } catch (_) {}
  }
}
