// ignore_for_file: avoid_print
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// ============================================================================
/// Gold Rush — Procedural Map Generator CLI Tool
/// ============================================================================
/// Công cụ tự động sinh bản đồ 2D cho game Gold Rush (Flame Engine) tuân thủ:
/// 1. Kiến trúc Data-Driven (`assets/data/maps.json`).
/// 2. Đảm bảo tính liên thông 100% cho thuật toán AI tìm đường A* (BFS validation).
/// 3. In preview trực quan ASCII Art trên Console.
/// 4. Tự động sinh file ảnh PNG nghệ thuật độc quyền theo chủ đề (`assets/images/maps/`).
///
/// Cách dùng:
///   dart run tool/generate_map.dart [options]
///
/// Ví dụ:
///   dart run tool/generate_map.dart --name="Hầm Ngục Hỏa Long" --theme=volcanic --type=arena
///   dart run tool/generate_map.dart --regenerate-images
/// ============================================================================

void main(List<String> args) {
  final options = _parseArgs(args);

  if (options.showHelp) {
    _printHelp();
    return;
  }

  if (options.listMaps) {
    _listExistingMaps();
    return;
  }

  if (options.regenerateImages) {
    _regenerateImagesForAllMaps();
    return;
  }

  print('\x1B[36m============================================================\x1B[0m');
  print('\x1B[1;33m🏆 GOLD RUSH — PROCEDURAL MAP GENERATOR\x1B[0m');
  print('\x1B[36m============================================================\x1B[0m');

  final generator = MapGenerator(options);
  final generatedMap = generator.generate();

  // In ASCII Preview
  _printAsciiPreview(generatedMap);

  // In Bảng Thống Kê
  _printSummaryTable(generatedMap, options);

  // Ghi vào file JSON (nếu không phải dry-run)
  if (options.dryRun) {
    print('\x1B[33m[DRY RUN] Chế độ chạy thử — Không ghi dữ liệu vào assets/data/maps.json\x1B[0m');
  } else {
    _saveToJson(generatedMap, generateImage: options.generateImage);
  }
}

class GeneratorOptions {
  final String? id;
  final String? name;
  final String theme;
  final String type;
  final int cols;
  final int rows;
  final int portalsCount;
  final int buffsCount;
  final int? seed;
  final bool dryRun;
  final bool listMaps;
  final bool showHelp;
  final bool generateImage;
  final bool regenerateImages;

  GeneratorOptions({
    this.id,
    this.name,
    this.theme = 'golden_sanctum',
    this.type = 'arena',
    this.cols = 36,
    this.rows = 24,
    this.portalsCount = 4,
    this.buffsCount = 3,
    this.seed,
    this.dryRun = false,
    this.listMaps = false,
    this.showHelp = false,
    this.generateImage = true,
    this.regenerateImages = false,
  });
}

GeneratorOptions _parseArgs(List<String> args) {
  String? id;
  String? name;
  String theme = 'golden_sanctum';
  String type = 'arena';
  int cols = 36;
  int rows = 24;
  int portals = 4;
  int buffs = 3;
  int? seed;
  bool dryRun = false;
  bool listMaps = false;
  bool showHelp = false;
  bool generateImage = true;
  bool regenerateImages = false;

  for (final arg in args) {
    if (arg == '--help' || arg == '-h') {
      showHelp = true;
    } else if (arg == '--list') {
      listMaps = true;
    } else if (arg == '--dry-run') {
      dryRun = true;
    } else if (arg == '--no-image') {
      generateImage = false;
    } else if (arg == '--regenerate-images') {
      regenerateImages = true;
    } else if (arg.startsWith('--id=')) {
      id = arg.substring(5).trim();
    } else if (arg.startsWith('--name=')) {
      name = arg.substring(7).trim();
    } else if (arg.startsWith('--theme=')) {
      theme = arg.substring(8).trim();
    } else if (arg.startsWith('--type=')) {
      type = arg.substring(7).trim();
    } else if (arg.startsWith('--cols=')) {
      cols = int.tryParse(arg.substring(7).trim()) ?? cols;
    } else if (arg.startsWith('--rows=')) {
      rows = int.tryParse(arg.substring(7).trim()) ?? rows;
    } else if (arg.startsWith('--portals=')) {
      portals = int.tryParse(arg.substring(10).trim()) ?? portals;
    } else if (arg.startsWith('--buffs=')) {
      buffs = int.tryParse(arg.substring(8).trim()) ?? buffs;
    } else if (arg.startsWith('--seed=')) {
      seed = int.tryParse(arg.substring(7).trim());
    }
  }

  return GeneratorOptions(
    id: id,
    name: name,
    theme: theme,
    type: type,
    cols: cols.clamp(20, 80),
    rows: rows.clamp(16, 60),
    portalsCount: portals.clamp(2, 8),
    buffsCount: buffs.clamp(1, 10),
    seed: seed,
    dryRun: dryRun,
    listMaps: listMaps,
    showHelp: showHelp,
    generateImage: generateImage,
    regenerateImages: regenerateImages,
  );
}

void _printHelp() {
  print('''
Gold Rush — Procedural Map Generator CLI Tool

Cú pháp:
  dart run tool/generate_map.dart [options]

Các tùy chọn:
  --name=<name>         Tên hiển thị của bản đồ (VD: "Hầm Ngục Hỏa Long")
  --id=<id>             ID định danh (mặc định: tự sinh dạng slug)
  --theme=<theme>       Chủ đề: golden_sanctum, volcanic, ice_arena, frost_island, forest, cyber, neon, alien
  --type=<type>         Kiểu địa hình:
                          * arena  : Đấu trường đối xứng, cột đá chiến thuật (chuẩn PvP & PvE)
                          * rooms  : Các buồng phòng liên hoàn nối hành lang (Roguelike Dungeon)
                          * ruins  : Phế tích cổ, các mảng tường đá vụn đổ
                          * cavern : Hang động tự nhiên với đá mài nhẵn
  --cols=<cols>         Số cột ô (chiều rộng, mặc định: 36)
  --rows=<rows>         Số hàng ô (chiều cao, mặc định: 24)
  --portals=<count>     Số lượng cổng quái vật (mặc định: 4)
  --buffs=<count>       Số lượng điểm buff / hòm báu (mặc định: 3)
  --seed=<int>          Seed ngẫu nhiên (để sinh lại map tương tự khi cần)
  --no-image            Không sinh file ảnh PNG (mặc định luôn tự động sinh PNG độc quyền)
  --regenerate-images   Tự động sinh ảnh PNG cho toàn bộ các map trong maps.json chưa có ảnh
  --dry-run             Chỉ chạy giả lập & xem preview, KHÔNG ghi vào file json
  --list                Xem danh sách toàn bộ các map hiện có
  --help, -h            Hiển thị hướng dẫn này
''');
}

void _listExistingMaps() {
  final file = File('assets/data/maps.json');
  if (!file.existsSync()) {
    print('\x1B[31m[LỖI] Không tìm thấy file assets/data/maps.json\x1B[0m');
    return;
  }
  final content = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final maps = (content['maps'] as List).cast<Map<String, dynamic>>();

  print('\x1B[32m=== DANH SÁCH BẢN ĐỒ HIỆN TẠI TRONG ASSETS/DATA/MAPS.JSON (${maps.length} MAPS) ===\x1B[0m');
  print('-------------------------------------------------------------------------------');
  print('Stage | ID                        | Tên bản đồ                 | Theme       | Kích thước');
  print('-------------------------------------------------------------------------------');
  for (final m in maps) {
    final stage = '${m['stage']}'.padRight(5);
    final id = '${m['id']}'.padRight(25);
    final name = '${m['name']}'.padRight(26);
    final theme = '${m['theme'] ?? 'sanctum'}'.padRight(11);
    final size = '${m['cols']}x${m['rows']}';
    print('$stage | $id | $name | $theme | $size');
  }
  print('-------------------------------------------------------------------------------');
}

