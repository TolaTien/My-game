import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_game/services/player_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PlayerStorage.loadProfile();
  });

  group('PvE Coin & Gold Reward System Tests', () {
    test('addXu increments xu balance and notifies profileNotifier', () async {
      final initialXu = PlayerStorage.currentProfile.xu;
      var notified = false;

      void listener() {
        notified = true;
      }

      PlayerStorage.profileNotifier.addListener(listener);

      // Nhặt 5 xu trong trận PvE
      await PlayerStorage.addXu(5);

      expect(PlayerStorage.currentProfile.xu, equals(initialXu + 5));
      expect(notified, isTrue);

      PlayerStorage.profileNotifier.removeListener(listener);
    });

    test('addGold increments gold balance and notifies profileNotifier', () async {
      final initialGold = PlayerStorage.currentProfile.gold;

      // Thưởng 500 vàng khi vượt ải PvE
      await PlayerStorage.addGold(500);

      expect(PlayerStorage.currentProfile.gold, equals(initialGold + 500));
    });

    test('Sequential multi-floor reward accumulation', () async {
      final initialXu = PlayerStorage.currentProfile.xu;
      final initialGold = PlayerStorage.currentProfile.gold;

      // Tầng 1: nhặt 3 xu, thưởng 500 vàng
      await PlayerStorage.addXu(3);
      await PlayerStorage.addGold(500);

      // Tầng 2: nhặt 4 xu, thưởng 1000 vàng
      await PlayerStorage.addXu(4);
      await PlayerStorage.addGold(1000);

      expect(PlayerStorage.currentProfile.xu, equals(initialXu + 7));
      expect(PlayerStorage.currentProfile.gold, equals(initialGold + 1500));
    });

    test('Defeat preserves already collected coins', () async {
      final initialXu = PlayerStorage.currentProfile.xu;

      // Trong trận nhặt được 2 xu trước khi tử trận
      const collectedBeforeDeath = 2;
      await PlayerStorage.addXu(collectedBeforeDeath);

      expect(PlayerStorage.currentProfile.xu, equals(initialXu + 2));
    });

    test('convertXuToGold converts 1 Xu to 1000 Gold accurately', () async {
      final initialXu = PlayerStorage.currentProfile.xu;
      final initialGold = PlayerStorage.currentProfile.gold;

      final success = await PlayerStorage.convertXuToGold(1);
      expect(success, isTrue);
      expect(PlayerStorage.currentProfile.xu, equals(initialXu - 1));
      expect(PlayerStorage.currentProfile.gold, equals(initialGold + 1000));
    });
  });
}
