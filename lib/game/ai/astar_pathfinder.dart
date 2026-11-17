import 'dart:math';
import 'package:flame/components.dart';
import '../../core/constants.dart';

/// Zero-dependency Binary Min-Heap Priority Queue for A* Search.
class MinHeap<T extends Comparable<dynamic>> {
  final List<T> _elements = [];

  bool get isEmpty => _elements.isEmpty;
  bool get isNotEmpty => _elements.isNotEmpty;
  int get length => _elements.length;

  void add(T item) {
    _elements.add(item);
    _bubbleUp(_elements.length - 1);
  }

  T removeFirst() {
    if (_elements.isEmpty) {
      throw StateError('Cannot remove from an empty MinHeap');
    }
    final first = _elements[0];
    final last = _elements.removeLast();
    if (_elements.isNotEmpty) {
      _elements[0] = last;
      _sinkDown(0);
    }
    return first;
  }

  void clear() => _elements.clear();

  void _bubbleUp(int index) {
    var idx = index;
    while (idx > 0) {
      final parentIdx = (idx - 1) >> 1;
      if (_elements[idx].compareTo(_elements[parentIdx]) < 0) {
        final temp = _elements[idx];
        _elements[idx] = _elements[parentIdx];
        _elements[parentIdx] = temp;
        idx = parentIdx;
      } else {
        break;
      }
    }
  }

  void _sinkDown(int index) {
    var idx = index;
    final len = _elements.length;
    while (true) {
      final left = (idx << 1) + 1;
      final right = left + 1;
      var smallest = idx;

      if (left < len && _elements[left].compareTo(_elements[smallest]) < 0) {
        smallest = left;
      }
      if (right < len && _elements[right].compareTo(_elements[smallest]) < 0) {
        smallest = right;
      }
      if (smallest != idx) {
        final temp = _elements[idx];
        _elements[idx] = _elements[smallest];
        _elements[smallest] = temp;
        idx = smallest;
      } else {
        break;
      }
    }
  }
}

/// A* Search node representing a grid tile coordinate.
class PathNode implements Comparable<PathNode> {
  final int col;
  final int row;
  double gCost;
  double hCost;
  PathNode? parent;

  PathNode({
    required this.col,
    required this.row,
    this.gCost = double.infinity,
    this.hCost = 0.0,
    this.parent,
  });

  double get fCost => gCost + hCost;

  @override
  int compareTo(PathNode other) {
    final cmp = fCost.compareTo(other.fCost);
    if (cmp != 0) return cmp;
    // Tie-breaking: favor node with lower heuristic (closer to target)
    return hCost.compareTo(other.hCost);
  }
}

/// High-performance A* Pathfinding Engine for Dungeon Navigation.
class AStarPathfinder {
  static const double tileSize = GameConstants.tileSize; // 32.0
  static const double sqrt2 = 1.4142135623730951;

  /// Converts world coordinates in pixels to grid column and row indices.
  static (int, int) worldToGrid(Vector2 worldPos) {
    final col = (worldPos.x / tileSize).floor();
    final row = (worldPos.y / tileSize).floor();
    return (col, row);
  }

  /// Converts grid cell coordinates to world center position in pixels.
  static Vector2 gridToWorld(int col, int row) {
    return Vector2((col + 0.5) * tileSize, (row + 0.5) * tileSize);
  }

  /// Builds the canonical 36x24 dungeon walkable matrix.
  /// Matches perimeter walls and the 6 stone pillars from DungeonMapComponent.
  static List<List<bool>> buildDungeonWalkableGrid({
    int width = 36,
    int height = 24,
  }) {
    final grid = List.generate(
      width,
      (_) => List.filled(height, true),
    );

    // Perimeter boundary walls
    for (int col = 0; col < width; col++) {
      grid[col][0] = false;
      grid[col][height - 1] = false;
    }
    for (int row = 0; row < height; row++) {
      grid[0][row] = false;
      grid[width - 1][row] = false;
    }

    // 6 stone pillars (each 2x2 tiles)
    const pillars = [
      (8, 6),
      (8, 16),
      (26, 6),
      (26, 16),
      (17, 10),
      (18, 10),
    ];

    for (final (pCol, pRow) in pillars) {
      if (pCol >= 0 && pCol + 1 < width && pRow >= 0 && pRow + 1 < height) {
        grid[pCol][pRow] = false;
        grid[pCol + 1][pRow] = false;
        grid[pCol][pRow + 1] = false;
        grid[pCol + 1][pRow + 1] = false;
      }
    }

    return grid;
  }

