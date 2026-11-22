import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/models/player_profile.dart';
import 'package:my_game/models/pvp_match.dart';
import 'package:my_game/screens/widgets/edit_profile_dialog.dart';
import 'package:my_game/screens/widgets/rank_badge.dart';

void main() {
  group('Rank Assets & Profile Rank Display', () {
    test('All 7 rank PNG assets exist and map correctly from PvpRankSystem', () {
      const expected = {
        'Đồng': 'assets/images/ranks/rank_dong.png',
        'Bạc': 'assets/images/ranks/rank_bac.png',
        'Vàng': 'assets/images/ranks/rank_vang.png',
        'Bạch Kim': 'assets/images/ranks/rank_bach_kim.png',
        'Kim Cương': 'assets/images/ranks/rank_kim_cuong.png',
        'Huyền Thoại': 'assets/images/ranks/rank_huyen_thoai.png',
        'Thách Đấu': 'assets/images/ranks/rank_thach_dau.png',
      };

      for (final entry in expected.entries) {
        final path = PvpRankSystem.getRankAssetPath(entry.key);
        expect(path, entry.value);
        expect(File(path).existsSync(), isTrue, reason: 'Missing asset $path');
      }
    });

    test('PlayerProfile.rankAssetPath matches player rank tier', () {
      const bronze = PlayerProfile(rankStars: 1, rankPoints: 1065);
      expect(bronze.rankTier, 'Đồng');
      expect(bronze.rankAssetPath, 'assets/images/ranks/rank_dong.png');

      const diamond = PlayerProfile(rankStars: 14, rankPoints: 1930);
      expect(diamond.rankTier, 'Kim Cương');
      expect(diamond.rankAssetPath, 'assets/images/ranks/rank_kim_cuong.png');

      const challenger = PlayerProfile(
        rankStars: 21,
        rankPoints: 2180,
        isChallengerTop10: true,
        serverRank: 2,
      );
      expect(challenger.rankTier, 'Thách Đấu');
      expect(challenger.rankAssetPath, 'assets/images/ranks/rank_thach_dau.png');
    });

    testWidgets('EditProfileDialog displays user rank badge, stars, RP and next tier',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const profile = PlayerProfile(
        playerName: 'Chiến Thần Test',
        playerCode: 'GR7777',
        rankStars: 14,
        rankPoints: 1930,
        totalMatches: 8,
        totalWins: 6,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EditProfileDialog(profile: profile),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RankBadge), findsOneWidget);
      expect(find.text('RANK KIM CƯƠNG'), findsOneWidget);
      expect(find.text('2/3 Sao'), findsOneWidget);
      expect(find.text('1930 RP'), findsOneWidget);
      expect(find.text('Kế tiếp: Huyền Thoại'), findsOneWidget);
      expect(find.text('Tỉ lệ thắng'), findsOneWidget);
      expect(find.text('75%'), findsOneWidget);
      expect(find.text('Kim Cương'), findsNothing);
    });

    testWidgets('EditProfileDialog displays Top 10 Challenger badge and accumulated stars',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const profile = PlayerProfile(
        playerName: 'TopServer',
        playerCode: 'GR0001',
        rankStars: 22,
        rankPoints: 2210,
        isChallengerTop10: true,
        serverRank: 1,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EditProfileDialog(profile: profile),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RankBadge), findsOneWidget);
      expect(find.text('RANK THÁCH ĐẤU'), findsOneWidget);
      expect(find.text('TOP #1'), findsOneWidget);
      expect(find.text('7 Sao Tích Lũy'), findsOneWidget);
      expect(find.text('2210 RP'), findsOneWidget);
    });
  });
}
