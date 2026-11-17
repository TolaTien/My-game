import 'package:flutter/material.dart';

/// Cosmetic palettes shared by the lobby and combat renderer.
class HeroSkinStyle {
  final String heroId;
  final String name;
  final Color color;
  const HeroSkinStyle(this.heroId, this.name, this.color);

  static const styles = <String, HeroSkinStyle>{
    'skin_george_gold': HeroSkinStyle(
      'george',
      'George Hoàng Kim',
      Color(0xFFFFD700),
    ),
    'skin_ranger_shadow': HeroSkinStyle(
      'ranger',
      'Ranger Bóng Đêm',
      Color(0xFF7E57C2),
    ),
    'skin_tanker_magma': HeroSkinStyle(
      'tanker',
      'Hiệp Sĩ Dung Nham',
      Color(0xFFFF3D00),
    ),
    'skin_ninja_thunder': HeroSkinStyle(
      'ninja',
      'Ninja Lôi Thần',
      Color(0xFF651FFF),
    ),
    'skin_kaelen_emperor': HeroSkinStyle(
      'kaelen',
      'Kaelen Lôi Đế Hoàng Kim',
      Color(0xFF00E5FF),
    ),
  };

  static HeroSkinStyle? resolve(String heroId, String? skinId) {
    final style = styles[skinId];
    return style?.heroId == heroId ? style : null;
  }

  // A luminance palette preserves detail and transparency in existing sprites.
  ColorFilter get filter => ColorFilter.matrix([
    .2126 * color.r,
    .7152 * color.r,
    .0722 * color.r,
    0,
    color.r * 24,
    .2126 * color.g,
    .7152 * color.g,
    .0722 * color.g,
    0,
    color.g * 24,
    .2126 * color.b,
    .7152 * color.b,
    .0722 * color.b,
    0,
    color.b * 24,
    0,
    0,
    0,
    1,
    0,
  ]);
}
