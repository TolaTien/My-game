import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bộ nhớ đệm (Cache) nạp trực tiếp `ui.Image` đã tách nền bảo toàn viền đen từ `assets/images/`
/// để render đồng nhất 100% giữa Cửa Hàng (Shop), Sảnh Chờ (Lobby) và Trong Trận (Flame Canvas),
/// bao gồm cả Frame Đứng/Chạy, Frame Tấn Công và Hiệu Ứng Kỹ Năng (Skill 1-2-3).
class SpriteImageCache {
  SpriteImageCache._();
  static final SpriteImageCache instance = SpriteImageCache._();

  final Map<String, ui.Image> _heroImages = {};
  final Map<String, ui.Image> _heroAttackImages = {};
  final Map<String, ui.Image> _companionImages = {};
  final Map<String, ui.Image> _skillImages = {};
  final Set<String> _loadingKeys = {};

  static const Map<String, String> heroPortraitPaths = {
    'nova_blade': 'assets/images/heroes/nova_blade/nova_blade_portrait.png',
    'shadow_01': 'assets/images/heroes/shadow/shadow_01_portrait.png',
    'ember_02': 'assets/images/heroes/ember/ember_02_portrait.png',
    'valeria': 'assets/images/heroes/valenria/valeria_portrait.png',
    'garrick': 'assets/images/heroes/garrick/garrick_portrait.png',
    'kaelen': 'assets/images/heroes/kaelen/kaelen_portrait.png',
  };

  static const Map<String, String> heroAttackPaths = {
    'nova_blade': 'assets/images/heroes/nova_blade/nova_blade_attack.png',
    'valeria': 'assets/images/heroes/valenria/valeria_attack.png',
    'garrick': 'assets/images/heroes/garrick/garrick_attack.png',
    'kaelen': 'assets/images/heroes/kaelen/kaelen_attack.png',
  };

  static const Map<String, String> companionSpritePaths = {
    'aegis_x9': 'assets/images/companions/aegis_x9.png',
    'cyber_drone': 'assets/images/companions/cyber_drone.png',
    'pyro_frost_dragon': 'assets/images/companions/pyro_frost_dragon.png',
    'gem_tumbler': 'assets/images/companions/gem_tumbler.png',
    'luna_fox': 'assets/images/companions/luna_fox.png',
    'orbit_03': 'assets/images/companions/orbit_03.png',
  };

  static const Map<String, String> skillEffectPaths = {
    'nova_blade_1': 'assets/images/skills/nova_energy_slash.png',
    'nova_blade_2': 'assets/images/skills/nova_shadow_dash.png',
    'nova_blade_3': 'assets/images/skills/nova_quantum_burst.png',
    'valeria_1': 'assets/images/skills/valeria_skills.png',
    'valeria_2': 'assets/images/skills/valeria_skills.png',
    'valeria_3': 'assets/images/skills/valeria_skills.png',
    'kaelen_1': 'assets/images/skills/kaelen_thunder_flash.png',
    'kaelen_2': 'assets/images/skills/kaelen_storm_vortex.png',
    'kaelen_3': 'assets/images/skills/kaelen_heaven_judgment.png',
  };

  ui.Image? getHeroImage(String heroId) {
    final cached = _heroImages[heroId];
    if (cached != null) return cached;
    final path = heroPortraitPaths[heroId];
    if (path != null && !_loadingKeys.contains('hero_$heroId')) {
      _loadingKeys.add('hero_$heroId');
      unawaited(_loadIntoCache(path, (img) => _heroImages[heroId] = img));
    }
    return null;
  }

  ui.Image? getHeroAttackImage(String heroId) {
    final cached = _heroAttackImages[heroId];
    if (cached != null) return cached;
    final path = heroAttackPaths[heroId];
    if (path != null && !_loadingKeys.contains('atk_$heroId')) {
      _loadingKeys.add('atk_$heroId');
      unawaited(_loadIntoCache(path, (img) => _heroAttackImages[heroId] = img));
    }
    return _heroImages[heroId];
  }

  ui.Image? getCompanionImage(String companionId) {
    final cached = _companionImages[companionId];
    if (cached != null) return cached;
    final path = companionSpritePaths[companionId];
    if (path != null && !_loadingKeys.contains('comp_$companionId')) {
      _loadingKeys.add('comp_$companionId');
      unawaited(
        _loadIntoCache(path, (img) => _companionImages[companionId] = img),
      );
    }
    return null;
  }

  ui.Image? getSkillEffectImage(String heroId, int skillSlot) {
    final key = '${heroId}_$skillSlot';
    final cached = _skillImages[key];
    if (cached != null) return cached;
    final path = skillEffectPaths[key];
    if (path != null && !_loadingKeys.contains('skill_$key')) {
      _loadingKeys.add('skill_$key');
      unawaited(_loadIntoCache(path, (img) => _skillImages[key] = img));
    }
    return null;
  }

  Future<void> preloadAll() async {
    final futures = <Future<void>>[];
    heroPortraitPaths.forEach((id, path) {
      if (!_heroImages.containsKey(id)) {
        _loadingKeys.add('hero_$id');
        futures.add(_loadIntoCache(path, (img) => _heroImages[id] = img));
      }
    });
    heroAttackPaths.forEach((id, path) {
      if (!_heroAttackImages.containsKey(id)) {
        _loadingKeys.add('atk_$id');
        futures.add(_loadIntoCache(path, (img) => _heroAttackImages[id] = img));
      }
    });
    companionSpritePaths.forEach((id, path) {
      if (!_companionImages.containsKey(id)) {
        _loadingKeys.add('comp_$id');
        futures.add(_loadIntoCache(path, (img) => _companionImages[id] = img));
      }
    });
    skillEffectPaths.forEach((key, path) {
      if (!_skillImages.containsKey(key)) {
        _loadingKeys.add('skill_$key');
        futures.add(_loadIntoCache(path, (img) => _skillImages[key] = img));
      }
    });
    await Future.wait(futures);
  }

  Future<void> _loadIntoCache(
    String assetPath,
    void Function(ui.Image) onLoaded,
  ) async {
    try {
      final data = await rootBundle.load(assetPath);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      try {
        final frame = await codec.getNextFrame();
        onLoaded(frame.image);
      } finally {
        codec.dispose();
      }
    } catch (error) {
      debugPrint('SpriteImageCache: failed to load $assetPath: $error');
    }
  }
}