class GeneratedMapData {
  final String id;
  final int stage;
  final String name;
  final String theme;
  final String type;
  final int cols;
  final int rows;
  final int tileSize;
  final List<int> playerSpawn;
  final List<int> bossSpawn;
  final List<List<int>> monsterPortals;
  final List<List<int>> buffNodes;
  final List<List<int>> obstacles; // [[col, row, width, height]]
  final List<List<bool>> walkableGrid;
  final int seed;
  final String description;
  String imageAsset;

  GeneratedMapData({
    required this.id,
    required this.stage,
    required this.name,
    required this.theme,
    required this.type,
    required this.cols,
    required this.rows,
    required this.tileSize,
    required this.playerSpawn,
    required this.bossSpawn,
    required this.monsterPortals,
    required this.buffNodes,
    required this.obstacles,
    required this.walkableGrid,
    required this.seed,
    required this.description,
    this.imageAsset = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'stage': stage,
        'name': name,
        'mode': 'all',
        'cols': cols,
        'rows': rows,
        'tileSize': tileSize,
        'playerSpawn': playerSpawn,
        'bossSpawn': bossSpawn,
        'monsterPortals': monsterPortals,
        'buffNodes': buffNodes,
        if (obstacles.isNotEmpty) 'obstacles': obstacles,
        'tilesetImage': '',
        'tiledMapFile': '',
        'imageAsset': imageAsset,
        'theme': theme,
        'description': description,
      };
}

class MapGenerator {
  final GeneratorOptions options;
  late final Random rng;
  late final int seed;

  MapGenerator(this.options) {
    seed = options.seed ?? (DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF);
    rng = Random(seed);
  }

  GeneratedMapData generate() {
    final cols = options.cols;
    final rows = options.rows;

    // 1. Khởi tạo ma trận ô di chuyển (false = tường/vật cản, true = đi được)
    final grid = List.generate(cols, (_) => List.filled(rows, true));

    // Viền tường bao ngoài
    for (int c = 0; c < cols; c++) {
      grid[c][0] = false;
      grid[c][rows - 1] = false;
    }
    for (int r = 0; r < rows; r++) {
      grid[0][r] = false;
      grid[cols - 1][r] = false;
    }

    final obstacles = <List<int>>[];

    void addObstacle(int c, int r, int w, int h) {
      if (c < 1 || r < 1 || c + w >= cols || r + h >= rows) return;
      obstacles.add([c, r, w, h]);
      for (int x = c; x < c + w; x++) {
        for (int y = r; y < r + h; y++) {
          grid[x][y] = false;
        }
      }
    }

    // 2. Sinh vật cản theo kiểu địa hình (type)
    switch (options.type) {
      case 'rooms':
        _generateRoomsLayout(cols, rows, addObstacle);
        break;
      case 'ruins':
        _generateRuinsLayout(cols, rows, addObstacle);
        break;
      case 'cavern':
        _generateCavernLayout(cols, rows, grid, obstacles);
        break;
      case 'arena':
      default:
        _generateArenaLayout(cols, rows, addObstacle);
        break;
    }

    // 3. Đặt các vị trí Spawn quan trọng
    final playerSpawn = _findSafeSpawn(grid, cols, rows, preferredZone: 'south_west');
    _clearArea(grid, obstacles, playerSpawn[0], playerSpawn[1], radius: 2);

    final bossSpawn = _findSafeSpawn(grid, cols, rows,
        preferredZone: 'north_east', minDistanceFrom: playerSpawn, minDist: 12);
    _clearArea(grid, obstacles, bossSpawn[0], bossSpawn[1], radius: 2);

    final monsterPortals = _placePortals(grid, cols, rows, options.portalsCount, playerSpawn);
    for (final p in monsterPortals) {
      _clearArea(grid, obstacles, p[0], p[1], radius: 1);
    }

    final buffNodes = _placeBuffNodes(grid, cols, rows, options.buffsCount, playerSpawn, bossSpawn);
    for (final b in buffNodes) {
      _clearArea(grid, obstacles, b[0], b[1], radius: 1);
    }

    // 4. KIỂM TRA TÍNH LIÊN THÔNG ĐỒ THỊ (BFS Flood-Fill)
    // Đảm bảo 100% người chơi, Boss, Cổng quái và Buff nodes đều đến được với nhau
    _ensureGraphConnectivity(grid, obstacles, playerSpawn, [
      bossSpawn,
      ...monsterPortals,
      ...buffNodes,
    ]);

    // 5. Xác định thông tin bản đồ
    final existingCount = _getExistingMapsCount();
    final stage = existingCount + 1;
    final mapName = options.name ?? _generateDefaultName(options.theme, stage);
    final mapId = options.id ?? _slugify(mapName, fallbackPrefix: 'map_${options.theme}_$stage');
    final description = _generateDescription(options.theme, options.type, mapName);

    return GeneratedMapData(
      id: mapId,
      stage: stage,
      name: mapName,
      theme: options.theme,
      type: options.type,
      cols: cols,
      rows: rows,
      tileSize: 32,
      playerSpawn: playerSpawn,
      bossSpawn: bossSpawn,
      monsterPortals: monsterPortals,
      buffNodes: buffNodes,
      obstacles: obstacles,
      walkableGrid: grid,
      seed: seed,
      description: description,
    );
  }

  void _generateArenaLayout(int cols, int rows, void Function(int, int, int, int) addObs) {
    // 4 trụ đối xứng ở 4 góc phần tư (chuẩn đấu trường Action RPG)
    final colMargin = (cols * 0.22).round();
    final rowMargin = (rows * 0.25).round();

    addObs(colMargin, rowMargin, 2, 2);
    addObs(cols - colMargin - 2, rowMargin, 2, 2);
    addObs(colMargin, rows - rowMargin - 2, 2, 2);
    addObs(cols - colMargin - 2, rows - rowMargin - 2, 2, 2);

    // Cột phụ chiến thuật ở 2 cánh
    if (cols >= 36) {
      final midColLeft = (cols * 0.38).round();
      final midColRight = (cols * 0.62).round() - 2;
      final midRow = (rows / 2).round() - 1;

      if (rng.nextBool()) {
        addObs(midColLeft, midRow, 2, 2);
        addObs(midColRight, midRow, 2, 2);
      }
    }
  }

  void _generateRoomsLayout(int cols, int rows, void Function(int, int, int, int) addObs) {
    // Vách ngăn chia phòng ngang và dọc với cửa thông hành lang
    final midCol = cols ~/ 2;
    final midRow = rows ~/ 2;

    // Vách dọc (chừa cửa rộng 4 ô ở giữa và 2 đầu)
    for (int r = 2; r < rows - 2; r++) {
      if (r < midRow - 2 || r > midRow + 2) {
        if (r % 2 == 0) addObs(midCol, r, 1, 2);
      }
    }

    // Vách ngang (chừa lối đi)
    for (int c = 2; c < cols - 2; c++) {
      if (c < midCol - 3 || c > midCol + 3) {
        if (c % 2 == 0) addObs(c, midRow, 2, 1);
      }
    }
  }

  void _generateRuinsLayout(int cols, int rows, void Function(int, int, int, int) addObs) {
    // Rải các khối phế tích hình chữ L hoặc tường ngắn
    final clusterCount = (cols * rows / 110).clamp(4, 10).round();
    for (int i = 0; i < clusterCount; i++) {
      final cx = 3 + rng.nextInt(cols - 8);
      final cy = 3 + rng.nextInt(rows - 8);

      if (rng.nextBool()) {
        addObs(cx, cy, 3, 1);
        addObs(cx, cy + 1, 1, 2);
      } else {
        addObs(cx, cy, 2, 2);
      }
    }
  }

