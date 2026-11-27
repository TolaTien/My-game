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
      expect(profile.toJson().containsKey('diamonds'), isFalse);
      expect(profile.selectedHeroId, 'ember_02');
      expect(
        PlayerProfile.fromJson(profile.toJson()).selectedCompanionId,
        isNull,
      );
      expect(CompanionTypeExtension.fromId('gem_tumbler'), isNull);
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
