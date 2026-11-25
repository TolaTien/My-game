import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/registry/asset_registry.dart';
import 'package:my_game/registry/sprite_animation_catalog.dart';
import 'package:my_game/registry/sprite_image_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Runtime sprites are bundled and decode as images', () async {
    final paths = <String>{
      ...SpriteImageCache.heroPortraitPaths.values,
      ...SpriteImageCache.heroAttackPaths.values,
      ...SpriteImageCache.companionSpritePaths.values,
      ...SpriteImageCache.skillEffectPaths.values,
    };

    for (final path in paths) {
      final data = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      try {
        final frame = await codec.getNextFrame();
        expect(frame.image.width, greaterThan(0), reason: path);
        expect(frame.image.height, greaterThan(0), reason: path);
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
    }
  });

  test('Ember run paths use the bundled case-sensitive asset path', () async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final bundledPaths = manifest.listAssets();
    final runPath = nativeRunPaths['ember_02']!;
    expect(bundledPaths, contains(runPath));
    expect(SpriteImageCache.heroRunPaths['ember_02'], runPath);
    expect(SpriteImageCache.heroRunPaths['ember'], runPath);

    final data = jsonDecode(
      await rootBundle.loadString('assets/data/heroes.json'),
    ) as Map<String, dynamic>;
    final heroes = data['heroes'] as List<dynamic>;
    final ember = heroes.cast<Map<String, dynamic>>().singleWhere(
      (hero) => hero['id'] == 'ember_02',
    );
    expect((ember['sprites'] as Map<String, dynamic>)['runSheet'], runPath);
  });

  test(
    'Heroes with supplied art use bundled portrait and animation paths',
    () async {
      final data = jsonDecode(
        await rootBundle.loadString('assets/data/heroes.json'),
      ) as Map<String, dynamic>;
      final heroes = data['heroes'] as List<dynamic>;

      for (final entry in SpriteImageCache.heroPortraitPaths.entries) {
        final hero = heroes.cast<Map<String, dynamic>>().singleWhere(
          (hero) => hero['id'] == GameAssetRegistry.canonicalHeroId(entry.key),
        );
        final sprites = hero['sprites'] as Map<String, dynamic>;
        expect(
          sprites['portrait'] ?? sprites['idleSheet'],
          entry.value,
          reason: entry.key,
        );
        for (final field in [
          'idleSheet',
          'runSheet',
          'attackSheet',
          'skill1Sheet',
        ]) {
          final path = sprites[field] as String?;
          if (path == null) continue;
          final bytes = await rootBundle.load(path);
          expect(bytes.lengthInBytes, greaterThan(0), reason: path);
        }
      }
    },
  );
}
