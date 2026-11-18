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
  final Map<String, ui.Image> _heroIdleImages = {};
  final Map<String, ui.Image> _heroRunImages = {};
  final Map<String, ui.Image> _heroSkillSheetImages = {};
  final Map<String, List<ui.Image>> _frameSequences = {};
  final Map<String, ui.Image> _companionImages = {};
  final Map<String, ui.Image> _skillImages = {};
  final Map<String, ui.Image> _mapImages = {};
  final Set<String> _loadingKeys = {};

  static const List<String> _shadowIdleFrames = [
    'assets/images/heroes/shadow/idle/01.png',
    'assets/images/heroes/shadow/idle/02.png',
    'assets/images/heroes/shadow/idle/03.png',
    'assets/images/heroes/shadow/idle/04.png',
    'assets/images/heroes/shadow/idle/05.png',
    'assets/images/heroes/shadow/idle/06.png',
    'assets/images/heroes/shadow/idle/07.png',
    'assets/images/heroes/shadow/idle/08.png',
    'assets/images/heroes/shadow/idle/09.png',
    'assets/images/heroes/shadow/idle/10.png',
    'assets/images/heroes/shadow/idle/11.png',
    'assets/images/heroes/shadow/idle/12.png',
    'assets/images/heroes/shadow/idle/13.png',
    'assets/images/heroes/shadow/idle/14.png',
    'assets/images/heroes/shadow/idle/15.png',
    'assets/images/heroes/shadow/idle/16.png',
  ];

  static const List<String> _shadowRunFrames = [
    'assets/images/heroes/shadow/run/01.png',
    'assets/images/heroes/shadow/run/02.png',
    'assets/images/heroes/shadow/run/03.png',
    'assets/images/heroes/shadow/run/04.png',
    'assets/images/heroes/shadow/run/05.png',
    'assets/images/heroes/shadow/run/06.png',
    'assets/images/heroes/shadow/run/07.png',
    'assets/images/heroes/shadow/run/08.png',
    'assets/images/heroes/shadow/run/09.png',
    'assets/images/heroes/shadow/run/10.png',
    'assets/images/heroes/shadow/run/11.png',
    'assets/images/heroes/shadow/run/12.png',
    'assets/images/heroes/shadow/run/13.png',
    'assets/images/heroes/shadow/run/14.png',
    'assets/images/heroes/shadow/run/15.png',
    'assets/images/heroes/shadow/run/16.png',
  ];

  static const List<String> _shadowAttackFrames = [
    'assets/images/heroes/shadow/attack/01.png',
    'assets/images/heroes/shadow/attack/02.png',
    'assets/images/heroes/shadow/attack/03.png',
    'assets/images/heroes/shadow/attack/04.png',
    'assets/images/heroes/shadow/attack/05.png',
    'assets/images/heroes/shadow/attack/06.png',
    'assets/images/heroes/shadow/attack/07.png',
    'assets/images/heroes/shadow/attack/08.png',
    'assets/images/heroes/shadow/attack/09.png',
    'assets/images/heroes/shadow/attack/10.png',
    'assets/images/heroes/shadow/attack/11.png',
    'assets/images/heroes/shadow/attack/12.png',
    'assets/images/heroes/shadow/attack/13.png',
    'assets/images/heroes/shadow/attack/14.png',
    'assets/images/heroes/shadow/attack/15.png',
    'assets/images/heroes/shadow/attack/16.png',
  ];

  static const List<String> _kaleRunFrames = [
    'assets/images/heroes/kale/run/01.png',
    'assets/images/heroes/kale/run/02.png',
    'assets/images/heroes/kale/run/03.png',
    'assets/images/heroes/kale/run/04.png',
    'assets/images/heroes/kale/run/05.png',
    'assets/images/heroes/kale/run/06.png',
    'assets/images/heroes/kale/run/07.png',
    'assets/images/heroes/kale/run/08.png',
    'assets/images/heroes/kale/run/09.png',
    'assets/images/heroes/kale/run/10.png',
    'assets/images/heroes/kale/run/11.png',
    'assets/images/heroes/kale/run/12.png',
    'assets/images/heroes/kale/run/13.png',
    'assets/images/heroes/kale/run/14.png',
    'assets/images/heroes/kale/run/15.png',
    'assets/images/heroes/kale/run/16.png',
  ];

  static const List<String> _kaleIdleFrames = [
    'assets/images/heroes/kale/idle/01.png',
    'assets/images/heroes/kale/idle/02.png',
    'assets/images/heroes/kale/idle/03.png',
    'assets/images/heroes/kale/idle/04.png',
    'assets/images/heroes/kale/idle/05.png',
    'assets/images/heroes/kale/idle/06.png',
    'assets/images/heroes/kale/idle/07.png',
    'assets/images/heroes/kale/idle/08.png',
    'assets/images/heroes/kale/idle/09.png',
    'assets/images/heroes/kale/idle/10.png',
    'assets/images/heroes/kale/idle/11.png',
    'assets/images/heroes/kale/idle/12.png',
    'assets/images/heroes/kale/idle/13.png',
    'assets/images/heroes/kale/idle/14.png',
    'assets/images/heroes/kale/idle/15.png',
    'assets/images/heroes/kale/idle/16.png',
  ];

  static const Map<String, List<String>> heroSequencePaths = {
    'shadow_01_idle': _shadowIdleFrames,
    'shadow_idle': _shadowIdleFrames,
    'shadow_01_run': _shadowRunFrames,
    'shadow_run': _shadowRunFrames,
    'shadow_01_attack': _shadowAttackFrames,
    'shadow_attack': _shadowAttackFrames,
    'kaelen_idle': _kaleIdleFrames,
    'kale_idle': _kaleIdleFrames,
    'kaelen_run': _kaleRunFrames,
    'kale_run': _kaleRunFrames,
  };

  static const Map<String, String> heroPortraitPaths = {
    'nova_blade': 'assets/images/heroes/nova/nova_portrait.png',
    'nova': 'assets/images/heroes/nova/nova_portrait.png',
    'shadow_01': 'assets/images/heroes/shadow_01_portrait.png',
    'shadow': 'assets/images/heroes/shadow_01_portrait.png',
    'ember_02': 'assets/images/heroes/ember/ember.png',
    'ember': 'assets/images/heroes/ember/ember.png',
    'kaelen': 'assets/images/heroes/kale/kaelen_portrait.png',
    'kale': 'assets/images/heroes/kale/kaelen_portrait.png',
  };

  static const Map<String, String> heroIdlePaths = {
    'nova_blade': 'assets/images/heroes/nova/nova.png',
    'nova': 'assets/images/heroes/nova/nova.png',
    'ember_02': 'assets/images/heroes/ember/Ember-idle.png',
    'ember': 'assets/images/heroes/ember/Ember-idle.png',
    'kaelen': 'assets/images/heroes/kale/idle/01.png',
    'kale': 'assets/images/heroes/kale/idle/01.png',
    'shadow_01': 'assets/images/heroes/shadow/idle/01.png',
    'shadow': 'assets/images/heroes/shadow/idle/01.png',
  };
  static const Map<String, String> heroRunPaths = {
    'nova_blade': 'assets/images/heroes/nova/nova-run.png',
    'nova': 'assets/images/heroes/nova/nova-run.png',
    'ember_02': 'assets/images/heroes/ember/ember-run.png',
    'ember': 'assets/images/heroes/ember/ember-run.png',
    'kaelen': 'assets/images/heroes/kale/run/01.png',
    'kale': 'assets/images/heroes/kale/run/01.png',
    'shadow_01': 'assets/images/heroes/shadow/run/01.png',
    'shadow': 'assets/images/heroes/shadow/run/01.png',
  };

  static const Map<String, String> heroAttackPaths = {
    'nova_blade': 'assets/images/heroes/nova/nova-attack.png',
    'nova': 'assets/images/heroes/nova/nova-attack.png',
    'ember_02': 'assets/images/heroes/ember/Ember-attack.png',
    'ember': 'assets/images/heroes/ember/Ember-attack.png',
    'kaelen': 'assets/images/heroes/kale/kale-attack.png',
    'kale': 'assets/images/heroes/kale/kale-attack.png',
    'shadow_01': 'assets/images/heroes/shadow/attack/01.png',
    'shadow': 'assets/images/heroes/shadow/attack/01.png',
  };

  static const Map<String, String> heroSkillSheetPaths = {};

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
    'valeria_1': 'assets/images/skills/valeria_skill1.png',
    'valeria_2': 'assets/images/skills/valeria_skill2.png',
    'valeria_3': 'assets/images/skills/valeria_skill3.png',
    'kaelen_1': 'assets/images/skills/kaelen_thunder_flash.png',
    'kaelen_2': 'assets/images/skills/kaelen_storm_vortex.png',
    'kaelen_3': 'assets/images/skills/kaelen_heaven_judgment.png',
  };

  static const Map<String, String> mapImagePaths = {
    'map_bang': 'assets/images/maps/map-bang.png',
    'map_dao_bang_gia': 'assets/images/maps/map-dao-bang-gia.png',
  };

  String? _getAliasId(String heroId) {
    switch (heroId) {
      case 'ember':
        return 'ember_02';
      case 'ember_02':
        return 'ember';
      case 'nova':
        return 'nova_blade';
      case 'nova_blade':
        return 'nova';
      case 'shadow':
        return 'shadow_01';
      case 'shadow_01':
        return 'shadow';
      case 'kale':
        return 'kaelen';
      case 'kaelen':
        return 'kale';
      default:
        return null;
    }
  }

  ui.Image? getHeroImage(String heroId) {
    final alias = _getAliasId(heroId);
    final cached = _heroImages[heroId] ?? (alias != null ? _heroImages[alias] : null);
    if (cached != null) return cached;
    final path = heroPortraitPaths[heroId] ?? (alias != null ? heroPortraitPaths[alias] : null);
    if (path != null && !_loadingKeys.contains('hero_$heroId')) {
      _loadingKeys.add('hero_$heroId');
      unawaited(_loadIntoCache(path, (img) {
        _heroImages[heroId] = img;
        if (alias != null) _heroImages[alias] = img;
      }));
    }
    return null;
  }

  ui.Image? getHeroIdleImage(String heroId) {
    final alias = _getAliasId(heroId);
    final cached = _heroIdleImages[heroId] ?? (alias != null ? _heroIdleImages[alias] : null);
    if (cached != null) return cached;
    final path = heroIdlePaths[heroId] ?? (alias != null ? heroIdlePaths[alias] : null);
    if (path != null && !_loadingKeys.contains('idle_$heroId')) {
      _loadingKeys.add('idle_$heroId');
      unawaited(_loadIntoCache(path, (img) {
        _heroIdleImages[heroId] = img;
        if (alias != null) _heroIdleImages[alias] = img;
      }));
    }
    return getHeroImage(heroId);
  }

  ui.Image? getHeroRunImage(String heroId) {
    final alias = _getAliasId(heroId);
    final cached = _heroRunImages[heroId] ?? (alias != null ? _heroRunImages[alias] : null);
    if (cached != null) return cached;
    final path = heroRunPaths[heroId] ?? (alias != null ? heroRunPaths[alias] : null);
    if (path != null && !_loadingKeys.contains('run_$heroId')) {
      _loadingKeys.add('run_$heroId');
      unawaited(_loadIntoCache(path, (img) {
        _heroRunImages[heroId] = img;
        if (alias != null) _heroRunImages[alias] = img;
      }));
    }
    return getHeroImage(heroId);
  }

  ui.Image? getHeroAttackImage(String heroId) {
    final alias = _getAliasId(heroId);
    final cached = _heroAttackImages[heroId] ?? (alias != null ? _heroAttackImages[alias] : null);
    if (cached != null) return cached;
    final path = heroAttackPaths[heroId] ?? (alias != null ? heroAttackPaths[alias] : null);
    if (path != null && !_loadingKeys.contains('atk_$heroId')) {
      _loadingKeys.add('atk_$heroId');
      unawaited(_loadIntoCache(path, (img) {
        _heroAttackImages[heroId] = img;
        if (alias != null) _heroAttackImages[alias] = img;
      }));
    }
    return getHeroImage(heroId);
  }

  ui.Image? getHeroSkillSheetImage(String heroId, int skillSlot) {
    final key = '${heroId}_$skillSlot';
    final cached = _heroSkillSheetImages[key];
    if (cached != null) return cached;
    final path = heroSkillSheetPaths[key];
    if (path != null && !_loadingKeys.contains('skillsheet_$key')) {
      _loadingKeys.add('skillsheet_$key');
      unawaited(
        _loadIntoCache(path, (img) => _heroSkillSheetImages[key] = img),
      );
    }
    return null;
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

  ui.Image? getMapImage(String mapId) {
    final cached = _mapImages[mapId];
    if (cached != null) return cached;
    final path = mapImagePaths[mapId];
    if (path != null) {
      final cachedByPath = _mapImages[path];
      if (cachedByPath != null) return cachedByPath;
      if (!_loadingKeys.contains('map_$mapId')) {
        _loadingKeys.add('map_$mapId');
        unawaited(_loadIntoCache(path, (img) {
          _mapImages[mapId] = img;
          _mapImages[path] = img;
        }));
      }
    }
    return null;
  }

  Future<ui.Image?> loadMapImageByPath(String path, {String? mapId}) async {
    final cached = _mapImages[path] ?? (mapId != null ? _mapImages[mapId] : null);
    if (cached != null) return cached;

    try {
      final data = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      _mapImages[path] = frame.image;
      if (mapId != null) _mapImages[mapId] = frame.image;
      return frame.image;
    } catch (e) {
      debugPrint('SpriteImageCache: Không thể nạp $path ($e), dùng fallback');
      try {
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.drawColor(const ui.Color(0xFF1E3A5F), ui.BlendMode.src);
        final picture = recorder.endRecording();
        final fallback = await picture.toImage(64, 64);
        _mapImages[path] = fallback;
        if (mapId != null) _mapImages[mapId] = fallback;
        return fallback;
      } catch (_) {
        return null;
      }
    }
  }

  void setMapImage(String mapId, ui.Image img) {
    _mapImages[mapId] = img;
    final path = mapImagePaths[mapId];
    if (path != null) _mapImages[path] = img;
  }

  bool hasSequence(String heroId, String action) {
    return heroSequencePaths.containsKey('${heroId}_$action');
  }

  ui.Image? getHeroSequenceFrame(String heroId, String action, int frameIndex) {
    final key = '${heroId}_$action';
    final seq = _frameSequences[key];
    if (seq != null && seq.isNotEmpty) {
      return seq[frameIndex % seq.length];
    }
    final paths = heroSequencePaths[key];
    if (paths != null && !_loadingKeys.contains('seq_$key')) {
      _loadingKeys.add('seq_$key');
      unawaited(_loadSequenceIntoCache(key, paths));
    }
    return getHeroImage(heroId);
  }

  Future<void> _loadSequenceIntoCache(String key, List<String> paths) async {
    final images = <ui.Image>[];
    for (final p in paths) {
      try {
        final data = await rootBundle.load(p);
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        final frame = await codec.getNextFrame();
        images.add(frame.image);
      } catch (_) {}
    }
    if (images.isNotEmpty) {
      _frameSequences[key] = images;
    }
  }

  Future<void> preloadAll() async {
    final futures = <Future<void>>[];
    heroSequencePaths.forEach((key, paths) {
      if (!_frameSequences.containsKey(key)) {
        _loadingKeys.add('seq_$key');
        futures.add(_loadSequenceIntoCache(key, paths));
      }
    });
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
    heroIdlePaths.forEach((id, path) {
      if (!_heroIdleImages.containsKey(id)) {
        _loadingKeys.add('idle_$id');
        futures.add(_loadIntoCache(path, (img) => _heroIdleImages[id] = img));
      }
    });
    heroRunPaths.forEach((id, path) {
      if (!_heroRunImages.containsKey(id)) {
        _loadingKeys.add('run_$id');
        futures.add(_loadIntoCache(path, (img) => _heroRunImages[id] = img));
      }
    });
    heroSkillSheetPaths.forEach((key, path) {
      if (!_heroSkillSheetImages.containsKey(key)) {
        _loadingKeys.add('skillsheet_$key');
        futures.add(
          _loadIntoCache(path, (img) => _heroSkillSheetImages[key] = img),
        );
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
    mapImagePaths.forEach((id, path) {
      if (!_mapImages.containsKey(id) && !_mapImages.containsKey(path)) {
        _loadingKeys.add('map_$id');
        futures.add(_loadIntoCache(path, (img) {
          _mapImages[id] = img;
          _mapImages[path] = img;
        }));
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
      final frame = await codec.getNextFrame();
      onLoaded(frame.image);
    } catch (_) {
      final altPath = assetPath.contains('/Ember-')
          ? assetPath.replaceAll('/Ember-', '/ember-')
          : (assetPath.contains('/ember-')
              ? assetPath.replaceAll('/ember-', '/Ember-')
              : null);
      if (altPath != null) {
        try {
          final data = await rootBundle.load(altPath);
          final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
          final frame = await codec.getNextFrame();
          onLoaded(frame.image);
        } catch (_) {}
      }
    }
  }
}
