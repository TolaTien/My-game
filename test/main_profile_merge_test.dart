import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_game/models/player_profile.dart';
import 'package:my_game/services/player_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(PlayerStorage.detachUser);

  test('Legacy skins round-trip alongside main star-rank and progression', () {
    final profile = PlayerProfile.fromJson({
      'playerCode': 'PROFILE_FIXTURE',
      'rankPoints': 1700,
      'rankStars': 17,
      'isChallengerTop10': false,
      'serverRank': 25,
      'unlockedSkinIds': ['skin_george_gold'],
      'selectedSkinId': 'skin_george_gold',
      'heroLevels': {'george': 20},
      'friendIds': ['friend-fixture'],
    });
    final reloaded = PlayerProfile.fromJson(
      jsonDecode(jsonEncode(profile.toJson())),
    );
    expect(reloaded.rankStars, 17);
    expect(reloaded.serverRank, 25);
    expect(reloaded.unlockedSkinIds, ['skin_george_gold']);
    expect(reloaded.selectedSkinId, 'skin_george_gold');
    expect(reloaded.getHeroLevel('george'), 20);
    expect(reloaded.friendIds, ['friend-fixture']);
    final unequipped = reloaded.copyWith(clearSkin: true);
    expect(unequipped.selectedSkinId, isNull);
    expect(unequipped.rankStars, 17);
    expect(unequipped.unlockedSkinIds, reloaded.unlockedSkinIds);
  });

  test(
    'Skin purchase uses account-scoped storage/cloud without losing rank',
    () async {
      final synced = <PlayerProfile>[];
      PlayerStorage.attachUser('merge_fixture', synced.add);
      await PlayerStorage.saveProfile(
        const PlayerProfile(diamonds: 100, rankStars: 8),
      );
      synced.clear();
      expect(await PlayerStorage.unlockSkin('skin_george_gold', 30), isTrue);
      expect(PlayerStorage.currentProfile.diamonds, 70);
      expect(PlayerStorage.currentProfile.rankStars, 8);
      expect(synced.single.selectedSkinId, 'skin_george_gold');
      final prefs = await SharedPreferences.getInstance();
      final stored = jsonDecode(
        prefs.getString('big_war_player_profile_merge_fixture')!,
      ) as Map<String, dynamic>;
      expect(stored['unlockedSkinIds'], ['skin_george_gold']);
      expect(stored['rankStars'], 8);
      expect(prefs.getString('gold_rush_player_profile'), isNull);
      expect(await PlayerStorage.unlockSkin('skin_george_gold', 30), isTrue);
      expect(PlayerStorage.currentProfile.diamonds, 70);
    },
  );

  test(
    'Unaffordable/negative-price skins and unowned selection are rejected',
    () async {
      await PlayerStorage.saveProfile(const PlayerProfile(diamonds: 10));
      expect(await PlayerStorage.unlockSkin('expensive', 20), isFalse);
      expect(await PlayerStorage.unlockSkin('negative', -20), isFalse);
      await PlayerStorage.selectSkin('unowned');
      expect(PlayerStorage.currentProfile.selectedSkinId, isNull);
      expect(PlayerStorage.currentProfile.diamonds, 10);
    },
  );
}