  void _generateCavernLayout(
    int cols,
    int rows,
    List<List<bool>> grid,
    List<List<int>> obstacles,
  ) {
    // Rải các cụm đá tự nhiên
    final clusters = (cols * rows / 120).clamp(5, 12).round();
    for (int i = 0; i < clusters; i++) {
      final cx = 4 + rng.nextInt(cols - 8);
      final cy = 4 + rng.nextInt(rows - 8);
      final w = rng.nextBool() ? 2 : 3;
      final h = rng.nextBool() ? 2 : 3;

      obstacles.add([cx, cy, w, h]);
      for (int x = cx; x < cx + w && x < cols - 1; x++) {
        for (int y = cy; y < cy + h && y < rows - 1; y++) {
          grid[x][y] = false;
        }
      }
    }
  }

  void _clearArea(
    List<List<bool>> grid,
    List<List<int>> obstacles,
    int cx,
    int cy, {
    int radius = 1,
  }) {
    for (int x = cx - radius; x <= cx + radius; x++) {
      for (int y = cy - radius; y <= cy + radius; y++) {
        if (x > 0 && x < grid.length - 1 && y > 0 && y < grid[0].length - 1) {
          grid[x][y] = true;
        }
      }
    }
    // Dọn dẹp chướng ngại vật đè lên vùng cần thoáng
    obstacles.removeWhere((obs) {
      final ox = obs[0];
      final oy = obs[1];
      final ow = obs.length >= 3 ? obs[2] : 2;
      final oh = obs.length >= 4 ? obs[3] : 2;
      return ox < cx + radius &&
          ox + ow > cx - radius &&
          oy < cy + radius &&
          oy + oh > cy - radius;
    });
  }

  List<int> _findSafeSpawn(
    List<List<bool>> grid,
    int cols,
    int rows, {
    required String preferredZone,
    List<int>? minDistanceFrom,
    double minDist = 0,
  }) {
    int startC, endC, startR, endR;
    switch (preferredZone) {
      case 'south_west':
        startC = 3;
        endC = cols ~/ 2 - 2;
        startR = rows ~/ 2 + 1;
        endR = rows - 3;
        break;
      case 'north_east':
        startC = cols ~/ 2 + 2;
        endC = cols - 4;
        startR = 3;
        endR = rows ~/ 2 - 1;
        break;
      default:
        startC = 3;
        endC = cols - 4;
        startR = 3;
        endR = rows - 4;
        break;
    }

    final candidates = <List<int>>[];
    for (int c = startC; c <= endC; c++) {
      for (int r = startR; r <= endR; r++) {
        if (grid[c][r]) {
          if (minDistanceFrom != null) {
            final d = sqrt(pow(c - minDistanceFrom[0], 2) + pow(r - minDistanceFrom[1], 2));
            if (d < minDist) continue;
          }
          candidates.add([c, r]);
        }
      }
    }

    if (candidates.isNotEmpty) {
      return candidates[rng.nextInt(candidates.length)];
    }
    // Fallback nếu không có ô trống
    return [cols ~/ 3, rows ~/ 2];
  }

  List<List<int>> _placePortals(
    List<List<bool>> grid,
    int cols,
    int rows,
    int count,
    List<int> playerSpawn,
  ) {
    final corners = [
      [4, 4],
      [cols - 5, 4],
      [4, rows - 5],
      [cols - 5, rows - 5],
      [cols ~/ 2, 4],
      [cols ~/ 2, rows - 5],
    ];

    final portals = <List<int>>[];
    for (final c in corners) {
      if (portals.length >= count) break;
      final dist = sqrt(pow(c[0] - playerSpawn[0], 2) + pow(c[1] - playerSpawn[1], 2));
      if (dist >= 8) {
        portals.add(c);
      }
    }

    while (portals.length < count) {
      final rx = 3 + rng.nextInt(cols - 6);
      final ry = 3 + rng.nextInt(rows - 6);
      portals.add([rx, ry]);
    }

    return portals;
  }

  List<List<int>> _placeBuffNodes(
    List<List<bool>> grid,
    int cols,
    int rows,
    int count,
    List<int> playerSpawn,
    List<int> bossSpawn,
  ) {
    final nodes = <List<int>>[];
    // Node 1: Gần trung tâm
    nodes.add([cols ~/ 2, rows ~/ 2]);
    // Node 2: Giữa Player và Boss
    nodes.add([((playerSpawn[0] + bossSpawn[0]) / 2).round(), 4]);
    // Node 3: Cánh đối diện
    nodes.add([((playerSpawn[0] + bossSpawn[0]) / 2).round(), rows - 5]);

    while (nodes.length < count) {
      nodes.add([4 + rng.nextInt(cols - 8), 4 + rng.nextInt(rows - 8)]);
    }

    return nodes.sublist(0, count);
  }

  void _ensureGraphConnectivity(
    List<List<bool>> grid,
    List<List<int>> obstacles,
    List<int> start,
    List<List<int>> targets,
  ) {
    final cols = grid.length;
    final rows = grid[0].length;

    Set<int> getReachable(List<int> s) {
      final visited = <int>{};
      final queue = Queue<List<int>>();
      queue.add(s);
      visited.add(s[0] * 1000 + s[1]);

      while (queue.isNotEmpty) {
        final cur = queue.removeFirst();
        final cx = cur[0];
        final cy = cur[1];

        const dirs = [
          [1, 0],
          [-1, 0],
          [0, 1],
          [0, -1]
        ];
        for (final d in dirs) {
          final nx = cx + d[0];
          final ny = cy + d[1];
          if (nx > 0 && nx < cols - 1 && ny > 0 && ny < rows - 1) {
            if (grid[nx][ny]) {
              final key = nx * 1000 + ny;
              if (!visited.contains(key)) {
                visited.add(key);
                queue.add([nx, ny]);
              }
            }
          }
        }
      }
      return visited;
    }

    var reachable = getReachable(start);

    for (final target in targets) {
      final key = target[0] * 1000 + target[1];
      if (!reachable.contains(key)) {
        // Đục thông hành lang rộng 2 ô từ start tới target
        int curX = start[0];
        int curY = start[1];
        final tx = target[0];
        final ty = target[1];

        while (curX != tx || curY != ty) {
          if (curX < tx) curX++;
          if (curX > tx) curX--;
          _clearArea(grid, obstacles, curX, curY, radius: 1);

          if (curY < ty) curY++;
          if (curY > ty) curY--;
          _clearArea(grid, obstacles, curX, curY, radius: 1);
        }
        reachable = getReachable(start);
      }
    }
  }

  int _getExistingMapsCount() {
    try {
      final file = File('assets/data/maps.json');
      if (file.existsSync()) {
        final content = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        final maps = content['maps'] as List?;
        return maps?.length ?? 0;
      }
    } catch (_) {}
    return 9;
  }

  String _generateDefaultName(String theme, int stage) {
    switch (theme) {
      case 'volcanic':
        return 'Hỏa Ngục Dung Nham Tầng $stage';
      case 'ice_arena':
      case 'frost_island':
        return 'Băng Cực Cực Địa Tầng $stage';
      case 'forest':
        return 'Rừng Nguyên Sinh Cổ Tầng $stage';
      case 'cyber':
        return 'Nhà Máy Cơ Giới Tầng $stage';
      case 'neon':
        return 'Đô Thị Ánh Sáng Tầng $stage';
      case 'alien':
        return 'Di Tích Vực Sâu Tầng $stage';
      case 'golden_sanctum':
      default:
        return 'Thần Điện Hoàng Kim Tầng $stage';
    }
  }

