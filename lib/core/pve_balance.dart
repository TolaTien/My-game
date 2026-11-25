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
    return 1.0 + (floor - 1) * 0.30;
  }

  static double zombieMaxHp(int floor) => 60.0 * enemyScale(floor);

  static double zombieDamage(int floor) {
    _validateFloor(floor);
    return 12.0 * (1.0 + (floor - 1) * .25);
  }

  static double skeletonMaxHp(int floor) => 45.0 * enemyScale(floor);

  static double bossMaxHp(int floor) {
    _validateFloor(floor);
    return 600.0 * (1.0 + (floor - 1) * 0.35);
  }

  static int floorCompletionGold(int clearedFloor) {
    _validateFloor(clearedFloor);
    return 200 * clearedFloor;
  }
}
