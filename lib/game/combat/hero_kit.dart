import 'package:flutter/material.dart';

class HeroSkill {
  final String name, description;
  final double cost, cooldown;
  final IconData icon;
  const HeroSkill(
    this.name,
    this.description,
    this.cost,
    this.cooldown,
    this.icon,
  );
}

class HeroKit {
  final double attackRange, attackInterval;
  final bool ranged;
  final Color color;
  final List<HeroSkill> skills;
  const HeroKit(
    this.attackRange,
    this.attackInterval,
    this.ranged,
    this.color,
    this.skills,
  );

  static const kits = {
    'george': HeroKit(65, .5, false, Colors.amber, [
      HeroSkill(
        'Búa Cuồng Phong',
        'Quét tròn quanh người, gây 180% sát thương.',
        25,
        5,
        Icons.cyclone,
      ),
      HeroSkill(
        'Nện Đất',
        'Sóng chấn động phía trước, đẩy lùi và choáng 0,6 giây.',
        35,
        8,
        Icons.landslide,
      ),
      HeroSkill(
        'Cuồng Nộ',
        '8 giây tăng 60% sát thương, 50% tốc chạy và giảm 40% sát thương nhận.',
        40,
        12,
        Icons.whatshot,
      ),
    ]),
    'ranger': HeroKit(330, .55, true, Colors.greenAccent, [
      HeroSkill(
        'Tam Tiễn',
        'Bắn 3 mũi tên hình quạt; mỗi tên gây 75% sát thương.',
        20,
        5,
        Icons.filter_3,
      ),
      HeroSkill(
        'Lùi Bước Đặt Bẫy',
        'Lùi 95px, để lại bẫy tồn tại 4 giây, gây sát thương và trói chân.',
        25,
        7,
        Icons.sports_martial_arts,
      ),
      HeroSkill(
        'Mưa Tên',
        'Báo vùng 0,5 giây, sau đó 4 đợt tên vào vị trí mục tiêu.',
        45,
        14,
        Icons.grain,
      ),
    ]),
    'tanker': HeroKit(60, .75, false, Colors.lightBlueAccent, [
      HeroSkill(
        'Khiên Xung Kích',
        'Đập khiên phía trước, đẩy lùi và choáng 1 giây.',
        20,
        6,
        Icons.shield,
      ),
      HeroSkill(
        'Pháo Đài Thép',
        'Nhận khiên bằng 35% máu tối đa trong 4 giây.',
        35,
        10,
        Icons.security,
      ),
      HeroSkill(
        'Địa Chấn',
        'Báo vùng 0,6 giây rồi gây 230% sát thương, choáng và làm chậm.',
        50,
        16,
        Icons.public,
      ),
    ]),
    'ninja': HeroKit(60, .3, false, Colors.purpleAccent, [
      HeroSkill(
        'Phi Tiêu Xuyên Thấu',
        'Phi tiêu bay 280px, xuyên qua nhiều kẻ địch.',
        20,
        4,
        Icons.star,
      ),
      HeroSkill(
        'Ảnh Bộ',
        'Lướt 100px, tăng tốc và giảm 60% sát thương nhận trong 2 giây.',
        30,
        8,
        Icons.blur_on,
      ),
      HeroSkill(
        'Ảnh Sát',
        'Áp sát mục tiêu trong 180px; gây thêm sát thương nếu máu địch dưới 30%.',
        50,
        14,
        Icons.flash_on,
      ),
    ]),
  };

  static HeroKit forHero(String id) => kits[id] ?? kits['george']!;
  static bool isSpecialized(String id) => kits.containsKey(id);
}