  String _generateDescription(String theme, String type, String name) {
    final typeName = type == 'arena'
        ? 'đấu trường chiến thuật mở'
        : type == 'rooms'
            ? 'hầm ngục nhiều phòng liên hoàn'
            : type == 'ruins'
                ? 'phế tích cổ đại đổ nát'
                : 'hang động thạch nhũ tự nhiên';
    return '$name — Bản đồ $typeName với bố cục tối ưu cho thuật toán tìm đường A* và chiến đấu đối kháng.';
  }

  String _slugify(String input, {required String fallbackPrefix}) {
    final lower = input.toLowerCase();
    final slug = lower
        .replaceAll(RegExp(r'[àáạảãâầấậẩẫăằắặẳẵ]'), 'a')
        .replaceAll(RegExp(r'[èéẹẻẽêềếệểễ]'), 'e')
        .replaceAll(RegExp(r'[ìíịỉĩ]'), 'i')
        .replaceAll(RegExp(r'[òóọỏõôồốộổỗơờớợởỡ]'), 'o')
        .replaceAll(RegExp(r'[ùúụủũưừứựửữ]'), 'u')
        .replaceAll(RegExp(r'[ỳýỵỷỹ]'), 'y')
        .replaceAll(RegExp(r'[đ]'), 'd')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return slug.isEmpty ? fallbackPrefix : slug;
  }
}

void _printAsciiPreview(GeneratedMapData map) {
  final cols = map.cols;
  final rows = map.rows;
  final grid = map.walkableGrid;

  // Tạo buffer ký tự
  final canvas = List.generate(rows, (_) => List.filled(cols, '.'));

  // Tường & vật cản
  for (int c = 0; c < cols; c++) {
    for (int r = 0; r < rows; r++) {
      if (!grid[c][r]) {
        canvas[r][c] = '#';
      }
    }
  }

  // Buff nodes ($)
  for (final b in map.buffNodes) {
    if (b[1] < rows && b[0] < cols) canvas[b[1]][b[0]] = '\$';
  }

  // Monster Portals (M)
  for (final p in map.monsterPortals) {
    if (p[1] < rows && p[0] < cols) canvas[p[1]][p[0]] = 'M';
  }

  // Boss Spawn (B)
  if (map.bossSpawn[1] < rows && map.bossSpawn[0] < cols) {
    canvas[map.bossSpawn[1]][map.bossSpawn[0]] = 'B';
  }

  // Player Spawn (P)
  if (map.playerSpawn[1] < rows && map.playerSpawn[0] < cols) {
    canvas[map.playerSpawn[1]][map.playerSpawn[0]] = 'P';
  }

  final border = '-' * cols;
  print('\n\x1B[1;36m🗺️  ASCII PREVIEW BẢN ĐỒ: "${map.name}" (${map.cols}x${map.rows} TILES)\x1B[0m');
  print('Chú thích: \x1B[32mP: Player\x1B[0m | \x1B[31mB: Boss\x1B[0m | \x1B[33mM: Quái Portal\x1B[0m | \x1B[36m\$: Hòm/Buff\x1B[0m | \x1B[90m#: Tường/Cột\x1B[0m | .: Đường đi');
  print('\x1B[90m+$border+\x1B[0m');

  for (int r = 0; r < rows; r++) {
    final sb = StringBuffer('\x1B[90m|\x1B[0m');
    for (int c = 0; c < cols; c++) {
      final ch = canvas[r][c];
      switch (ch) {
        case 'P':
          sb.write('\x1B[1;32mP\x1B[0m');
          break;
        case 'B':
          sb.write('\x1B[1;31mB\x1B[0m');
          break;
        case 'M':
          sb.write('\x1B[1;33mM\x1B[0m');
          break;
        case '\$':
          sb.write('\x1B[1;36m\$\x1B[0m');
          break;
        case '#':
          sb.write('\x1B[90m#\x1B[0m');
          break;
        default:
          sb.write('\x1B[37m.\x1B[0m');
      }
    }
    sb.write('\x1B[90m|\x1B[0m');
    print(sb.toString());
  }
  print('\x1B[90m+$border+\x1B[0m');
}

void _printSummaryTable(GeneratedMapData map, GeneratorOptions options) {
  int walkableCount = 0;
  for (int c = 0; c < map.cols; c++) {
    for (int r = 0; r < map.rows; r++) {
      if (map.walkableGrid[c][r]) walkableCount++;
    }
  }
  final totalTiles = map.cols * map.rows;
  final ratio = (walkableCount / totalTiles * 100).toStringAsFixed(1);

  print('\n\x1B[1;32m📊 THÔNG SỐ BẢN ĐỒ VỪA SINH THÀNH CÔNG:\x1B[0m');
  print('------------------------------------------------------------');
  print('• ID Bản đồ          : \x1B[33m${map.id}\x1B[0m');
  print('• Tên hiển thị       : \x1B[33m${map.name}\x1B[0m');
  print('• Stage / Tầng       : \x1B[36m${map.stage}\x1B[0m');
  print('• Theme / Kiểu       : \x1B[36m${map.theme}\x1B[0m / \x1B[36m${map.type}\x1B[0m');
  print('• Kích thước         : \x1B[36m${map.cols} x ${map.rows}\x1B[0m ô (${map.cols * map.tileSize}x${map.rows * map.tileSize} px)');
  print('• Tọa độ Player      : \x1B[32m${map.playerSpawn}\x1B[0m');
  print('• Tọa độ Boss        : \x1B[31m${map.bossSpawn}\x1B[0m');
  print('• Cổng quái (Portals): \x1B[33m${map.monsterPortals.length} điểm: ${map.monsterPortals}\x1B[0m');
  print('• Buff/Hòm kho báu   : \x1B[36m${map.buffNodes.length} điểm: ${map.buffNodes}\x1B[0m');
  print('• Chướng ngại vật    : ${map.obstacles.length} khối (Pillars/Walls)');
  print('• Độ thoáng sàn      : $ratio% ($walkableCount / $totalTiles ô đi được)');
  print('• Kiểm thử liên thông: \x1B[1;32m✓ PASSED (100% Thông Suốt Cho A* Pathfinder)\x1B[0m');
  print('• Seed ngẫu nhiên    : ${map.seed}');
  print('------------------------------------------------------------');
}

void _saveToJson(GeneratedMapData map, {bool generateImage = true}) {
  final file = File('assets/data/maps.json');
  if (!file.existsSync()) {
    print('\x1B[31m[LỖI] Không tìm thấy file assets/data/maps.json\x1B[0m');
    return;
  }

  // 1. Tự động sinh file ảnh PNG nghệ thuật riêng biệt cho bản đồ
  if (generateImage) {
    final imageRelPath = 'assets/images/maps/${map.id}.png';
    final savedPath = MapImageRenderer.renderAndSave(map, imageRelPath);
    if (savedPath != null) {
      map.imageAsset = imageRelPath;
      print('\x1B[1;32m[IMAGE] ✓ Đã xuất file tranh nền bản đồ độc quyền: $imageRelPath (${map.cols * map.tileSize}x${map.rows * map.tileSize}px)\x1B[0m');
    }
  }

  try {
    final raw = file.readAsStringSync();
    final jsonContent = jsonDecode(raw) as Map<String, dynamic>;
    final mapsList = (jsonContent['maps'] as List).cast<Map<String, dynamic>>();

    // Kiểm tra xem ID map đã tồn tại chưa
    final existingIdx = mapsList.indexWhere((m) => m['id'] == map.id);
    if (existingIdx >= 0) {
      mapsList[existingIdx] = map.toJson();
      print('\x1B[33m[UPDATE] Đã ghi đè cập nhật bản đồ có ID: "${map.id}" trong maps.json\x1B[0m');
    } else {
      mapsList.add(map.toJson());
      print('\x1B[1;32m[SUCCESS] Đã thêm thành công bản đồ mới vào assets/data/maps.json (Tổng: ${mapsList.length} maps)!\x1B[0m');
    }

    final encoder = const JsonEncoder.withIndent('  ');
    file.writeAsStringSync(encoder.convert(jsonContent));
  } catch (e) {
    print('\x1B[31m[LỖI] Không thể lưu file JSON: $e\x1B[0m');
  }
}

/// Tự động sinh/cập nhật ảnh PNG cho toàn bộ các map trong maps.json chưa có ảnh
void _regenerateImagesForAllMaps() {
  final file = File('assets/data/maps.json');
  if (!file.existsSync()) {
    print('\x1B[31m[LỖI] Không tìm thấy file assets/data/maps.json\x1B[0m');
    return;
  }

  final content = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final maps = (content['maps'] as List).cast<Map<String, dynamic>>();

  print('\x1B[36m=== TIẾN HÀNH SINH ẢNH NỀN PNG ĐỘC QUYỀN CHO TOÀN BỘ MAPS ===\x1B[0m');
  int updatedCount = 0;

  for (final m in maps) {
    final id = m['id'] as String;
    final theme = (m['theme'] as String?) ?? 'golden_sanctum';
    final cols = (m['cols'] as num?)?.toInt() ?? 36;
    final rows = (m['rows'] as num?)?.toInt() ?? 24;
    final tileSize = (m['tileSize'] as num?)?.toInt() ?? 32;
    final currentImage = (m['imageAsset'] as String?) ?? '';

    // Nếu map đã có ảnh vẽ tay chất lượng cao riêng (như map-bang.png, map-dao-bang-gia.png, map-rung-cay.png)
    // và file đó đang tồn tại thì giữ nguyên, không ghi đè trừ khi rỗng
    final isCustomOriginal = currentImage.isNotEmpty &&
        File(currentImage).existsSync() &&
        !currentImage.endsWith('$id.png');

    if (isCustomOriginal) {
      print('• Bỏ qua map "$id": Đang dùng tác phẩm gốc ($currentImage)');
      continue;
    }

    final imageRelPath = 'assets/images/maps/$id.png';
    final pSpawn = (m['playerSpawn'] as List).cast<int>();
    final bSpawn = (m['bossSpawn'] as List).cast<int>();
    final portals = ((m['monsterPortals'] as List?) ?? const [])
        .map((e) => (e as List).cast<int>())
        .toList();
    final buffs = ((m['buffNodes'] as List?) ?? const [])
        .map((e) => (e as List).cast<int>())
        .toList();
    final obstacles = ((m['obstacles'] as List?) ?? const [])
        .map((e) => (e as List).cast<int>())
        .toList();

    final data = GeneratedMapData(
      id: id,
      stage: (m['stage'] as num?)?.toInt() ?? 1,
      name: (m['name'] as String?) ?? id,
      theme: theme,
      type: 'arena',
      cols: cols,
      rows: rows,
      tileSize: tileSize,
      playerSpawn: pSpawn,
      bossSpawn: bSpawn,
      monsterPortals: portals,
      buffNodes: buffs,
      obstacles: obstacles,
      walkableGrid: List.generate(cols, (_) => List.filled(rows, true)),
      seed: id.hashCode,
      description: (m['description'] as String?) ?? '',
      imageAsset: imageRelPath,
    );

    final saved = MapImageRenderer.renderAndSave(data, imageRelPath);
    if (saved != null) {
      m['imageAsset'] = imageRelPath;
      updatedCount++;
      print('\x1B[1;32m✓ Sinh thành công ảnh nền: "$id" -> $imageRelPath\x1B[0m');
    }
  }

  final encoder = const JsonEncoder.withIndent('  ');
  file.writeAsStringSync(encoder.convert(content));
  print('\x1B[1;32m[HOÀN TẤT] Đã cập nhật ảnh bản đồ cho $updatedCount màn chơi trong maps.json!\x1B[0m');
}

// =============================================================================
// PROCEDURAL PNG ARTIST & RENDERING ENGINE
// =============================================================================

class RgbColor {
  final int r;
  final int g;
  final int b;
  const RgbColor(this.r, this.g, this.b);
}

class ThemePalette {
  final RgbColor floorBase;
  final RgbColor floorAlt;
  final RgbColor floorBorder;
  final RgbColor floorHighlight;
  final RgbColor veinOuter;
  final RgbColor veinInner;
  final RgbColor wallBase;
  final RgbColor wallTop;
  final RgbColor wallHighlight;
  final RgbColor wallShadow;
  final RgbColor coreGlow;
  final RgbColor playerCrest;
  final RgbColor bossSeal;