  /// Raycast Line-of-Sight check sampling along the segment at intervals <= 8px.
  /// Detects direct obstacle collisions as well as diagonal barrier penetration
  /// across touching corner vertices.
  /// Returns true if the sightline is completely clear of obstacles.
  static bool hasLineOfSight(
    Vector2 start,
    Vector2 target,
    List<List<bool>> walkableGrid,
  ) {
    if (walkableGrid.isEmpty || walkableGrid[0].isEmpty) return false;

    final width = walkableGrid.length;
    final height = walkableGrid[0].length;

    final startCol = (start.x / tileSize).floor();
    final startRow = (start.y / tileSize).floor();
    if (startCol < 0 || startCol >= width || startRow < 0 || startRow >= height) {
      return false;
    }
    if (!walkableGrid[startCol][startRow]) return false;

    final targetCol = (target.x / tileSize).floor();
    final targetRow = (target.y / tileSize).floor();
    if (targetCol < 0 || targetCol >= width || targetRow < 0 || targetRow >= height) {
      return false;
    }
    if (!walkableGrid[targetCol][targetRow]) return false;

    final dist = start.distanceTo(target);
    if (dist < 1.0) return true;

    // Step size <= 8px ensures fine sub-stepping along the ray
    final steps = (dist / 8.0).ceil().clamp(2, 500);
    final dx = (target.x - start.x) / steps;
    final dy = (target.y - start.y) / steps;

    int prevCol = startCol;
    int prevRow = startRow;

    for (int i = 0; i <= steps; i++) {
      final px = start.x + dx * i;
      final py = start.y + dy * i;
      final col = (px / tileSize).floor();
      final row = (py / tileSize).floor();

      if (col < 0 || col >= width || row < 0 || row >= height) return false;
      if (!walkableGrid[col][row]) return false;

      // Diagonal transition check:
      // When a step crosses diagonally between grid cells (c1 != c2 && r1 != r2),
      // verify that both orthogonal neighbors are walkable.
      // If either is blocked, the ray is cutting across an obstacle corner or
      // piercing a diagonal barrier formed by touching corners.
      if (col != prevCol && row != prevRow) {
        if (!walkableGrid[prevCol][row] || !walkableGrid[col][prevRow]) {
          return false;
        }
      }

      prevCol = col;
      prevRow = row;
    }
    return true;
  }

  /// Calculates Octile distance heuristic between two grid coordinates.
  static double _octileDistance(int c1, int r1, int c2, int r2) {
    final dx = (c1 - c2).abs();
    final dy = (r1 - r2).abs();
    final minD = min(dx, dy);
    final maxD = max(dx, dy);
    return (maxD - minD) + sqrt2 * minD;
  }

  /// Finds the closest walkable neighbor tile when target is inside an obstacle.
  static (int, int)? _findNearestWalkable(
    int col,
    int row,
    List<List<bool>> grid,
  ) {
    final width = grid.length;
    final height = grid[0].length;

    for (int radius = 1; radius <= 4; radius++) {
      for (int dc = -radius; dc <= radius; dc++) {
        for (int dr = -radius; dr <= radius; dr++) {
          final nc = col + dc;
          final nr = row + dr;
          if (nc >= 0 && nc < width && nr >= 0 && nr < height) {
            if (grid[nc][nr]) return (nc, nr);
          }
        }
      }
    }
    return null;
  }

