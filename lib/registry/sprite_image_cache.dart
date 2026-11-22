import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'companion_texture.dart';

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
  final Map<String, ui.Image> _companionIdleSheets = {};
  final Map<String, ui.Image> _companionRunSheets = {};
  final Map<String, ui.Image> _companionSkillSheets = {};
  final Map<String, ui.Image> _skillImages = {};
  final Map<String, ui.Image> _mapImages = {};
  final Map<String, ui.Image> _rawPathCache = {};
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

  static const Map<String, List<String>> heroSequencePaths = {
    'shadow_01_idle': _shadowIdleFrames,
    'shadow_idle': _shadowIdleFrames,
    'shadow_01_run': _shadowRunFrames,
    'shadow_run': _shadowRunFrames,
    'shadow_01_attack': _shadowAttackFrames,
    'shadow_attack': _shadowAttackFrames,
  };

  static const Set<String> proceduralHeroIds = {};

  /// Các tướng sử dụng bộ spritesheet 4-frame ngang (idle/attack: 1024x256)
  /// và spritesheet chạy 4 hướng (run: 1024x1024 — Down/Up/Left/Right).
  static const Set<String> stripAnimatedHeroIds = {
    'george',
    'ranger',
    'tanker',
    'ninja',
    'valeria',
    'garrick',
  };

  static bool isProceduralHero(String heroId) =>
      proceduralHeroIds.contains(heroId);

  static bool isStripAnimatedHero(String heroId) =>
      stripAnimatedHeroIds.contains(heroId);

  static const Map<String, String> heroPortraitPaths = {
    'george': 'assets/images/heroes/george/portrait.png',
    'ranger': 'assets/images/heroes/ranger/portrait.png',
    'tanker': 'assets/images/heroes/tanker/portrait.png',
    'ninja': 'assets/images/heroes/ninja/portrait.png',
    'valeria': 'assets/images/heroes/valeria/portrait.png',
    'garrick': 'assets/images/heroes/garrick/portrait.png',
    'nova_blade': 'assets/images/heroes/nova/nova_portrait.png',
    'nova': 'assets/images/heroes/nova/nova_portrait.png',
    'shadow_01': 'assets/images/heroes/shadow_01_portrait.png',
    'shadow': 'assets/images/heroes/shadow_01_portrait.png',
    'ember_02': 'assets/images/heroes/ember/ember.png',
    'ember': 'assets/images/heroes/ember/ember.png',
  };

  static const Map<String, String> heroIdlePaths = {
    'george': 'assets/images/heroes/george/idle.png',
    'ranger': 'assets/images/heroes/ranger/idle.png',
    'tanker': 'assets/images/heroes/tanker/idle.png',
    'ninja': 'assets/images/heroes/ninja/idle.png',
    'valeria': 'assets/images/heroes/valeria/idle.png',
    'garrick': 'assets/images/heroes/garrick/idle.png',
    'nova_blade': 'assets/images/heroes/nova/nova.png',
    'nova': 'assets/images/heroes/nova/nova.png',
    'ember_02': 'assets/images/heroes/ember/Ember-idle.png',
    'ember': 'assets/images/heroes/ember/Ember-idle.png',
    'shadow_01': 'assets/images/heroes/shadow/idle/01.png',
    'shadow': 'assets/images/heroes/shadow/idle/01.png',
  };
  static const Map<String, String> heroRunPaths = {
    'george': 'assets/images/heroes/george/run.png',
    'ranger': 'assets/images/heroes/ranger/run.png',
    'tanker': 'assets/images/heroes/tanker/run.png',
    'ninja': 'assets/images/heroes/ninja/run.png',
    'valeria': 'assets/images/heroes/valeria/run.png',
    'garrick': 'assets/images/heroes/garrick/run.png',
    'nova_blade': 'assets/images/heroes/nova/nova-run.png',
    'nova': 'assets/images/heroes/nova/nova-run.png',
    'ember_02': 'assets/images/heroes/ember/ember-run.png',
    'ember': 'assets/images/heroes/ember/ember-run.png',
    'shadow_01': 'assets/images/heroes/shadow/run/01.png',
    'shadow': 'assets/images/heroes/shadow/run/01.png',
  };

  static const Map<String, String> heroAttackPaths = {
    'george': 'assets/images/heroes/george/attack.png',
    'ranger': 'assets/images/heroes/ranger/attack.png',
    'tanker': 'assets/images/heroes/tanker/attack.png',
    'ninja': 'assets/images/heroes/ninja/attack.png',
    'valeria': 'assets/images/heroes/valeria/attack.png',
    'garrick': 'assets/images/heroes/garrick/attack.png',
    'nova_blade': 'assets/images/heroes/nova/nova-attack.png',
    'nova': 'assets/images/heroes/nova/nova-attack.png',
    'ember_02': 'assets/images/heroes/ember/Ember-attack.png',
    'ember': 'assets/images/heroes/ember/Ember-attack.png',
    'shadow_01': 'assets/images/heroes/shadow/attack/01.png',
    'shadow': 'assets/images/heroes/shadow/attack/01.png',
  };

  static const Map<String, String> heroSkillSheetPaths = {};

  static const Map<String, String> companionSpritePaths = {
    'aegis_x9': 'assets/images/companions/aegis_x9.png',
    'cyber_drone': 'assets/images/companions/cyber_drone.png',
    'pyro_frost_dragon': 'assets/images/companions/pyro_frost_dragon.png',
    'luna_fox': 'assets/images/companions/luna_fox.png',
    'orbit_03': 'assets/images/companions/orbit_03.png',
  };

  static const Map<String, String> companionSkillSheetPaths = {
    'comp_attack': 'assets/images/skills/pet_skill_attack_nova.png',
    'companion_attack': 'assets/images/skills/pet_skill_attack_nova.png',
    'attack': 'assets/images/skills/pet_skill_attack_nova.png',
    'comp_defense': 'assets/images/skills/pet_skill_defense_barrier.png',
    'companion_defense': 'assets/images/skills/pet_skill_defense_barrier.png',
    'defense': 'assets/images/skills/pet_skill_defense_barrier.png',
    'shield': 'assets/images/skills/pet_skill_defense_barrier.png',
    'comp_control': 'assets/images/skills/pet_skill_frost_blizzard.png',
    'companion_frost': 'assets/images/skills/pet_skill_frost_blizzard.png',
    'control': 'assets/images/skills/pet_skill_frost_blizzard.png',
    'frost': 'assets/images/skills/pet_skill_frost_blizzard.png',
    'cyber_drone': 'assets/images/skills/pet_skill_cyber_heal.png',
    'luna_fox': 'assets/images/skills/pet_skill_luna_spirit.png',
    'orbit_03': 'assets/images/skills/pet_skill_orbit_laser.png',
    'aegis_x9': 'assets/images/skills/pet_skill_aegis_gravity.png',
    'comp_aegis': 'assets/images/skills/pet_skill_aegis_gravity.png',
    'aegis': 'assets/images/skills/pet_skill_aegis_gravity.png',
    'pyro_frost_dragon': 'assets/images/skills/pet_skill_dragon_storm.png',
  };

  static const Map<String, String> skillEffectPaths = {
    'nova_blade_1': 'assets/images/skills/nova_energy_slash.png',
    'nova_blade_2': 'assets/images/skills/nova_shadow_dash.png',
    'nova_blade_3': 'assets/images/skills/nova_quantum_burst.png',
  };

  static const Map<String, String> mapImagePaths = {
    'map_bang': 'assets/images/maps/map-bang.png',
    'map_dao_bang_gia': 'assets/images/maps/map-dao-bang-gia.png',
    'map_rung_cay': 'assets/images/maps/map-rung-cay.png',
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

  /// Original portraits remain separate from animation sheets.
  ui.Image? getCompanionIdleSheet(String companionId) {
    if (companionId != 'luna_fox' && companionId != 'pyro_frost_dragon') return null;
    final cached = _companionIdleSheets[companionId];
    if (cached != null) return cached;
    final key = 'comp_idle_$companionId';
    if (_loadingKeys.add(key)) {
      unawaited(_loadIntoCache(
        companionId == 'luna_fox'
            ? 'assets/images/companions/luna_fox_idle_v2.png'
            : 'assets/images/companions/pyro_frost_dragon_fly_v2.png',
        (image) => _companionIdleSheets[companionId] = image,
      ));
    }
    return null;
  }

  ui.Image? getCompanionRunSheet(String companionId) {
    if (companionId != 'luna_fox') return null;
    final cached = _companionRunSheets[companionId];
    if (cached != null) return cached;
    if (_loadingKeys.add('comp_run_$companionId')) {
      unawaited(_loadIntoCache('assets/images/companions/luna_fox_run_v2.png',
          (image) => _companionRunSheets[companionId] = image));
    }
    return null;
  }

  ui.Image? getCompanionSkillSheet(String companionId) {
    final cached = _companionSkillSheets[companionId];
    if (cached != null) return cached;
    final path = companionSkillSheetPaths[companionId];
    if (path != null && _loadingKeys.add('comp_skill_$companionId')) {
      unawaited(
        _loadIntoCache(
          path,
          (img) => _companionSkillSheets[companionId] = img,
        ),
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
      if (_rawPathCache.containsKey(p)) {
        images.add(_rawPathCache[p]!);
        continue;
      }
      try {
        final data = await rootBundle.load(p);
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        final frame = await codec.getNextFrame();
        _rawPathCache[p] = frame.image;
        images.add(frame.image);
      } catch (_) {}
    }
    if (images.isNotEmpty) {
      _frameSequences[key] = images;
      // Tự động gán cho alias để không nạp lại 2 lần
      if (key == 'shadow_01_idle') _frameSequences['shadow_idle'] = images;
      if (key == 'shadow_idle') _frameSequences['shadow_01_idle'] = images;
      if (key == 'shadow_01_run') _frameSequences['shadow_run'] = images;
      if (key == 'shadow_run') _frameSequences['shadow_01_run'] = images;
      if (key == 'shadow_01_attack') _frameSequences['shadow_attack'] = images;
      if (key == 'shadow_attack') _frameSequences['shadow_01_attack'] = images;
    }
  }

  Future<void> preloadAll() async {
    // 1. Tải ảnh đại diện tướng và thú cưng trước
    final priorityFutures = <Future<void>>[];
    heroPortraitPaths.forEach((id, path) {
      if (!_heroImages.containsKey(id)) {
        _loadingKeys.add('hero_$id');
        priorityFutures.add(_loadIntoCache(path, (img) => _heroImages[id] = img));
      }
    });
    companionSpritePaths.forEach((id, path) {
      if (!_companionImages.containsKey(id)) {
        _loadingKeys.add('comp_$id');
        priorityFutures.add(_loadIntoCache(path, (img) => _companionImages[id] = img));
      }
    });
    mapImagePaths.forEach((id, path) {
      if (!_mapImages.containsKey(id) && !_mapImages.containsKey(path)) {
        _loadingKeys.add('map_$id');
        priorityFutures.add(_loadIntoCache(path, (img) {
          _mapImages[id] = img;
          _mapImages[path] = img;
        }));
      }
    });
    await Future.wait(priorityFutures);

    // Nhường event loop cho Flutter vẽ mượt frame
    await Future<void>.delayed(Duration.zero);

    // 2. Tải ảnh kỹ năng, idle, run, attack
    final secondaryFutures = <Future<void>>[];
    heroIdlePaths.forEach((id, path) {
      if (!_heroIdleImages.containsKey(id)) {
        _loadingKeys.add('idle_$id');
        secondaryFutures.add(_loadIntoCache(path, (img) => _heroIdleImages[id] = img));
      }
    });
    heroRunPaths.forEach((id, path) {
      if (!_heroRunImages.containsKey(id)) {
        _loadingKeys.add('run_$id');
        secondaryFutures.add(_loadIntoCache(path, (img) => _heroRunImages[id] = img));
      }
    });
    heroAttackPaths.forEach((id, path) {
      if (!_heroAttackImages.containsKey(id)) {
        _loadingKeys.add('atk_$id');
        secondaryFutures.add(_loadIntoCache(path, (img) => _heroAttackImages[id] = img));
      }
    });
    skillEffectPaths.forEach((key, path) {
      if (!_skillImages.containsKey(key)) {
        _loadingKeys.add('skill_$key');
        secondaryFutures.add(_loadIntoCache(path, (img) => _skillImages[key] = img));
      }
    });
    companionSkillSheetPaths.forEach((id, path) {
      if (!_companionSkillSheets.containsKey(id)) {
        _loadingKeys.add('comp_skill_$id');
        secondaryFutures.add(
          _loadIntoCache(path, (img) => _companionSkillSheets[id] = img),
        );
      }
    });
    await Future.wait(secondaryFutures);

    // Nhường event loop
    await Future<void>.delayed(Duration.zero);

    // 3. Tải các frame chuỗi (Sequence) lần lượt để tránh nghẽn luồng UI
    for (final entry in heroSequencePaths.entries) {
      if (!_frameSequences.containsKey(entry.key)) {
        _loadingKeys.add('seq_${entry.key}');
        await _loadSequenceIntoCache(entry.key, entry.value);
        await Future<void>.delayed(Duration.zero);
      }
    }
  }

  Future<void> _loadIntoCache(
    String assetPath,
    void Function(ui.Image) onLoaded,
  ) async {
    if (_rawPathCache.containsKey(assetPath)) {
      onLoaded(_rawPathCache[assetPath]!);
      return;
    }
    try {
      final data = await rootBundle.load(assetPath);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      codec.dispose();
      var image = frame.image;
      if (assetPath.contains('/companions/') &&
          !assetPath.endsWith('_idle_v2.png') && !assetPath.endsWith('_run_v2.png') &&
          !assetPath.endsWith('_fly_v2.png')) {
        image = await cleanCompanionTexture(frame.image,
            fox: assetPath.endsWith('/luna_fox.png'));
        if (!identical(image, frame.image)) frame.image.dispose();
      }
      _rawPathCache[assetPath] = image;
      onLoaded(image);
    } catch (_) {
      final altPath = assetPath.contains('/Ember-')
          ? assetPath.replaceAll('/Ember-', '/ember-')
          : (assetPath.contains('/ember-')
              ? assetPath.replaceAll('/ember-', '/Ember-')
              : null);
      if (altPath != null) {
        if (_rawPathCache.containsKey(altPath)) {
          onLoaded(_rawPathCache[altPath]!);
          return;
        }
        try {
          final data = await rootBundle.load(altPath);
          final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
          final frame = await codec.getNextFrame();
          _rawPathCache[altPath] = frame.image;
          onLoaded(frame.image);
        } catch (_) {}
      }
    }
  }
}