  const ThemePalette({
    required this.floorBase,
    required this.floorAlt,
    required this.floorBorder,
    required this.floorHighlight,
    required this.veinOuter,
    required this.veinInner,
    required this.wallBase,
    required this.wallTop,
    required this.wallHighlight,
    required this.wallShadow,
    required this.coreGlow,
    required this.playerCrest,
    required this.bossSeal,
  });

  static ThemePalette forTheme(String theme) {
    switch (theme.toLowerCase()) {
      case 'volcanic':
        return const ThemePalette(
          floorBase: RgbColor(26, 18, 18),
          floorAlt: RgbColor(38, 25, 24),
          floorBorder: RgbColor(14, 9, 9),
          floorHighlight: RgbColor(54, 34, 32),
          veinOuter: RgbColor(230, 65, 0),
          veinInner: RgbColor(255, 215, 60),
          wallBase: RgbColor(34, 22, 20),
          wallTop: RgbColor(56, 34, 30),
          wallHighlight: RgbColor(255, 110, 20),
          wallShadow: RgbColor(12, 6, 6),
          coreGlow: RgbColor(255, 140, 0),
          playerCrest: RgbColor(0, 229, 255),
          bossSeal: RgbColor(255, 30, 0),
        );
      case 'ice_arena':
      case 'frost_island':
      case 'map_bang':
      case 'map_dao_bang_gia':
        return const ThemePalette(
          floorBase: RgbColor(20, 44, 70),
          floorAlt: RgbColor(30, 62, 96),
          floorBorder: RgbColor(12, 28, 48),
          floorHighlight: RgbColor(48, 92, 138),
          veinOuter: RgbColor(0, 190, 230),
          veinInner: RgbColor(200, 245, 255),
          wallBase: RgbColor(16, 36, 60),
          wallTop: RgbColor(36, 76, 116),
          wallHighlight: RgbColor(0, 230, 255),
          wallShadow: RgbColor(8, 18, 32),
          coreGlow: RgbColor(0, 235, 255),
          playerCrest: RgbColor(0, 230, 255),
          bossSeal: RgbColor(0, 140, 255),
        );
      case 'forest':
      case 'nature':
      case 'map_rung_cay':
        return const ThemePalette(
          floorBase: RgbColor(24, 48, 24),
          floorAlt: RgbColor(36, 66, 36),
          floorBorder: RgbColor(16, 32, 16),
          floorHighlight: RgbColor(52, 92, 52),
          veinOuter: RgbColor(80, 50, 28),
          veinInner: RgbColor(0, 230, 118),
          wallBase: RgbColor(28, 44, 26),
          wallTop: RgbColor(46, 78, 40),
          wallHighlight: RgbColor(105, 240, 174),
          wallShadow: RgbColor(12, 20, 10),
          coreGlow: RgbColor(0, 230, 118),
          playerCrest: RgbColor(0, 230, 118),
          bossSeal: RgbColor(255, 87, 34),
        );
      case 'cyber':
      case 'neon':
        return const ThemePalette(
          floorBase: RgbColor(20, 24, 32),
          floorAlt: RgbColor(30, 36, 48),
          floorBorder: RgbColor(12, 14, 18),
          floorHighlight: RgbColor(46, 56, 74),
          veinOuter: RgbColor(0, 200, 240),
          veinInner: RgbColor(255, 0, 128),
          wallBase: RgbColor(24, 28, 38),
          wallTop: RgbColor(40, 48, 64),
          wallHighlight: RgbColor(0, 240, 255),
          wallShadow: RgbColor(10, 12, 16),
          coreGlow: RgbColor(0, 240, 255),
          playerCrest: RgbColor(0, 240, 255),
          bossSeal: RgbColor(255, 0, 128),
        );
      case 'alien':
      case 'space':
        return const ThemePalette(
          floorBase: RgbColor(22, 14, 34),
          floorAlt: RgbColor(34, 22, 52),
          floorBorder: RgbColor(12, 8, 20),
          floorHighlight: RgbColor(52, 34, 78),
          veinOuter: RgbColor(168, 85, 247),
          veinInner: RgbColor(240, 171, 252),
          wallBase: RgbColor(28, 18, 44),
          wallTop: RgbColor(48, 30, 72),
          wallHighlight: RgbColor(217, 70, 239),
          wallShadow: RgbColor(10, 6, 16),
          coreGlow: RgbColor(217, 70, 239),
          playerCrest: RgbColor(192, 132, 252),
          bossSeal: RgbColor(236, 72, 153),
        );
      case 'golden_sanctum':
      default:
        return const ThemePalette(
          floorBase: RgbColor(40, 36, 50),
          floorAlt: RgbColor(54, 48, 66),
          floorBorder: RgbColor(24, 22, 32),
          floorHighlight: RgbColor(76, 68, 92),
          veinOuter: RgbColor(200, 160, 40),
          veinInner: RgbColor(255, 230, 120),
          wallBase: RgbColor(46, 40, 56),
          wallTop: RgbColor(70, 60, 84),
          wallHighlight: RgbColor(255, 215, 0),
          wallShadow: RgbColor(16, 14, 22),
          coreGlow: RgbColor(255, 215, 0),
          playerCrest: RgbColor(255, 215, 0),
          bossSeal: RgbColor(255, 87, 34),
        );
    }
  }
}

class ImageBuffer {
  final int width;
  final int height;
  final Uint8List pixels;

