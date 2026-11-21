import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_game/models/player_profile.dart';
import 'package:my_game/services/player_storage.dart';
import 'package:my_game/game/components/companion_component.dart';

void main() {
  test(
    'Old Gem ownership and equipment are removed without changing progress',
    () {
      final profile = PlayerProfile.fromJson({
        'gold': 1234,
        'diamonds': 87,
        'selectedHeroId': 'ember_02',
        'unlockedCompanionIds': [
          'gem_tumbler',
          'luna_fox',
          'pyro_frost_dragon',
        ],
        'selectedCompanionId': 'gem_tumbler',
      });
      expect(profile.selectedCompanionId, isNull);
      expect(profile.unlockedCompanionIds, ['luna_fox', 'pyro_frost_dragon']);
      expect(profile.gold, 1234);
      expect(profile.diamonds, 87);
      expect(profile.selectedHeroId, 'ember_02');
      expect(
        PlayerProfile.fromJson(profile.toJson()).selectedCompanionId,
        isNull,
      );
      expect(CompanionTypeExtension.fromId('gem_tumbler'), isNull);
    },
  );
  test('Migration preserves legacy IDs, unknown fields, skins and rank', () {
    for (final id in ['comp_aegis', 'aegis', 'future_companion']) {
      final profile = PlayerProfile.fromJson({
        'unlockedCompanionIds': ['gem_tumbler', id],
        'selectedCompanionId': id,
        'unlockedSkinIds': ['skin_legacy'],
        'selectedSkinId': 'skin_legacy',
        'rankStars': 18,
        'serverRank': 4,
        'isChallengerTop10': true,
        'heroLevels': {'ember_02': 47},
        'heroExp': {'ember_02': 123},
        'futureAccountData': {'revision': 7},
      }).copyWith(gold: 4321);
      final saved = profile.toJson();
      final restored = PlayerProfile.fromJson(saved);
      expect(restored.unlockedCompanionIds, [id]);
      expect(restored.selectedCompanionId, id);
      expect(restored.unlockedSkinIds, ['skin_legacy']);
      expect(restored.selectedSkinId, 'skin_legacy');
      expect(restored.rankStars, 18);
      expect(restored.serverRank, 4);
      expect(restored.isChallengerTop10, isTrue);
      expect(restored.heroLevels['ember_02'], 47);
      expect(restored.heroExp['ember_02'], 123);
      expect(restored.gold, 4321);
      expect(saved['futureAccountData'], {'revision': 7});
    }
  });
  test(
    'Owned legacy Aegis aliases remain equipable without new sales',
    () async {
      SharedPreferences.setMockInitialValues({});
      for (final id in ['comp_aegis', 'aegis']) {
        PlayerStorage.profileNotifier.value = PlayerProfile(
          gold: 2000,
          unlockedCompanionIds: [id],
        );
        await PlayerStorage.selectCompanion(id);
        expect(PlayerStorage.currentProfile.selectedCompanionId, id);
        expect(CompanionTypeExtension.fromId(id), CompanionType.aegisX9);
        expect(await PlayerStorage.unlockCompanion(id, 800), isFalse);
        expect(PlayerStorage.currentProfile.gold, 2000);
      }
      PlayerStorage.profileNotifier.value = PlayerProfile.defaultProfile();
    },
  );
  test('Other equipped companions survive profile migration', () {
    final profile = PlayerProfile.fromJson({
      'unlockedCompanionIds': ['gem_tumbler', 'luna_fox'],
      'selectedCompanionId': 'luna_fox',
    });
    expect(profile.selectedCompanionId, 'luna_fox');
    expect(profile.unlockedCompanionIds, ['luna_fox']);
  });
  test(
    'Removed companion cannot be purchased or equipped through storage',
    () async {
      SharedPreferences.setMockInitialValues({});
      PlayerStorage.profileNotifier.value = const PlayerProfile(
        gold: 2000,
        selectedCompanionId: 'luna_fox',
      );
      expect(await PlayerStorage.unlockCompanion('gem_tumbler', 850), isFalse);
      await PlayerStorage.selectCompanion('gem_tumbler');
      expect(PlayerStorage.currentProfile.gold, 2000);
      expect(PlayerStorage.currentProfile.selectedCompanionId, 'luna_fox');
      PlayerStorage.profileNotifier.value = PlayerProfile.defaultProfile();
    },
  );
}
