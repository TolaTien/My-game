import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data' show Uint32List;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'asset_registry.dart';
import 'companion_texture.dart';
import 'sprite_animation_catalog.dart';

export 'sprite_animation_catalog.dart'
    show HeroSpriteSet, SpriteClip, SpriteFrame, SpriteMotion;

/// Shares decoded images and prepared clips between the UI and Flame.
class SpriteImageCache {
  SpriteImageCache._(this._bundle);
  @visibleForTesting
  SpriteImageCache.forTesting(AssetBundle bundle) : this._(bundle);
  static final SpriteImageCache instance = SpriteImageCache._(rootBundle);

  final AssetBundle _bundle;
  final Map<String, ui.Image> _images = {};
  final Map<String, Future<ui.Image?>> _decodes = {};
  final Map<String, Future<Map<SpriteRegion, SpriteFrame>>> _prepared = {};
  final Map<String, Future<void>> _heroPreloads = {};
  final Map<String, List<HeroSpriteSet?>> _heroAnimations = {};
  final Map<String, Map<int, SpriteClip>> _skillAnimations = {};
  final Map<String, ui.Image> _mapsById = {};

  static String _canonical(String id) => GameAssetRegistry.canonicalHeroId(id);

  static final _regionsByPath = _indexRegions();

  static Map<String, Set<SpriteRegion>> _indexRegions() {
    final result = <String, Set<SpriteRegion>>{};
    for (final clip in [
      for (final hero in heroSpriteClips.values) ...[
        hero.idle,
        hero.run,
        hero.attack,
      ],
      for (final skills in skillSpriteClips.values) ...skills.values,
    ]) {
      for (final region in clip.frames) {
        result.putIfAbsent(region.path, () => {}).add(region);
      }
    }
    return result;
  }