  ImageBuffer(this.width, this.height) : pixels = Uint8List(width * height * 4);

  void setPixel(int x, int y, int r, int g, int b, [int a = 255]) {
    if (x < 0 || x >= width || y < 0 || y >= height) return;
    final idx = (y * width + x) * 4;
    if (a >= 255) {
      pixels[idx] = r.clamp(0, 255);
      pixels[idx + 1] = g.clamp(0, 255);
      pixels[idx + 2] = b.clamp(0, 255);
      pixels[idx + 3] = 255;
    } else if (a > 0) {
      final invA = 255 - a;
      pixels[idx] = ((r * a + pixels[idx] * invA) ~/ 255).clamp(0, 255);
      pixels[idx + 1] = ((g * a + pixels[idx + 1] * invA) ~/ 255).clamp(0, 255);
      pixels[idx + 2] = ((b * a + pixels[idx + 2] * invA) ~/ 255).clamp(0, 255);
      pixels[idx + 3] = max(pixels[idx + 3], a);
    }
  }

  void fillRect(int x, int y, int w, int h, int r, int g, int b, [int a = 255]) {
    final startX = x.clamp(0, width);
    final endX = (x + w).clamp(0, width);
    final startY = y.clamp(0, height);
    final endY = (y + h).clamp(0, height);
    for (int py = startY; py < endY; py++) {
      for (int px = startX; px < endX; px++) {
        setPixel(px, py, r, g, b, a);
      }
    }
  }

  void strokeRect(int x, int y, int w, int h, int r, int g, int b, [int a = 255, int stroke = 1]) {
    fillRect(x, y, w, stroke, r, g, b, a);
    fillRect(x, y + h - stroke, w, stroke, r, g, b, a);
    fillRect(x, y, stroke, h, r, g, b, a);
    fillRect(x + w - stroke, y, stroke, h, r, g, b, a);
  }

  void fillCircle(int cx, int cy, int radius, int r, int g, int b, [int a = 255]) {
    final r2 = radius * radius;
    for (int dy = -radius; dy <= radius; dy++) {
      final y = cy + dy;
      if (y < 0 || y >= height) continue;
      for (int dx = -radius; dx <= radius; dx++) {
        final x = cx + dx;
        if (x < 0 || x >= width) continue;
        if (dx * dx + dy * dy <= r2) {
          setPixel(x, y, r, g, b, a);
        }
      }
    }
  }

  void drawCircle(int cx, int cy, int radius, int strokeWidth, int r, int g, int b, [int a = 255]) {
    final outerR2 = radius * radius;
    final innerR = max(0, radius - strokeWidth);
    final innerR2 = innerR * innerR;
    for (int dy = -radius; dy <= radius; dy++) {
      final y = cy + dy;
      if (y < 0 || y >= height) continue;
      for (int dx = -radius; dx <= radius; dx++) {
        final x = cx + dx;
        if (x < 0 || x >= width) continue;
        final d2 = dx * dx + dy * dy;
        if (d2 <= outerR2 && d2 >= innerR2) {
          setPixel(x, y, r, g, b, a);
        }
      }
    }
  }

  void drawLine(int x0, int y0, int x1, int y1, int stroke, int r, int g, int b, [int a = 255]) {
    int dx = (x1 - x0).abs();
    int dy = (y1 - y0).abs();
    int sx = x0 < x1 ? 1 : -1;
    int sy = y0 < y1 ? 1 : -1;
    int err = dx - dy;

    int curX = x0;
    int curY = y0;

    while (true) {
      if (stroke <= 1) {
        setPixel(curX, curY, r, g, b, a);
      } else {
        final half = stroke ~/ 2;
        fillRect(curX - half, curY - half, stroke, stroke, r, g, b, a);
      }

      if (curX == x1 && curY == y1) break;
      int e2 = 2 * err;
      if (e2 > -dy) {
        err -= dy;
        curX += sx;
      }
      if (e2 < dx) {
        err += dx;
        curY += sy;
      }
    }
  }
}

class MapImageRenderer {
  static String? renderAndSave(GeneratedMapData map, String outputPath) {
    try {
      final tileSize = map.tileSize;
      final width = map.cols * tileSize;
      final height = map.rows * tileSize;
      final buf = ImageBuffer(width, height);
      final rng = Random(map.seed);
      final palette = ThemePalette.forTheme(map.theme);

      // 1. Vẽ nền gạch và hoa văn theo theme
      _renderFloorTiles(buf, map, rng, palette);

      // 2. Vẽ các đường mạch năng lượng / dung nham / dây leo uốn lượn xuyên suốt bản đồ
      _renderEnvironmentalVeins(buf, map, rng, palette);

      // 3. Vẽ tường ranh giới bản đồ (Outer Border)
      _renderBorderWalls(buf, map, palette);

      // 4. Vẽ chướng ngại vật & cột đá (Obstacles) khớp 100% với mapConfig
      _renderObstacles(buf, map, rng, palette);

      // 5. Vẽ Vùng Xuất Phát Người Chơi (Player Spawn Crest)
      _renderPlayerSpawnZone(buf, map, palette);

      // 6. Vẽ Đấu Trường Triệu Hồi Boss (Boss Arena Seal)
      _renderBossSpawnZone(buf, map, palette);

      // 7. Vẽ Cổng Quái Vật (Monster Portals)
      _renderMonsterPortals(buf, map, palette);

      // 8. Vẽ Điểm Buff / Đài Báu Vật (Buff Nodes)
      _renderBuffNodes(buf, map, palette);

      // 9. Mã hóa sang PNG và ghi ra file
      final pngBytes = PngEncoder.encodeRgba(width, height, buf.pixels);
      final outFile = File(outputPath);
      outFile.parent.createSync(recursive: true);
      outFile.writeAsBytesSync(pngBytes);
      return outputPath;
    } catch (e) {
      print('\x1B[31m[LỖI] Không thể sinh ảnh map: $e\x1B[0m');
      return null;
    }
  }

