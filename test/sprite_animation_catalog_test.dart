import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/registry/sprite_animation_catalog.dart';
import 'package:my_game/registry/sprite_image_cache.dart';

const _valeriaSkills = 'assets/images/skills/valeria_skills.png';
const _cyberSkills = 'assets/images/skills/cyber_skill_effects.png';

class _CountingBundle extends CachingAssetBundle {
  final loads = <String, int>{};
  final replacements = <String, ByteData>{};
  final missing = <String>{};

  @override
  Future<ByteData> load(String key) async {
    loads.update(key, (count) => count + 1, ifAbsent: () => 1);
    if (missing.contains(key)) throw StateError('Missing test asset $key');
    return replacements[key] ?? await rootBundle.load(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled clips have verified frame counts, bounds and alpha', () async {
    final cache = SpriteImageCache.forTesting(rootBundle);
    await cache.preloadAll();
    final pixelData = <ui.Image, ByteData>{};
    const counts = {
      'nova_blade': [5, 8, 5, 1, 2, 3],
      'shadow_01': [16, 16, 16, 2, 2, 3],
      'ember_02': [5, 8, 5, 2, 2, 1],
      'valeria': [1, 1, 2, 1, 1, 1],
      'garrick': [1, 1, 3, 1, 1, 2],
      'kaelen': [1, 2, 3, 1, 2, 1],
    };
    for (final entry in counts.entries) {
      final id = entry.key;
      await cache.preloadHero(id);
      final hero = cache.getHeroAnimations(id)!;
      final clips = [
        hero.idle,
        hero.run,
        hero.attack,
        for (var slot = 1; slot <= 3; slot++)
          cache.getSkillAnimation(id, slot)!,
      ];
      expect(clips.map((clip) => clip.frames.length), entry.value, reason: id);
      final specs = heroSpriteClips[id]!;
      final sourceClips = [
        specs.idle,
        specs.run,
        specs.attack,
        ...skillSpriteClips[id]!.values,
      ];
      for (var n = 0; n < clips.length; n++) {
        final clip = clips[n];
        for (var i = 0; i < clip.frames.length; i++) {
          final frame = clip.frames[i];
          final image = frame.image;
          final rect = frame.source;
          final nativeBody =
              n < 3 &&
              const ['nova_blade', 'shadow_01', 'ember_02'].contains(id);
          if (!nativeBody) {
            final region = sourceClips[n].frames[i];
            expect(rect.size, region.source.size, reason: id);
            expect(rect.left, greaterThan(0));
            expect(rect.top, greaterThan(0));
            expect(rect.right, lessThan(image.width));
            expect(rect.bottom, lessThan(image.height));
          } else {
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.top, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(image.width));
            expect(rect.bottom, lessThanOrEqualTo(image.height));
          }
          expect(frame.anchor.dx, inInclusiveRange(0, 1));
          expect(frame.anchor.dy, inInclusiveRange(0, 1));
          if (n < 3) expect(frame.anchor.dy, greaterThan(.85));

          final pixels = pixelData[image] ??= (await image.toByteData())!;
          var transparent = 0;
          var visible = 0;
          for (var y = rect.top.toInt(); y < rect.bottom; y++) {
            for (var x = rect.left.toInt(); x < rect.right; x++) {
              final alpha = pixels.getUint8((y * image.width + x) * 4 + 3);
              if (alpha == 0) transparent++;
              if (alpha > 127) visible++;
            }
          }
          final area = rect.width * rect.height;
          expect(
            transparent,
            greaterThan(area * .03),
            reason: '$id $n/$i background',
          );
          expect(visible, greaterThan(area * .03), reason: '$id $n/$i artwork');
        }
      }
    }
  });

  test(
    'preloads coalesce by PNG and share prepared textures across regions',
    () async {
      final bundle = _CountingBundle();
      final cache = SpriteImageCache.forTesting(bundle);
      expect(cache.getHeroAnimations('valeria'), isNull);
      expect(cache.getSkillAnimation('valeria', 1), isNull);
      expect(bundle.loads, isEmpty);
      final first = cache.preloadHero('valeria');
      expect(cache.preloadHero('valeria'), same(first));
      await Future.wait([
        first,
        cache.preloadAll(),
        cache.preloadHero('shadow_01'),
        cache.preloadHero('ember_02'),
        cache.preloadHero('garrick'),
        cache.preloadHero('nova_blade'),
      ]);
      expect(bundle.loads[_valeriaSkills], 1);
      expect(bundle.loads[_cyberSkills], 1);
      expect(bundle.loads.values, everyElement(1));
      final frames = [
        for (var slot = 1; slot <= 3; slot++)
          cache.getSkillAnimation('valeria', slot)!.frames.single,
      ];
      expect(frames.map((frame) => frame.image).toSet(), hasLength(1));
      expect(frames.map((frame) => frame.source).toSet(), hasLength(3));
      expect(
        cache.getSkillEffectImage('valeria', 1),
        same(cache.getSkillEffectImage('valeria', 3)),
      );
      expect(cache.getHeroImage('valeria'), isNotNull);
      expect(
        cache.getSkillAnimation('ember_02', 3)!.frames.single.image,
        same(cache.getSkillAnimation('garrick', 3)!.frames.last.image),
      );
      expect(
        cache.getSkillAnimation('ember_02', 3)!.frames.single,
        same(cache.getSkillAnimation('ember', 3)!.frames.single),
      );
      final clip = cache.getHeroAnimations('nova_blade')!.run;
      expect(clip.frameAt(0), same(clip.frames.first));
      expect(clip.frameAt(clip.frameDuration + .01), same(clip.frames[1]));
      expect(clip.frameAt(clip.duration), same(clip.frames.first));
      final attack = cache.getHeroAnimations('nova_blade')!.attack;
      expect(attack.frameAt(attack.duration * 2), same(attack.frames.last));
      expect(
        attack.frameAt(0, normalizedProgress: .5),
        same(attack.frames[attack.frames.length ~/ 2]),
      );
      expect(
        attack.frameAt(0, normalizedProgress: 1),
        same(attack.frames.last),
      );
    },
  );

  test(
    'edge matte preserves both black outlines and enclosed matching colors',
    () async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final matte = ui.Paint()..color = const ui.Color(0xff0d1015);
      canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 963, 184), matte);
      canvas.drawRect(
        const ui.Rect.fromLTWH(40, 30, 50, 50),
        ui.Paint()..color = const ui.Color(0xff000000),
      );
      canvas.drawRect(const ui.Rect.fromLTWH(45, 35, 40, 40), matte);
      final picture = recorder.endRecording();
      final image = await picture.toImage(963, 184);
      picture.dispose();
      final bundle = _CountingBundle();
      bundle.replacements[_valeriaSkills] = (await image.toByteData(
        format: ui.ImageByteFormat.png,
      ))!;
      image.dispose();

      final cache = SpriteImageCache.forTesting(bundle);
      await cache.preloadHero('valeria');
      final frame = cache.getSkillAnimation('valeria', 1)!.frames.single;
      final region = skillSpriteClips['valeria']![1]!.frames.single;
      final pixels = (await frame.image.toByteData())!;
      int rgba(int assetX, int assetY) {
        final localX = assetX - region.source.left.toInt();
        final x =
            frame.source.left.toInt() +
            (region.mirror ? frame.source.width.toInt() - 1 - localX : localX);
        final y = frame.source.top.toInt() + assetY - region.source.top.toInt();
        return pixels.getUint32((y * frame.image.width + x) * 4);
      }

      expect(
        region.mirror,
        isTrue,
        reason: 'source points left; projectile travels right',
      );
      expect(rgba(20, 20), 0x00000000);
      expect(rgba(40, 30), 0x000000ff);
      expect(rgba(60, 50), 0x0d1015ff);
      expect(cache.getSkillAnimation('valeria', 2), isNull);
      expect(cache.getSkillAnimation('valeria', 3), isNull);
    },
  );

  test(
    'Valeria skill two masks its baked caster and keeps ring sides',
    () async {
      final cache = SpriteImageCache.forTesting(rootBundle);
      await cache.preloadHero('valeria');
      final frame = cache.getSkillAnimation('valeria', 2)!.frames.single;
      final pixels = (await frame.image.toByteData())!;
      int alphaAt(int cropX, int cropY) {
        final x = frame.source.left.toInt() + cropX;
        final y = frame.source.top.toInt() + cropY;
        return pixels.getUint8((y * frame.image.width + x) * 4 + 3);
      }

      expect(alphaAt(140, 20), 0, reason: 'baked head');
      expect(alphaAt(140, 80), 0, reason: 'baked body');
      expect(alphaAt(140, 130), 0, reason: 'baked feet');
      expect(alphaAt(20, 70), 255, reason: 'left cyan ring');
      expect(alphaAt(250, 75), 255, reason: 'right orange ring');
      expect(
        skillSpriteClips['valeria']![1]!.frames.single.exclusionPolygons,
        isEmpty,
        reason: 'slot one remains unchanged',
      );
      expect(
        skillSpriteClips['valeria']![3]!.frames.single.exclusionPolygons,
        isEmpty,
        reason: 'slot three remains unchanged',
      );
    },
  );

  test('missing paths and heroes are explicit procedural fallbacks', () async {
    final bundle = _CountingBundle()..missing.add(_valeriaSkills);
    final cache = SpriteImageCache.forTesting(bundle);
    for (final id in ['george', 'ranger', 'tanker', 'ninja', 'unknown']) {
      await cache.preloadHero(id);
      expect(cache.getHeroAnimations(id), isNull);
      for (var slot = 1; slot <= 3; slot++) {
        expect(cache.getSkillAnimation(id, slot), isNull);
      }
    }
    expect(bundle.loads, isEmpty);
    await cache.preloadHero('valeria');
    expect(cache.getHeroAnimations('valeria'), isNotNull);
    for (var slot = 0; slot <= 4; slot++) {
      expect(cache.getSkillAnimation('valeria', slot), isNull);
    }
    expect(bundle.loads[_valeriaSkills], 1);
  });
}