  static const Map<String, String> heroPortraitPaths = {
    'george': 'assets/images/heroes/george/portrait.png',
    'ranger': 'assets/images/heroes/ranger/portrait.png',
    'tanker': 'assets/images/heroes/tanker/portrait.png',
    'ninja': 'assets/images/heroes/ninja/portrait.png',
    'valeria': 'assets/images/heroes/valeria/portrait.png',
    'garrick': 'assets/images/heroes/garrick/portrait.png',
    'nova_blade': 'assets/images/heroes/nova/nova_portrait.png',
    'nova': 'assets/images/heroes/nova/nova_portrait.png',
    'shadow_01': 'assets/images/heroes/shadow/shadow_01_portrait.png',
    'shadow': 'assets/images/heroes/shadow/shadow_01_portrait.png',
    'ember_02': 'assets/images/heroes/ember/ember.png',
    'ember': 'assets/images/heroes/ember/ember.png',
    'kaelen': 'assets/images/heroes/kaelen/kaelen_portrait.png',
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
    'ember_02': 'assets/images/heroes/ember/Ember-run.png',
    'ember': 'assets/images/heroes/ember/Ember-run.png',
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
    'kaelen': 'assets/images/heroes/kaelen/kaelen_attack.png',
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

  static bool isStripAnimatedHero(String heroId) =>
      stripAnimatedHeroIds.contains(_canonical(heroId));

  static bool isProceduralHero(String heroId) =>
      proceduralHeroIds.contains(_canonical(heroId));

  static final heroSequencePaths = Map<String, List<String>>.unmodifiable({
    for (final entry in shadowSequencePaths.entries) ...{
      'shadow_01_${entry.key}': entry.value,
      'shadow_${entry.key}': entry.value,
    },
  });

  static const companionSpritePaths = {
    'aegis_x9': 'assets/images/companions/aegis_x9.png',
    'cyber_drone': 'assets/images/companions/cyber_drone.png',
    'pyro_frost_dragon': 'assets/images/companions/pyro_frost_dragon.png',
    'luna_fox': 'assets/images/companions/luna_fox.png',
    'orbit_03': 'assets/images/companions/orbit_03.png',
  };

  static const companionIdleSheetPaths = {
    'luna_fox': 'assets/images/companions/luna_fox_idle_v2.png',
    'pyro_frost_dragon':
        'assets/images/companions/pyro_frost_dragon_fly_v2.png',
  };

  static const companionRunSheetPaths = {
    'luna_fox': 'assets/images/companions/luna_fox_run_v2.png',
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

  static const skillEffectPaths = {
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

  static const Map<String, String> heroSkillSheetPaths = {};

  static const mapImagePaths = {
    'map_bang': 'assets/images/maps/map-bang.png',
    'map_dao_bang_gia': 'assets/images/maps/map-dao-bang-gia.png',
    'map_rung_cay': 'assets/images/maps/map-rung-cay.png',
  };

  static final _legacyPaths = {
    ...heroPortraitPaths.values,
    ...heroAttackPaths.values,
    ...heroIdlePaths.values,
    ...heroRunPaths.values,
    ...heroSkillSheetPaths.values,
    ...companionSpritePaths.values,
    ...companionIdleSheetPaths.values,
    ...companionRunSheetPaths.values,
    ...skillEffectPaths.values,
    ...companionSkillSheetPaths.values,
    for (final paths in heroSequencePaths.values) ...paths,
    ...mapImagePaths.values,
  };

  ui.Image? getHeroImage(String heroId) =>
      _getLegacy(heroPortraitPaths[_canonical(heroId)]);

  ui.Image? getHeroIdleImage(String heroId) =>
      _getLegacy(heroIdlePaths[_canonical(heroId)]) ?? getHeroImage(heroId);

  ui.Image? getHeroRunImage(String heroId) =>
      _getLegacy(heroRunPaths[_canonical(heroId)]) ?? getHeroImage(heroId);

  ui.Image? getHeroAttackImage(String heroId) =>
      _getLegacy(heroAttackPaths[_canonical(heroId)]) ?? getHeroImage(heroId);

  ui.Image? getHeroSkillSheetImage(String heroId, int slot) =>
      _getLegacy(heroSkillSheetPaths['${_canonical(heroId)}_$slot']);

  ui.Image? getCompanionImage(String companionId) =>
      _getLegacy(companionSpritePaths[companionId]);

  ui.Image? getCompanionIdleSheet(String companionId) =>
      _getLegacy(companionIdleSheetPaths[companionId]);

  ui.Image? getCompanionRunSheet(String companionId) =>
      _getLegacy(companionRunSheetPaths[companionId]);

  ui.Image? getCompanionSkillSheet(String companionId) =>
      _getLegacy(companionSkillSheetPaths[companionId]);

  ui.Image? getSkillEffectImage(String heroId, int skillSlot) =>
      _getLegacy(skillEffectPaths['${_canonical(heroId)}_$skillSlot']);

  ui.Image? _getLegacy(String? path) {
    if (path == null) return null;
    final image = _images[path];
    if (image == null && !_decodes.containsKey(path)) unawaited(_decode(path));
    return image;
  }

  ui.Image? getMapImage(String mapId) =>
      _mapsById[mapId] ?? _getLegacy(mapImagePaths[mapId]);

  Future<ui.Image?> loadMapImageByPath(String path, {String? mapId}) async {
    if (path.isEmpty) return null;
    final image = _images[path] ?? await _decode(path);
    if (image != null && mapId != null) _mapsById[mapId] = image;
    return image;
  }

  void setMapImage(String mapId, ui.Image image) {
    _mapsById[mapId] = image;
    final path = mapImagePaths[mapId];
    if (path != null) _images[path] = image;
  }

  bool hasSequence(String heroId, String action) =>
      heroSequencePaths.containsKey('${_canonical(heroId)}_$action');

  ui.Image? getHeroSequenceFrame(String heroId, String action, int frameIndex) {
    final paths = heroSequencePaths['${_canonical(heroId)}_$action'];
    if (paths != null) {
      final image = _getLegacy(paths[frameIndex % paths.length]);
      if (image != null) return image;
    }
    return _images[heroPortraitPaths[_canonical(heroId)]];
  }

  HeroSpriteSet? getHeroAnimations(String heroId, {int facingRow = 2}) {
    final sets = _heroAnimations[_canonical(heroId)];
    if (sets == null) return null;
    return sets[sets.length == 1 ? 0 : facingRow.clamp(0, 4)];
  }

  SpriteClip? getSkillAnimation(String heroId, int slot) =>
      _skillAnimations[_canonical(heroId)]?[slot];

  Future<void> preloadHero(String heroId) {
    heroId = _canonical(heroId);
    final native = nativeHeroSpriteClips[heroId];
    final hero = heroSpriteClips[heroId];
    final skills = skillSpriteClips[heroId];
    if (native == null && hero == null && skills == null) {
      return Future<void>.value();
    }
    return _heroPreloads.putIfAbsent(heroId, () async {
      final nativeSets = <HeroSpriteSet?>[];
      if (native != null) {
        final decoded = <String, ui.Image?>{};
        for (final row in native) {
          for (final spec in [row.idle, row.run, row.attack]) {
            for (final region in spec.frames) {
              if (!decoded.containsKey(region.path)) {
                final image = await _decode(region.path);
                decoded[region.path] = image;
                if (image != null) _images[region.path] = image;
              }
            }
          }
          SpriteClip? clip(SpriteClipSpec spec) {
            final frames = <SpriteFrame>[];
            for (final region in spec.frames) {
              final image = decoded[region.path];
              if (image == null ||
                  region.right > image.width ||
                  region.bottom > image.height) {
                return null;
              }
              frames.add(
                SpriteFrame(
                  image: image,
                  source: region.source,
                  anchor: ui.Offset(region.anchorX, region.anchorY),
                  worldHeight: region.worldHeight,
                ),
              );
            }
            return SpriteClip(frames, spec.interval, loop: spec.loop);
          }

          nativeSets.add(_buildSet(row, clip));
        }
      }

      final needsFallback = nativeSets.isEmpty || nativeSets.contains(null);
      final prepared = <SpriteRegion, SpriteFrame>{};
      final paths = {
        if (hero != null && needsFallback)
          for (final spec in [hero.idle, hero.run, hero.attack])
            for (final region in spec.frames) region.path,
        if (skills != null)
          for (final spec in skills.values)
            for (final region in spec.frames) region.path,
      };
      for (final path in paths) {
        prepared.addAll(
          await _prepared.putIfAbsent(path, () => _prepare(path)),
        );
      }

      SpriteClip? legacyClip(SpriteClipSpec spec) {
        final frames = spec.frames
            .map((region) => prepared[region])
            .nonNulls
            .toList();
        return frames.isEmpty
            ? null
            : SpriteClip(frames, spec.interval, loop: spec.loop);
      }

      final fallback = needsFallback && hero != null
          ? _buildSet(hero, legacyClip)
          : null;
      if (nativeSets.isNotEmpty) {
        _heroAnimations[heroId] = [
          for (final set in nativeSets) set ?? fallback,
        ];
      } else if (fallback != null) {
        _heroAnimations[heroId] = [fallback];
      }
      if (skills != null) {
        _skillAnimations[heroId] = {
          for (final entry in skills.entries)
            entry.key: ?legacyClip(entry.value),
        };
      }
    });
  }

  static HeroSpriteSet? _buildSet(
    HeroClipSpecs specs,
    SpriteClip? Function(SpriteClipSpec) clip,
  ) {
    final idle = clip(specs.idle);
    final run = clip(specs.run);
    final attack = clip(specs.attack);
    if (idle == null || run == null || attack == null) return null;
    return HeroSpriteSet(idle: idle, run: run, attack: attack);
  }

  Future<void> preloadAll() async {
    final paths = {...heroPortraitPaths.values, ...companionSpritePaths.values};
    await Future.wait([..._decodes.values, ...paths.map(_decode)]);
  }

  Future<ui.Image?> _decode(String path) =>
      _decodes.putIfAbsent(path, () async {
        try {
          final data = await _bundle.load(path);
          final codec = await ui.instantiateImageCodec(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          );
          try {
            final frame = await codec.getNextFrame();
            var image = frame.image;
            if (companionSpritePaths.containsValue(path)) {
              image = await cleanCompanionTexture(
                frame.image,
                fox: path.endsWith('/luna_fox.png'),
              );
              if (!identical(image, frame.image)) frame.image.dispose();
            }
            if (_legacyPaths.contains(path)) _images[path] = image;
            return image;
          } finally {
            codec.dispose();
          }
        } catch (error) {
          debugPrint('SpriteImageCache: failed to load $path: $error');
          return null;
        }
      });

  Future<Map<SpriteRegion, SpriteFrame>> _prepare(String path) async {
    final raw = await _decode(path);
    if (raw == null) return {};
    try {
      final data = await raw.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return {};
      final pixels = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final regions = _regionsByPath[path]!.where((region) {
        final rect = region.source;
        return rect.left >= 0 &&
            rect.top >= 0 &&
            rect.right <= raw.width &&
            rect.bottom <= raw.height &&
            rect.width > 0 &&
            rect.height > 0;
      }).toList();
      if (regions.isEmpty) return {};

      // One prepared texture per path, with one blank pixel around each crop.
      final width = regions.fold(
        0,
        (w, r) => math.max(w, r.source.width.toInt() + 2),
      );
      final height = regions.fold(0, (h, r) => h + r.source.height.toInt() + 2);
      final atlas = Uint8List(width * height * 4);
      final rectangles = <SpriteRegion, ui.Rect>{};
      var y = 1;
      for (final region in regions) {
        final crop = _matte(pixels, raw.width, region);
        final rect = region.source;
        final w = rect.width.toInt();
        final h = rect.height.toInt();
        if (crop != null) {
          rectangles[region] = ui.Rect.fromLTWH(
            1,
            y.toDouble(),
            rect.width,
            rect.height,
          );
          for (var row = 0; row < h; row++) {
            final start = ((y + row) * width + 1) * 4;
            atlas.setRange(start, start + w * 4, crop, row * w * 4);
          }
        }
        y += h + 2;
      }
      if (rectangles.isEmpty) return {};
      final buffer = await ui.ImmutableBuffer.fromUint8List(atlas);
      try {
        final descriptor = ui.ImageDescriptor.raw(
          buffer,
          width: width,
          height: height,
          pixelFormat: ui.PixelFormat.rgba8888,
        );
        try {
          final codec = await descriptor.instantiateCodec();
          try {
            final image = (await codec.getNextFrame()).image;
            return {
              for (final entry in rectangles.entries)
                entry.key: SpriteFrame(
                  image: image,
                  source: entry.value,
                  anchor: ui.Offset(
                    entry.key.mirror
                        ? 1 - entry.key.anchorX
                        : entry.key.anchorX,
                    entry.key.anchorY,
                  ),
                  worldHeight: entry.key.worldHeight,
                ),
            };
          } finally {
            codec.dispose();
          }
        } finally {
          descriptor.dispose();
        }
      } finally {
        buffer.dispose();
      }
    } catch (error) {
      debugPrint('SpriteImageCache: failed to prepare $path: $error');
      return {};
    } finally {
      if (!_legacyPaths.contains(path) && !_images.containsKey(path)) {
        _decodes.remove(path);
        raw.dispose();
      }
    }
  }

  static Uint8List? _matte(Uint8List pixels, int stride, SpriteRegion region) {
    final rect = region.source;
    final w = rect.width.toInt();
    final h = rect.height.toInt();
    final area = w * h;
    final crop = Uint8List(area * 4);
    final backdrop = region.backdrop;
    final candidates = backdrop == null ? null : Uint8List(area);
    final red = (backdrop ?? 0) >> 16;
    final green = ((backdrop ?? 0) >> 8) & 255;
    final blue = (backdrop ?? 0) & 255;
    final tolerance = region.tolerance;
    var opaque = 0;

    for (var y = 0; y < h; y++) {
      final sourceRow =
          ((rect.top.toInt() + y) * stride + rect.left.toInt()) * 4;
      for (var x = 0; x < w; x++) {
        final index = y * w + x;
        final sourceX = region.mirror ? w - 1 - x : x;
        final source = sourceRow + sourceX * 4;
        final alpha = pixels[source + 3];
        if (alpha == 0) {
          candidates?[index] = 1;
          continue;
        }
        opaque++;
        final target = index * 4;
        crop[target] = pixels[source];
        crop[target + 1] = pixels[source + 1];
        crop[target + 2] = pixels[source + 2];
        crop[target + 3] = alpha;
        if (candidates == null) continue;
        // Compare straight RGB while preserving the premultiplied source bytes.
        final r = pixels[source] * 255 ~/ alpha;
        final g = pixels[source + 1] * 255 ~/ alpha;
        final b = pixels[source + 2] * 255 ~/ alpha;
        if (b >= blue - 18 &&
            r + g + b >= red + green + blue - 26 &&
            (r - red).abs() <= tolerance &&
            (g - green).abs() <= tolerance &&
            (b - blue).abs() <= tolerance &&
            ((b - r) - (blue - red)).abs() <= tolerance) {
          candidates[index] = 1;
        }
      }
    }
    // Hand masks cut away adjacent artwork where two panels share a crop.
    for (final exclusion in region.exclusions) {
      final left = (exclusion.left - rect.left).toInt();
      final right = (exclusion.right - rect.left).toInt();
      for (
        var y = (exclusion.top - rect.top).toInt();
        y < exclusion.bottom - rect.top;
        y++
      ) {
        for (var x = left; x < right; x++) {
          final index = y * w + (region.mirror ? w - 1 - x : x);
          final target = index * 4;
          if (crop[target + 3] != 0) opaque--;
          crop.fillRange(target, target + 4, 0);
          if (candidates != null) candidates[index] = 0;
        }
      }
    }
    // Polygon masks remove baked casters. Coordinates are crop-local.
    for (final polygon in region.exclusionPolygons) {
      if (polygon.length < 3) continue;
      for (var y = 0; y < h; y++) {
        final scanY = y + .5;
        final intersections = <double>[];
        for (var i = 0; i < polygon.length; i++) {
          final a = polygon[i];
          final b = polygon[(i + 1) % polygon.length];
          if ((a.dy <= scanY && b.dy > scanY) ||
              (b.dy <= scanY && a.dy > scanY)) {
            intersections.add(
              a.dx + (scanY - a.dy) * (b.dx - a.dx) / (b.dy - a.dy),
            );
          }
        }
        intersections.sort();
        for (var i = 0; i + 1 < intersections.length; i += 2) {
          final start = intersections[i].floor().clamp(0, w);
          final end = intersections[i + 1].ceil().clamp(0, w);
          for (var x = start; x < end; x++) {
            final index = y * w + (region.mirror ? w - 1 - x : x);
            final target = index * 4;
            if (crop[target + 3] != 0) opaque--;
            crop.fillRange(target, target + 4, 0);
            if (candidates != null) candidates[index] = 0;
          }
        }
      }
    }
    if (candidates != null) {
      // Flood only from crop edges to preserve internal colors and outlines.
      final queue = Uint32List(area);
      var write = 0;
      void visit(int index) {
        if (candidates[index] == 0) return;
        candidates[index] = 0;
        queue[write++] = index;
      }

      for (var x = 0; x < w; x++) {
        visit(x);
        visit((h - 1) * w + x);
      }
      for (var y = 0; y < h; y++) {
        visit(y * w);
        visit(y * w + w - 1);
      }
      for (var read = 0; read < write; read++) {
        final index = queue[read];
        final target = index * 4;
        if (crop[target + 3] != 0) opaque--;
        crop.fillRange(target, target + 4, 0);
        if (index % w != 0) visit(index - 1);
        if (index % w != w - 1) visit(index + 1);
        if (index >= w) visit(index - w);
        if (index < area - w) visit(index + w);
      }
    }
    return opaque == 0 ? null : crop;
  }
}