  static void _renderFloorTiles(
    ImageBuffer buf,
    GeneratedMapData map,
    Random rng,
    ThemePalette pal,
  ) {
    final ts = map.tileSize;
    for (int r = 0; r < map.rows; r++) {
      for (int c = 0; c < map.cols; c++) {
        final px = c * ts;
        final py = r * ts;
        final isAlt = (c + r) % 2 == 1;
        final col = isAlt ? pal.floorAlt : pal.floorBase;

        // Đổ màu sàn
        buf.fillRect(px, py, ts, ts, col.r, col.g, col.b);

        // Viền vát cạnh trên & trái tạo khối 3D gạch sàn đá
        buf.drawLine(px, py, px + ts - 1, py, 1, pal.floorHighlight.r, pal.floorHighlight.g, pal.floorHighlight.b, 130);
        buf.drawLine(px, py, px, py + ts - 1, 1, pal.floorHighlight.r, pal.floorHighlight.g, pal.floorHighlight.b, 130);

        // Rãnh chỉ vữa viền gạch dưới & phải
        buf.drawLine(px, py + ts - 1, px + ts - 1, py + ts - 1, 1, pal.floorBorder.r, pal.floorBorder.g, pal.floorBorder.b, 200);
        buf.drawLine(px + ts - 1, py, px + ts - 1, py + ts - 1, 1, pal.floorBorder.r, pal.floorBorder.g, pal.floorBorder.b, 200);

        // Vết rạn nứt tự nhiên trên một số viên gạch (tỷ lệ 16%)
        final randSeed = (c * 19 + r * 37 + map.seed) % 100;
        if (randSeed < 16) {
          final fx = px + (randSeed % 12) + 4;
          final fy = py + ((randSeed * 3) % 12) + 4;
          buf.drawLine(fx, fy, fx + 8, fy + 7, 1, pal.veinOuter.r, pal.veinOuter.g, pal.veinOuter.b, 140);
          buf.drawLine(fx + 8, fy + 7, fx + 16, fy + 12, 1, pal.veinInner.r, pal.veinInner.g, pal.veinInner.b, 180);
        }
      }
    }
  }

  static void _renderEnvironmentalVeins(
    ImageBuffer buf,
    GeneratedMapData map,
    Random rng,
    ThemePalette pal,
  ) {
    final ts = map.tileSize;
    final targets = <List<int>>[];
    targets.add(map.bossSpawn);
    targets.addAll(map.monsterPortals);
    targets.addAll(map.buffNodes);

    final startX = ((map.playerSpawn[0] + 0.5) * ts).round();
    final startY = ((map.playerSpawn[1] + 0.5) * ts).round();

    for (final t in targets) {
      final tx = ((t[0] + 0.5) * ts).round();
      final ty = ((t[1] + 0.5) * ts).round();

      // Uốn lượn qua trung gian
      final midX = ((startX + tx) ~/ 2) + ((t[0] % 5 - 2) * 16);
      final midY = ((startY + ty) ~/ 2) + ((t[1] % 5 - 2) * 16);

      // Lớp ngoài phát sáng (quầng sáng)
      buf.drawLine(startX, startY, midX, midY, 3, pal.veinOuter.r, pal.veinOuter.g, pal.veinOuter.b, 110);
      buf.drawLine(midX, midY, tx, ty, 3, pal.veinOuter.r, pal.veinOuter.g, pal.veinOuter.b, 110);

      // Lõi năng lượng nóng chảy phát quang
      buf.drawLine(startX, startY, midX, midY, 1, pal.veinInner.r, pal.veinInner.g, pal.veinInner.b, 230);
      buf.drawLine(midX, midY, tx, ty, 1, pal.veinInner.r, pal.veinInner.g, pal.veinInner.b, 230);
    }
  }

  static void _renderBorderWalls(
    ImageBuffer buf,
    GeneratedMapData map,
    ThemePalette pal,
  ) {
    final ts = map.tileSize;
    final w = map.cols * ts;
    final h = map.rows * ts;

    // Tường trên & dưới
    for (int c = 0; c < map.cols; c++) {
      buf.fillRect(c * ts, 0, ts, ts, pal.wallBase.r, pal.wallBase.g, pal.wallBase.b);
      buf.fillRect(c * ts, (map.rows - 1) * ts, ts, ts, pal.wallBase.r, pal.wallBase.g, pal.wallBase.b);
    }

    // Tường trái & phải
    for (int r = 0; r < map.rows; r++) {
      buf.fillRect(0, r * ts, ts, ts, pal.wallBase.r, pal.wallBase.g, pal.wallBase.b);
      buf.fillRect((map.cols - 1) * ts, r * ts, ts, ts, pal.wallBase.r, pal.wallBase.g, pal.wallBase.b);
    }

    // Viền bảo vệ bên ngoài
    buf.strokeRect(0, 0, w, h, pal.wallShadow.r, pal.wallShadow.g, pal.wallShadow.b, 255, 3);
    buf.strokeRect(ts, ts, w - ts * 2, h - ts * 2, pal.wallHighlight.r, pal.wallHighlight.g, pal.wallHighlight.b, 140, 1);
  }

  static void _renderObstacles(
    ImageBuffer buf,
    GeneratedMapData map,
    Random rng,
    ThemePalette pal,
  ) {
    final ts = map.tileSize;

    for (final obs in map.obstacles) {
      if (obs.length < 4) continue;
      final ox = obs[0] * ts;
      final oy = obs[1] * ts;
      final ow = obs[2] * ts;
      final oh = obs[3] * ts;

      // 1. Bóng đổ phía dưới và bên phải
      buf.fillRect(ox + 4, oy + 4, ow, oh, 0, 0, 0, 130);

      // 2. Thân khối trụ đá / chướng ngại vật
      buf.fillRect(ox, oy, ow, oh, pal.wallBase.r, pal.wallBase.g, pal.wallBase.b);

      // 3. Mặt trên đỉnh nổi khối 3D (35% chiều cao)
      final topH = (oh * 0.35).round();
      buf.fillRect(ox, oy, ow, topH, pal.wallTop.r, pal.wallTop.g, pal.wallTop.b);

      // 4. Viền đậm khối kiến trúc
      buf.strokeRect(ox, oy, ow, oh, pal.wallShadow.r, pal.wallShadow.g, pal.wallShadow.b, 255, 2);

      // 5. Đường gân sáng phân chia đỉnh và thân trụ
      buf.drawLine(ox + 2, oy + topH, ox + ow - 3, oy + topH, 1, pal.wallHighlight.r, pal.wallHighlight.g, pal.wallHighlight.b, 220);

      // 6. Lõi linh thạch / ấn ký phát sáng tại trung tâm khối trụ
      final cx = ox + ow ~/ 2;
      final cy = oy + oh ~/ 2;
      if (ow >= ts * 1.5 && oh >= ts * 1.5) {
        buf.fillCircle(cx, cy, 7, pal.coreGlow.r, pal.coreGlow.g, pal.coreGlow.b, 240);
        buf.drawCircle(cx, cy, 10, 1, pal.wallHighlight.r, pal.wallHighlight.g, pal.wallHighlight.b, 180);
      }
    }
  }

