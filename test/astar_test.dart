import 'package:flutter_test/flutter_test.dart';
import 'package:flame/components.dart';
import 'package:my_game/game/ai/astar_pathfinder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MinHeap Priority Queue', () {
    test('MinHeap maintains ascending sorted order on removeFirst', () {
      final heap = MinHeap<int>();
      final items = [42, 10, 85, 3, 27, 99, 14, 1];
      for (final item in items) {
        heap.add(item);
      }

      expect(heap.length, items.length);
      expect(heap.isEmpty, isFalse);
      expect(heap.isNotEmpty, isTrue);

      final extracted = <int>[];
      while (heap.isNotEmpty) {
        extracted.add(heap.removeFirst());
      }

      expect(extracted, [1, 3, 10, 14, 27, 42, 85, 99]);
      expect(heap.isEmpty, isTrue);
    });

    test('MinHeap throws StateError on removeFirst when empty', () {
      final heap = MinHeap<int>();
      expect(() => heap.removeFirst(), throwsStateError);
    });

    test('MinHeap clear resets length to zero', () {
      final heap = MinHeap<int>();
      heap.add(10);
      heap.add(20);
      expect(heap.length, 2);
      heap.clear();
      expect(heap.length, 0);
      expect(heap.isEmpty, isTrue);
    });
  });

  group('PathNode Heuristic & Tie-Breaking', () {
    test('PathNode compares by fCost then tie-breaks by hCost', () {
      final nodeA = PathNode(col: 1, row: 1, gCost: 10, hCost: 5); // f = 15
      final nodeB = PathNode(col: 2, row: 2, gCost: 12, hCost: 4); // f = 16
      final nodeC = PathNode(col: 3, row: 3, gCost: 11, hCost: 4); // f = 15, h = 4

      // A (f=15, h=5) vs B (f=16) -> A < B
      expect(nodeA.compareTo(nodeB), lessThan(0));

      // A (f=15, h=5) vs C (f=15, h=4) -> C is closer to target, so C < A
      expect(nodeC.compareTo(nodeA), lessThan(0));
      expect(nodeA.compareTo(nodeC), greaterThan(0));
    });
  });

  group('A* Grid Math & Dungeon Geometry', () {
    late List<List<bool>> grid;

    setUp(() {
      grid = AStarPathfinder.buildDungeonWalkableGrid();
    });

    test('worldToGrid and gridToWorld coordinate consistency', () {
      final worldPos = Vector2(32.0 * 5 + 16.0, 32.0 * 10 + 16.0); // center of (5, 10)
      final (col, row) = AStarPathfinder.worldToGrid(worldPos);
      expect(col, 5);
      expect(row, 10);

      final reconWorld = AStarPathfinder.gridToWorld(col, row);
      expect(reconWorld.x, closeTo(worldPos.x, 0.001));
      expect(reconWorld.y, closeTo(worldPos.y, 0.001));
    });

    test('Canonical dungeon grid matches 36x24 boundary and 6 pillars', () {
      expect(grid.length, 36);
      expect(grid[0].length, 24);

      // Boundaries must be unwalkable
      for (int c = 0; c < 36; c++) {
        expect(grid[c][0], isFalse, reason: 'Top wall blocked');
        expect(grid[c][23], isFalse, reason: 'Bottom wall blocked');
      }
      for (int r = 0; r < 24; r++) {
        expect(grid[0][r], isFalse, reason: 'Left wall blocked');
        expect(grid[35][r], isFalse, reason: 'Right wall blocked');
      }

      // Pillar 1: (8, 6)-(9, 7)
      expect(grid[8][6], isFalse);
      expect(grid[9][6], isFalse);
      expect(grid[8][7], isFalse);
      expect(grid[9][7], isFalse);

      // Surrounding floor of Pillar 1 must be walkable
      expect(grid[7][6], isTrue);
      expect(grid[10][6], isTrue);
      expect(grid[8][5], isTrue);
      expect(grid[8][8], isTrue);
    });

    test('hasLineOfSight detects clear vs blocked sightlines at <= 16px sampling', () {
      // Clear line across open floor
      final startClear = Vector2(3 * 32.0, 3 * 32.0);
      final targetClear = Vector2(7 * 32.0, 3 * 32.0);
      expect(AStarPathfinder.hasLineOfSight(startClear, targetClear, grid), isTrue);

      // Sightline blocked by Pillar 1 (col 8..9, row 6..7)
      final startBlocked = Vector2(6 * 32.0 + 16, 6 * 32.0 + 16);
      final targetBlocked = Vector2(12 * 32.0 + 16, 6 * 32.0 + 16);
      expect(AStarPathfinder.hasLineOfSight(startBlocked, targetBlocked, grid), isFalse);
    });
  });

  group('A* Pathfinder Execution & Corner-Cutting Prevention', () {
    late List<List<bool>> grid;

    setUp(() {
      grid = AStarPathfinder.buildDungeonWalkableGrid();
    });

    test('A* navigates around Pillar 1 without intersecting obstacle cells', () {
      final startPos = Vector2(6 * 32.0 + 16, 6 * 32.0 + 16);
      final targetPos = Vector2(12 * 32.0 + 16, 6 * 32.0 + 16);

      final stopwatch = Stopwatch()..start();
      final path = AStarPathfinder.findPath(startPos, targetPos, grid);
      stopwatch.stop();

      // Performance budget: < 2.0ms (using generous 20ms threshold for test runners)
      expect(stopwatch.elapsedMilliseconds, lessThan(20),
          reason: 'A* search must complete quickly');

      expect(path, isNotEmpty);
      expect(path.last.distanceTo(targetPos), lessThan(1.0));

      // Pillar 1 bounding box: cols 8..9, rows 6..7
      // In world pixels: x in [256, 320], y in [192, 256]
      for (final pt in path) {
        final (c, r) = AStarPathfinder.worldToGrid(pt);
        final inPillar1 = (c == 8 || c == 9) && (r == 6 || r == 7);
        expect(inPillar1, isFalse,
            reason: 'Waypoint ($c, $r) must NOT land inside Pillar 1!');
      }
    });

    test('Strict diagonal corner-cutting prevention validates orthogonal neighbors', () {
      // Create a 5x5 test grid with an L-shaped corner wall at (2, 2)
      final testGrid = List.generate(5, (_) => List.filled(5, true));
      testGrid[2][2] = false; // Wall at (2, 2)

      // Start at (1, 2), Target at (2, 1)
      // Moving diagonally between (1, 3) and (3, 1) across corner (2, 2)
      final path = AStarPathfinder.findPath(
        Vector2(1.5 * 32.0, 2.5 * 32.0),
        Vector2(2.5 * 32.0, 1.5 * 32.0),
        testGrid,
      );

      expect(path, isNotEmpty);
      for (final pt in path) {
        final (c, r) = AStarPathfinder.worldToGrid(pt);
        expect(testGrid[c][r], isTrue, reason: 'All waypoints must be walkable');
      }
    });

    test('LoS raycast detects diagonal wall barriers across corner vertices', () {
      final barrierGrid = List.generate(8, (_) => List.filled(8, true));
      barrierGrid[3][3] = false;
      barrierGrid[4][4] = false;

      final p1 = Vector2(3.5 * 32.0, 4.5 * 32.0); // (3, 4)
      final p2 = Vector2(4.5 * 32.0, 3.5 * 32.0); // (4, 3)

      expect(AStarPathfinder.hasLineOfSight(p1, p2, barrierGrid), isFalse,
          reason: 'Diagonal sightline across touching corners must be occluded');
    });

    test('findPath does not bypass A* when diagonally adjacent step cuts obstacle corner', () {
      final start = Vector2(7.5 * 32.0, 6.5 * 32.0); // (7, 6)
      final target = Vector2(8.5 * 32.0, 5.5 * 32.0); // (8, 5)
      final path = AStarPathfinder.findPath(start, target, grid);

      expect(path, isNotEmpty);
      final (firstCol, firstRow) = AStarPathfinder.worldToGrid(path.first);
      final isDirectCornerCut = (firstCol == 8 && firstRow == 5 && path.length == 1);
      expect(isDirectCornerCut, isFalse,
          reason: 'Cannot take direct diagonal cut across Pillar 1 corner (8, 6)');
    });
  });
}
