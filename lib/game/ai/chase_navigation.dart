import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';

import 'astar_pathfinder.dart';

/// Shared chase steering. Samples the *next frame's* actual position so collision
/// rollback counts as a stall, while intentional attack/shooting pauses do not.
class ChaseNavigation {
  // Bound retained maps and footprint variants. Public mutable grids cannot
  // safely use identity alone as a geometry version.
  static final List<_PlanningGridCache> _planningCaches = [];
  @visibleForTesting
  static int debugPlanningGridBuildCount = 0;

  final double repathInterval;
  final Random random;
  final Vector2? halfSize;
  late double _repathTimer;
  List<Vector2> _waypoints = [];
  int _waypointIndex = 0;
  Vector2? _progressPosition;
  double _progressTimer = 0;
  bool _movementRequested = false;
  int _consecutiveStalls = 0;
  double _searchTimer = 0;

  int repathCount = 0;
  int recoveryCount = 0;
  bool get isSearching => _searchTimer > 0;

  ChaseNavigation({this.repathInterval = 0.5, Random? random, this.halfSize})
    : random = random ?? Random() {
    if (!repathInterval.isFinite || repathInterval <= 0) {
      throw ArgumentError.value(repathInterval, 'repathInterval');
    }
    _repathTimer = this.random.nextDouble() * repathInterval;
  }

  void pause() {
    _progressPosition = null;
    _progressTimer = 0;
    _movementRequested = false;
    _waypoints = [];
    _waypointIndex = 0;
    _consecutiveStalls = 0;
    _searchTimer = 0;
  }

  static Vector2 knockbackMovement({
    required Vector2 position,
    required Vector2 direction,
    required double distance,
    required Vector2 halfSize,
    required List<List<bool>> grid,
  }) {
    if (!_validPoint(position) ||
        !_validPoint(direction) ||
        !_validPoint(halfSize) ||
        !distance.isFinite ||
        !_validGrid(grid) ||
        distance <= 0 ||
        direction.length2 == 0) {
      return Vector2.zero();
    }
    final unit = direction.normalized();
    final next = position.clone();
    // Bound even an unexpectedly large caller-provided displacement.
    final limit = min(distance, AStarPathfinder.tileSize * grid.length);
    for (double moved = 0; moved < limit; moved += 4) {
      final candidate = next + unit * min(4.0, limit - moved);
      if (!_footprintIsClear(candidate, halfSize, grid)) {
        break;
      }
      next.setFrom(candidate);
    }
    return next - position;
  }

