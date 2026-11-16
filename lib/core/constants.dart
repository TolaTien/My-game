import 'package:flutter/material.dart';

class GameConstants {
  static const double tileSize = 32.0;

  // George Stats
  static const double playerBaseSpeed = 160.0;
  static const double playerMaxHp = 100.0;
  static const double playerMaxKi = 100.0;
  static const double playerBaseDamage = 20.0;

  // Economy
  static const int goldPerCoinPickup = 1000;
  static const int heroUnlockPrice = 100;
}

class GameColors {
  static const Color background = Color(0xFF14141E);
  static const Color floorLight = Color(0xFF2C2C3E);
  static const Color floorDark = Color(0xFF242434);
  static const Color wall = Color(0xFF4A4A68);
  static const Color wallTop = Color(0xFF6B6B8E);

  // HUD
  static const Color hpBar = Color(0xFFE53935);
  static const Color kiBar = Color(0xFF1E88E5);
  static const Color expBar = Color(0xFFFFB300);
  static const Color gold = Color(0xFFFFD700);
}
