/// Existing PvE spawn and floor-completion values, without balance changes.
class PveBalance {
  PveBalance._();

  static void _validateFloor(int floor) {
    if (floor < 1) {
      throw RangeError.range(floor, 1, null, 'floor');
    }
  }

  static double enemyScale(int floor) {
    _validateFloor(floor);
    return 1.0 + (floor - 1) * 0.2;
  }

  static double zombieMaxHp(int floor) => 60.0 * enemyScale(floor);

  static double zombieDamage(int floor) => 10.0 * enemyScale(floor);

  static double skeletonMaxHp(int floor) => 45.0 * enemyScale(floor);

  static double bossMaxHp(int floor) {
    _validateFloor(floor);
    return floor == 1 ? 600.0 : 500.0 * (1.0 + (floor - 1) * 0.25);
  }

  /// The existing reward is indexed by the floor entered, not the floor cleared.
  static int floorCompletionGold(int destinationFloor) {
    _validateFloor(destinationFloor);
    return 50 * destinationFloor;
  }
}
