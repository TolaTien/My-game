import 'package:my_game/models/database_models.dart';
import 'package:my_game/models/pvp_match.dart';

/// Explicit test data; production starts with an empty, real-player leaderboard.
List<LeaderboardEntry> leaderboardFixture() {
  const players = [
    ('BáĐạo99', 2850),
    ('ChiếnThần_SG', 2680),
    ('ĐộcCôCầuBại', 2540),
    ('RồngLửaVN', 2420),
    ('TrùmSolo1v1', 2310),
    ('SátThủBóngĐêm', 2230),
    ('LôiThầnHàThành', 2150),
    ('KiếmThánh_VN', 2080),
    ('VôĐịchThiênHạ', 1990),
    ('BóngMaHưKhông', 1940),
    ('ThầnĐiêuĐạiHiệp', 1880),
    ('BấtBại_9x', 1820),
    ('HắcBạchCôngTử', 1760),
    ('TiểuLongNữ', 1710),
    ('CuồngPhong_HN', 1640),
    ('BãoLửa2026', 1580),
    ('HiệpSĩBóngĐêm', 1520),
    ('NinjaSiêuCấp', 1440),
    ('ThầnSấm_VN', 1380),
    ('ĐạiHiệpBấtTử', 1290),
  ];
  return [
    for (var i = 0; i < players.length; i++)
      LeaderboardEntry(
        uid: 'fixture_player_$i',
        name: players[i].$1,
        rankPoints: players[i].$2,
        rankTier: PvpEloCalculator.getRankTier(players[i].$2),
        winRate: '50%',
        rankNumber: i + 1,
        lastUpdated: DateTime.utc(2026),
        heroId: 'george',
      ),
  ];
}
