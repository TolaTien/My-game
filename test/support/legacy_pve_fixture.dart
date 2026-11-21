import 'package:my_game/registry/asset_registry.dart';

/// Collision/combat fixtures must not depend on production's random map choice.
const legacyTestMap = MapAssetConfig(
  id: 'integration_legacy',
  stage: 1,
  name: 'Legacy fixture',
  mode: 'pve',
  cols: 36,
  rows: 24,
  tileSize: 32,
  playerSpawn: [6, 6],
  bossSpawn: [28, 11],
  monsterPortals: [],
  buffNodes: [],
  obstacles: [
    [8, 6],
    [26, 6],
    [8, 16],
    [26, 16],
    [17, 10],
  ],
  tilesetImage: '',
  tiledMapFile: '',
);