  Vector2 step({
    required Vector2 position,
    required Vector2 target,
    required List<List<bool>> grid,
    required double speed,
    required double dt,
  }) {
    if (!dt.isFinite ||
        !speed.isFinite ||
        dt <= 0 ||
        speed <= 0 ||
        !_validPoint(position) ||
        !_validPoint(target) ||
        (halfSize != null &&
            (!_validPoint(halfSize!) || halfSize!.x < 0 || halfSize!.y < 0))) {
      pause();
      return Vector2.zero();
    }
    if (grid.isEmpty || grid.first.isEmpty) {
      pause();
      final offset = target - position;
      final distance = offset.length;
      return distance > 0
          ? offset * (min(speed * dt, distance) / distance)
          : Vector2.zero();
    }
    if (!_validGrid(grid)) {
      pause();
      return Vector2.zero();
    }
    _repathTimer -= dt;
    if (_searchTimer > 0) {
      _searchTimer -= dt;
      _progressPosition = position.clone();
      _movementRequested = false;
      return Vector2.zero();
    }

    if (_movementRequested) {
      _progressTimer += dt;
      if (_progressPosition == null ||
          position.distanceToSquared(_progressPosition!) >= 4) {
        _progressPosition = position.clone();
        _progressTimer = 0;
        _consecutiveStalls = 0;
      } else if (_progressTimer >= 1.0) {
        recoveryCount++;
        _consecutiveStalls++;
        _repathTimer = 0;
        _progressTimer = 0;
        if (_consecutiveStalls >= 2) {
          // A new route can still be physically blocked by a large hitbox.
          // Wait in a bounded search state instead of pushing into it forever.
          _searchTimer = repathInterval * 2;
          _waypoints = [];
          _movementRequested = false;
          return Vector2.zero();
        }
      }
    } else {
      _progressPosition = position.clone();
      _progressTimer = 0;
    }

    if (_repathTimer <= 0) {
      final footprint = halfSize;
      final planningGrid = _planningGrid(grid, footprint);
      _waypoints = AStarPathfinder.findPath(
        position,
        target,
        planningGrid,
        useLineOfSightShortcut: footprint == null,
      );
      _waypointIndex = 0;
      // A periodic search may include the current cell center behind us.
      // Resume at the furthest safely visible waypoint instead of backtracking
      // to that center on every refresh (especially at large frame deltas).
      var foundVisibleWaypoint = false;
      for (int i = _waypoints.length - 1; i >= 0; i--) {
        if (grid.isEmpty || _segmentIsClear(position, _waypoints[i], grid)) {
          _waypointIndex = i;
          foundVisibleWaypoint = true;
          break;
        }
      }
      if (!foundVisibleWaypoint && _waypoints.isNotEmpty) {
        // Point-sized A* can omit a nearby cell center even though the body
        // must reach it before turning around a pillar.
        final (col, row) = AStarPathfinder.worldToGrid(position);
        final center = AStarPathfinder.gridToWorld(col, row);
        if (_segmentIsClear(position, center, grid)) {
          _waypoints.insert(0, center);
        }
      }
      repathCount++;
      _repathTimer = repathInterval;
    }

    // Spend at most this frame's travel budget; never skip a corner or move
    // beyond a waypoint. Do not replace the final safe waypoint with a live
    // target that may have moved behind a wall since the previous search.
    var remaining = speed * dt;
    final next = position.clone();
    var wantsMovement = false;
    while (_waypointIndex < _waypoints.length && remaining > 0) {
      final waypoint = _waypoints[_waypointIndex];
      final offset = waypoint - next;
      final distance = offset.length;
      if (distance <= 0.001) {
        _waypointIndex++;
        continue;
      }
      final travel = min(remaining, distance);
      wantsMovement = true;
      final candidate = next + offset * (travel / distance);
      if (grid.isNotEmpty && !_segmentIsClear(next, candidate, grid)) {
        break;
      }
      next.setFrom(candidate);
      remaining -= travel;
      if (travel >= distance) _waypointIndex++;
      // Collision sees one straight segment per update, not the intermediate
      // positions of a multi-corner route.
      break;
    }
    final movement = next - position;
    _movementRequested = wantsMovement;
    return movement;
  }

  static bool _footprintIsClear(
    Vector2 center,
    Vector2 halfSize,
    List<List<bool>> grid,
  ) {
    if (!_validPoint(center) ||
        !_validPoint(halfSize) ||
        halfSize.x < 0 ||
        halfSize.y < 0) {
      return false;
    }
    final (left, top) = AStarPathfinder.worldToGrid(center - halfSize);
    final (right, bottom) = AStarPathfinder.worldToGrid(center + halfSize);
    if (left < 0 ||
        right >= grid.length ||
        top < 0 ||
        bottom >= grid[0].length) {
      return false;
    }
    for (int col = left; col <= right; col++) {
      for (int row = top; row <= bottom; row++) {
        if (!grid[col][row]) return false;
      }
    }
    return true;
  }