  static void _renderPlayerSpawnZone(
    ImageBuffer buf,
    GeneratedMapData map,
    ThemePalette pal,
  ) {
    final ts = map.tileSize;
    final cx = ((map.playerSpawn[0] + 0.5) * ts).round();
    final cy = ((map.playerSpawn[1] + 0.5) * ts).round();

    // Vòng hào quang ngoài
    buf.drawCircle(cx, cy, 38, 2, pal.playerCrest.r, pal.playerCrest.g, pal.playerCrest.b, 220);
    // Vòng hào quang trong
    buf.drawCircle(cx, cy, 26, 1, pal.playerCrest.r, pal.playerCrest.g, pal.playerCrest.b, 180);

    // 4 Mũi tên định hướng xuất trận
    buf.drawLine(cx - 32, cy, cx - 18, cy, 2, pal.playerCrest.r, pal.playerCrest.g, pal.playerCrest.b, 240);
    buf.drawLine(cx + 18, cy, cx + 32, cy, 2, pal.playerCrest.r, pal.playerCrest.g, pal.playerCrest.b, 240);
    buf.drawLine(cx, cy - 32, cx, cy - 18, 2, pal.playerCrest.r, pal.playerCrest.g, pal.playerCrest.b, 240);
    buf.drawLine(cx, cy + 18, cx, cy + 32, 2, pal.playerCrest.r, pal.playerCrest.g, pal.playerCrest.b, 240);

    // Điểm tâm sáng
    buf.fillCircle(cx, cy, 6, pal.playerCrest.r, pal.playerCrest.g, pal.playerCrest.b, 255);
  }

  static void _renderBossSpawnZone(
    ImageBuffer buf,
    GeneratedMapData map,
    ThemePalette pal,
  ) {
    final ts = map.tileSize;
    final cx = ((map.bossSpawn[0] + 0.5) * ts).round();
    final cy = ((map.bossSpawn[1] + 0.5) * ts).round();

    // Đấu trường rực lửa / gai nhọn ngoài
    buf.drawCircle(cx, cy, 54, 3, pal.bossSeal.r, pal.bossSeal.g, pal.bossSeal.b, 240);
    buf.drawCircle(cx, cy, 42, 1, pal.bossSeal.r, pal.bossSeal.g, pal.bossSeal.b, 170);

    // 12 Gai nhọn triệu hồi Boss tỏa ra xung quanh
    for (int i = 0; i < 12; i++) {
      final angle = i * (pi / 6);
      final x1 = (cx + cos(angle) * 44).round();
      final y1 = (cy + sin(angle) * 44).round();
      final x2 = (cx + cos(angle) * 58).round();
      final y2 = (cy + sin(angle) * 58).round();
      buf.drawLine(x1, y1, x2, y2, 2, pal.bossSeal.r, pal.bossSeal.g, pal.bossSeal.b, 220);
    }

    // Tâm ấn phong ấn ma thần hình thoi
    buf.drawLine(cx - 14, cy, cx, cy - 14, 2, pal.bossSeal.r, pal.bossSeal.g, pal.bossSeal.b, 255);
    buf.drawLine(cx, cy - 14, cx + 14, cy, 2, pal.bossSeal.r, pal.bossSeal.g, pal.bossSeal.b, 255);
    buf.drawLine(cx + 14, cy, cx, cy + 14, 2, pal.bossSeal.r, pal.bossSeal.g, pal.bossSeal.b, 255);
    buf.drawLine(cx, cy + 14, cx - 14, cy, 2, pal.bossSeal.r, pal.bossSeal.g, pal.bossSeal.b, 255);
    buf.fillCircle(cx, cy, 5, pal.bossSeal.r, pal.bossSeal.g, pal.bossSeal.b, 255);
  }

  static void _renderMonsterPortals(
    ImageBuffer buf,
    GeneratedMapData map,
    ThemePalette pal,
  ) {
    final ts = map.tileSize;
    for (final p in map.monsterPortals) {
      final cx = ((p[0] + 0.5) * ts).round();
      final cy = ((p[1] + 0.5) * ts).round();

      // Vòng xoáy hư không triệu hồi
      buf.drawCircle(cx, cy, 24, 2, pal.veinOuter.r, pal.veinOuter.g, pal.veinOuter.b, 220);
      buf.drawCircle(cx, cy, 18, 1, pal.veinInner.r, pal.veinInner.g, pal.veinInner.b, 190);

      // Lỗ đen trung tâm cổng quái
      buf.fillCircle(cx, cy, 11, 14, 8, 20, 255);
      buf.fillCircle(cx, cy, 4, pal.veinInner.r, pal.veinInner.g, pal.veinInner.b, 240);
    }
  }

  static void _renderBuffNodes(
    ImageBuffer buf,
    GeneratedMapData map,
    ThemePalette pal,
  ) {
    final ts = map.tileSize;
    for (final b in map.buffNodes) {
      final cx = ((b[0] + 0.5) * ts).round();
      final cy = ((b[1] + 0.5) * ts).round();

      // Bệ đài báu vật hoàng kim
      buf.drawCircle(cx, cy, 20, 2, 255, 215, 0, 240);
      buf.drawCircle(cx, cy, 13, 1, 255, 235, 120, 180);

      // Ngôi sao vàng phát quang
      buf.drawLine(cx - 10, cy, cx + 10, cy, 2, 255, 235, 80, 255);
      buf.drawLine(cx, cy - 10, cx, cy + 10, 2, 255, 235, 80, 255);
      buf.fillCircle(cx, cy, 4, 255, 255, 200, 255);
    }
  }
}

class Crc32 {
  static final List<int> _table = List.generate(256, (n) {
    int c = n;
    for (int k = 0; k < 8; k++) {
      if ((c & 1) != 0) {
        c = 0xedb88320 ^ (c >>> 1);
      } else {
        c = c >>> 1;
      }
    }
    return c;
  });

  static int compute(List<int> bytes) {
    int c = 0xffffffff;
    for (int i = 0; i < bytes.length; i++) {
      c = _table[(c ^ bytes[i]) & 0xff] ^ (c >>> 8);
    }
    return (c ^ 0xffffffff) & 0xffffffff;
  }
}

class PngEncoder {
  static Uint8List encodeRgba(int width, int height, Uint8List rgbaPixels) {
    final scanlineSize = 1 + width * 4;
    final rawData = Uint8List(height * scanlineSize);
    for (int y = 0; y < height; y++) {
      final rawOffset = y * scanlineSize;
      rawData[rawOffset] = 0; // Filter: 0 (None)
      final pixelOffset = y * width * 4;
      rawData.setRange(rawOffset + 1, rawOffset + scanlineSize, rgbaPixels, pixelOffset);
    }

    final compressed = zlib.encode(rawData);
    final bb = BytesBuilder();

    // 1. Signature
    bb.add([137, 80, 78, 71, 13, 10, 26, 10]);

    // 2. IHDR
    final ihdrData = ByteData(13)
      ..setUint32(0, width)
      ..setUint32(4, height)
      ..setUint8(8, 8)
      ..setUint8(9, 6)
      ..setUint8(10, 0)
      ..setUint8(11, 0)
      ..setUint8(12, 0);
    _writeChunk(bb, 'IHDR', ihdrData.buffer.asUint8List());

    // 3. IDAT
    _writeChunk(bb, 'IDAT', Uint8List.fromList(compressed));

    // 4. IEND
    _writeChunk(bb, 'IEND', Uint8List(0));

    return bb.toBytes();
  }

  static void _writeChunk(BytesBuilder bb, String type, Uint8List data) {
    final typeBytes = ascii.encode(type);
    final len = ByteData(4)..setUint32(0, data.length);
    bb.add(len.buffer.asUint8List());
    bb.add(typeBytes);
    bb.add(data);

    final crcInput = Uint8List(4 + data.length);
    crcInput.setRange(0, 4, typeBytes);
    crcInput.setRange(4, 4 + data.length, data);
    final crcVal = Crc32.compute(crcInput);

    final crcBytes = ByteData(4)..setUint32(0, crcVal);
    bb.add(crcBytes.buffer.asUint8List());
  }
}