  /// Computes optimal collision-free path from [startPos] to [targetPos].
  /// Enforces strict diagonal corner-cutting prevention to prevent hitbox snagging.
  static List<Vector2> findPath(
    Vector2 startPos,
    Vector2 targetPos,
    List<List<bool>> walkableGrid,
  ) {
    if (walkableGrid.isEmpty || walkableGrid[0].isEmpty) {
      return [targetPos.clone()];
    }

    final width = walkableGrid.length;
    final height = walkableGrid[0].length;

    final (startColRaw, startRowRaw) = worldToGrid(startPos);
    var (targetColRaw, targetRowRaw) = worldToGrid(targetPos);

    final startCol = startColRaw.clamp(0, width - 1);
    final startRow = startRowRaw.clamp(0, height - 1);
    var targetCol = targetColRaw.clamp(0, width - 1);
    var targetRow = targetRowRaw.clamp(0, height - 1);

    // If start is in the same cell as target, direct waypoint
    if (startCol == targetCol && startRow == targetRow) {
      return [targetPos.clone()];
    }

    // Fast-path: Unobstructed Line-of-Sight bypass (< 0.02ms)
    // Diagonal adjacency check: if start and target are diagonally adjacent,
    // ensure both orthogonal neighbors are walkable to prevent cutting obstacle corners.
    final isDiagonallyAdjacent =
        (startCol - targetCol).abs() == 1 && (startRow - targetRow).abs() == 1;
    final isDiagonalBlocked = isDiagonallyAdjacent &&
        (!walkableGrid[startCol][targetRow] || !walkableGrid[targetCol][startRow]);

    if (!isDiagonalBlocked && hasLineOfSight(startPos, targetPos, walkableGrid)) {
      return [targetPos.clone()];
    }

    // If target cell is blocked by obstacle, redirect to closest walkable tile
    if (!walkableGrid[targetCol][targetRow]) {
      final nearest = _findNearestWalkable(targetCol, targetRow, walkableGrid);
      if (nearest == null) return [];
      targetCol = nearest.$1;
      targetRow = nearest.$2;
    }

    // If start position is inside an obstacle (e.g. pushed by knockback), find nearest walkable
    var effectiveStartCol = startCol;
    var effectiveStartRow = startRow;
    if (!walkableGrid[startCol][startRow]) {
      final nearestStart = _findNearestWalkable(startCol, startRow, walkableGrid);
      if (nearestStart != null) {
        effectiveStartCol = nearestStart.$1;
        effectiveStartRow = nearestStart.$2;
      }
    }

    final openHeap = MinHeap<PathNode>();
    final gScores = List<double>.filled(width * height, double.infinity);
    final closed = List<bool>.filled(width * height, false);

    int flatIndex(int c, int r) => c * height + r;

    final startNode = PathNode(
      col: effectiveStartCol,
      row: effectiveStartRow,
      gCost: 0.0,
      hCost: _octileDistance(effectiveStartCol, effectiveStartRow, targetCol, targetRow),
    );

    gScores[flatIndex(effectiveStartCol, effectiveStartRow)] = 0.0;
    openHeap.add(startNode);

    PathNode? goalNode;

    // 8 movement directions: 4 orthogonal + 4 diagonal
    const dxs = [-1, 0, 1, -1, 1, -1, 0, 1];
    const dys = [-1, -1, -1, 0, 0, 1, 1, 1];

    while (openHeap.isNotEmpty) {
      final current = openHeap.removeFirst();
      final curIdx = flatIndex(current.col, current.row);

      if (closed[curIdx]) continue;
      closed[curIdx] = true;

      if (current.col == targetCol && current.row == targetRow) {
        goalNode = current;
        break;
      }

      for (int i = 0; i < 8; i++) {
        final dx = dxs[i];
        final dy = dys[i];
        final nc = current.col + dx;
        final nr = current.row + dy;

        // Boundary check
        if (nc < 0 || nc >= width || nr < 0 || nr >= height) continue;
        if (!walkableGrid[nc][nr]) continue;
        if (closed[flatIndex(nc, nr)]) continue;

        // STRICT CORNER-CUTTING PREVENTION:
        // Diagonal transition (dx != 0 && dy != 0) requires BOTH adjacent
        // orthogonal tiles to be clear. If either is blocked, corner is grazed.
        if (dx != 0 && dy != 0) {
          if (!walkableGrid[current.col + dx][current.row] ||
              !walkableGrid[current.col][current.row + dy]) {
            continue; // Prevent cutting across obstacle corner
          }
        }

        final stepCost = (dx != 0 && dy != 0) ? sqrt2 : 1.0;
        final tentativeG = current.gCost + stepCost;
        final nIdx = flatIndex(nc, nr);

        if (tentativeG < gScores[nIdx]) {
          gScores[nIdx] = tentativeG;
          final neighbor = PathNode(
            col: nc,
            row: nr,
            gCost: tentativeG,
            hCost: _octileDistance(nc, nr, targetCol, targetRow),
            parent: current,
          );
          openHeap.add(neighbor);
        }
      }
    }

    if (goalNode == null) return [];

    // Reconstruct waypoints from goal up to start
    final waypoints = <Vector2>[];
    PathNode? curr = goalNode;
    while (curr != null) {
      waypoints.add(gridToWorld(curr.col, curr.row));
      curr = curr.parent;
    }

    final reversed = waypoints.reversed.toList();

    // If first waypoint is very close to start, discard it to avoid stutter
    if (reversed.isNotEmpty && reversed.first.distanceTo(startPos) < 16.0) {
      reversed.removeAt(0);
    }

    // Append exact target position at the end for smooth final approach
    reversed.add(targetPos.clone());
    return reversed;
  }
}