  static List<List<bool>> _planningGrid(
    List<List<bool>> grid,
    Vector2? footprint,
  ) {
    final halfTile = AStarPathfinder.tileSize / 2;
    // At tile centers a body strictly smaller than one tile touches exactly
    // that cell. The source is already the exact planning grid in this case.
    if (footprint == null ||
        (footprint.x >= 0 &&
            footprint.x < halfTile &&
            footprint.y >= 0 &&
            footprint.y < halfTile)) {
      return grid;
    }
    final index = _planningCaches.indexWhere(
      (entry) => identical(entry.source, grid),
    );
    final cache = index < 0
        ? _PlanningGridCache(grid)
        : _planningCaches.removeAt(index);
    _planningCaches.add(cache);
    if (_planningCaches.length > 4) _planningCaches.removeAt(0);
    if (!cache.matchesSource()) {
      cache.snapshot = [for (final column in grid) List<bool>.of(column)];
      cache.footprints.clear();
    }
    final key = (footprint.x, footprint.y);
    final existing = cache.footprints[key];
    if (existing != null) return existing;
    final result = List<List<bool>>.unmodifiable([
      for (var col = 0; col < grid.length; col++)
        List<bool>.unmodifiable([
          for (var row = 0; row < grid[col].length; row++)
            _footprintIsClear(
              AStarPathfinder.gridToWorld(col, row),
              footprint,
              grid,
            ),
        ]),
    ]);
    if (cache.footprints.length >= 8) {
      cache.footprints.remove(cache.footprints.keys.first);
    }
    cache.footprints[key] = result;
    assert(() {
      debugPlanningGridBuildCount++;
      return true;
    }());
    return result;
  }

  /// Tile-center clearance grid, cached with exact mutable-source validation.
  static List<List<bool>> clearanceGrid(
    List<List<bool>> grid,
    Vector2 halfSize,
  ) =>
      _validGrid(grid) &&
          _validPoint(halfSize) &&
          halfSize.x >= 0 &&
          halfSize.y >= 0
      ? _planningGrid(grid, halfSize)
      : const [];

  static bool isBodyPathClear({
    required Vector2 start,
    required Vector2 end,
    required Vector2 halfSize,
    required List<List<bool>> grid,
  }) {
    if (!_validGrid(grid) ||
        !_validPoint(start) ||
        !_validPoint(end) ||
        !_validPoint(halfSize) ||
        halfSize.x < 0 ||
        halfSize.y < 0) {
      return false;
    }
    final distance = start.distanceTo(end);
    // Reject outside points before allocating a potentially unbounded sweep.
    if (!_footprintIsClear(start, halfSize, grid) ||
        !_footprintIsClear(end, halfSize, grid)) {
      return false;
    }
    final steps = max(1, (distance / 4).ceil());
    for (int i = 0; i <= steps; i++) {
      if (!_footprintIsClear(
        start + (end - start) * (i / steps),
        halfSize,
        grid,
      )) {
        return false;
      }
    }
    return true;
  }

  static bool _validPoint(Vector2 value) =>
      value.x.isFinite && value.y.isFinite;

  static bool _validGrid(List<List<bool>> grid) =>
      grid.isNotEmpty &&
      grid.first.isNotEmpty &&
      grid.every((column) => column.length == grid.first.length);

  bool _segmentIsClear(Vector2 start, Vector2 end, List<List<bool>> grid) {
    final footprint = halfSize;
    if (footprint == null) {
      return AStarPathfinder.hasLineOfSight(start, end, grid);
    }
    final steps = max(1, (start.distanceTo(end) / 4).ceil());
    for (int i = 0; i <= steps; i++) {
      final center = start + (end - start) * (i / steps);
      if (!_footprintIsClear(center, footprint, grid)) {
        return false;
      }
    }
    return true;
  }
}

class _PlanningGridCache {
  final List<List<bool>> source;
  List<List<bool>> snapshot = const [];
  final Map<(double, double), List<List<bool>>> footprints = {};

  _PlanningGridCache(this.source);

  bool matchesSource() {
    if (snapshot.length != source.length) return false;
    for (var col = 0; col < source.length; col++) {
      final current = source[col];
      final previous = snapshot[col];
      if (previous.length != current.length) return false;
      for (var row = 0; row < current.length; row++) {
        if (previous[row] != current[row]) return false;
      }
    }
    return true;
  }
}
