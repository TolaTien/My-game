import 'package:flutter/material.dart';

import '../models/player_profile.dart';
import '../services/player_storage.dart';
import '../core/constants.dart';

class ShopDialog extends StatefulWidget {
  const ShopDialog({super.key});

  @override
  State<ShopDialog> createState() => _ShopDialogState();
}

class _ShopDialogState extends State<ShopDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showNotification(String message, {bool isSuccess = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: isSuccess
            ? Colors.green.shade800
            : Colors.red.shade800,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlayerProfile>(
      valueListenable: PlayerStorage.profileNotifier,
      builder: (context, profile, _) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 14,
          ),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 760, maxHeight: 420),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1B192E), Color(0xFF100E1C)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.amberAccent.withValues(alpha: 0.5),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 24,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Column(
              children: [
                // 1. THANH TIÊU ĐỀ & TIỀN TỆ
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.storefront_rounded,
                        color: Colors.amberAccent,
                        size: 26,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'CỬA HÀNG VẬT PHẨM',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                          color: Colors.amberAccent,
                        ),
                      ),
                      const Spacer(),

                      // Số dư Xu (1 Xu = 1000 Vàng)
                      InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () async {
                          final ok = await PlayerStorage.convertXuToGold(1);
                          if (ok) {
                            _showNotification(
                              'Đã đổi 1 Xu ➔ +1.000 Vàng thành công!',
                            );
                          } else {
                            _showNotification(
                              'Không đủ Xu để đổi (1 Xu = 1.000 Vàng)!',
                              isSuccess: false,
                            );
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orangeAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.orangeAccent),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.currency_exchange_rounded,
                                color: Colors.orangeAccent,
                                size: 15,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '${profile.xu} XU (Đổi 1K Vàng)',
                                style: const TextStyle(
                                  color: Colors.orangeAccent,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Số dư Vàng
                      _CurrencyBadge(
                        icon: Icons.monetization_on_rounded,
                        color: Colors.amberAccent,
                        value: profile.gold,
                      ),
                      const SizedBox(width: 12),

                      // Nút đóng
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white70,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),

                // 2. TAB SELECTOR
                Container(
                  height: 38,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicator: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFB300), Color(0xFFFF8F00)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    labelColor: Colors.black87,
                    unselectedLabelColor: Colors.white70,
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      letterSpacing: 1,
                    ),
                    tabs: const [
                      Tab(text: 'NHÂN VẬT'),
                      Tab(text: 'TRỢ THỦ AI'),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // 3. NỘI DUNG TỪNG TAB
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // TAB 1: NHÂN VẬT
                      _buildHeroesTab(profile),

                      // TAB 2: TRỢ THỦ AI
                      _buildCompanionsTab(profile),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- TAB 1: NHÂN VẬT (BẬC TƯỚNG & GIÁ VÀNG) ---
  Widget _buildHeroesTab(PlayerProfile profile) {
    final heroes = [
      // === 4 NHÂN VẬT ĐẶC QUYỀN (CUSTOM HEROES) ===
      _HeroItem(
        id: 'nova_blade',
        name: 'Nova Blade',
        subtitle: 'Chiến Binh Ánh Sáng',
        role: 'ĐẤU SĨ / CƠ ĐỘNG',
        description: 'Song kiếm năng lượng cực quang, lướt bóng hư không, bộc phá lượng tử diện rộng.',
        color: const Color(0xFF00E5FF),
        icon: Icons.electric_bolt_rounded,
        portraitAsset: 'assets/images/heroes/nova/nova_portrait.png',
        price: 6000,
      ),
      _HeroItem(
        id: 'shadow_01',
        name: 'Shadow (SHADOW-01)',
        subtitle: 'Sát Thủ Hư Không',
        role: 'SÁT THỦ / HƯ KHÔNG',
        description:
            'Plasma xuyên thấu, lướt bóng hư không, xoay bão dao găm bạo kích.',
        color: const Color(0xFF9C27B0),
        icon: Icons.nights_stay_rounded,
        portraitAsset: 'assets/images/heroes/shadow_01_portrait.png',
        price: 6000,
      ),
      _HeroItem(
        id: 'ember_02',
        name: 'Ember (EMBER-02)',
        subtitle: 'Phù Thủy Hỏa Cầu',
        role: 'PHÁP SƯ / HỎA LỰC',
        description: 'Hỏa cầu nổ diện rộng, cột lửa ma pháp thiêu đốt, thái dương bộc phá hủy diệt.',
        color: const Color(0xFFFF5722),
        icon: Icons.local_fire_department_rounded,
        portraitAsset: 'assets/images/heroes/ember/ember.png',
        price: 6500,
      ),

      // === 4 NHÂN VẬT HỆ THỐNG (SYSTEM HEROES) ===
      _HeroItem(
        id: 'george',
        name: 'George',
        subtitle: 'Chiến Binh Búa',
        role: 'CẬN CHIẾN / TANKER',
        description: 'Vung búa cuồng phong, nện đất diện rộng, máu cực trâu.',
        color: const Color(0xFFFF5722),
        icon: Icons.shield_sharp,
        portraitAsset: 'assets/images/heroes/george_portrait.png',
        price: 0,
      ),
      _HeroItem(
        id: 'ranger',
        name: 'Xạ Thủ Ranger',
        subtitle: 'Cung Thủ Tầm Xa',
        role: 'TẦM XA / CƠ ĐỘNG',
        description:
            'Bắn tên ánh sáng xuyên giáp, tốc độ lướt thả diều kiting.',
        color: const Color(0xFF00E676),
        icon: Icons.gps_fixed_rounded,
        portraitAsset: 'assets/images/heroes/ranger_portrait.png',
        price: 4000,
      ),
      _HeroItem(
        id: 'tanker',
        name: 'Hiệp Sĩ Tanker',
        subtitle: 'Hộ Vệ Hoàng Gia',
        role: 'PHÒNG THỦ / PHẢN ĐÒN',
        description:
            'Khiên hộ mệnh hấp thụ sát thương, khóa đòn tấn công quái.',
        color: const Color(0xFF00B0FF),
        icon: Icons.security_rounded,
        portraitAsset: 'assets/images/heroes/tanker_portrait.png',
        price: 4000,
      ),
      _HeroItem(
        id: 'ninja',
        name: 'Ninja Sát Thủ',
        subtitle: 'Bóng Đêm Hắc Ám',
        role: 'CHÍ MẠNG / ÁM SÁT',
        description:
            'Phi tiêu lôi điện, lướt tàng hình, sát thương bạo kích đỉnh cao.',
        color: const Color(0xFFAB47BC),
        icon: Icons.flash_on_rounded,
        portraitAsset: 'assets/images/heroes/ninja_portrait.png',
        price: 4500,
      ),
    ];

    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: heroes.length,
      itemBuilder: (context, index) {
        final hero = heroes[index];
        final isUnlocked = profile.unlockedHeroIds.contains(hero.id);
        final isSelected = profile.selectedHeroId == hero.id;

        return Container(
          width: 165,
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF232038),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? Colors.amberAccent
                  : isUnlocked
                  ? Colors.white24
                  : Colors.white12,
              width: isSelected ? 2.5 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.amberAccent.withValues(alpha: 0.3),
                      blurRadius: 10,
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Icon / Portrait Avatar nhân vật
              Container(
                height: 70,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: hero.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: hero.color.withValues(alpha: 0.5)),
                ),
                child: hero.portraitAsset != null
                    ? Image.asset(
                        hero.portraitAsset!,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.none,
                        errorBuilder: (_, _, _) => Center(
                          child: Icon(hero.icon, color: hero.color, size: 40),
                        ),
                      )
                    : Center(
                        child: Icon(hero.icon, color: hero.color, size: 40),
                      ),
              ),
              const SizedBox(height: 6),

              // Tên nhân vật + Cấp độ 1-100
              Row(
                children: [
                  Expanded(
                    child: Text(
                      hero.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12.5,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amberAccent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Lv.${profile.getHeroLevel(hero.id)}/100',
                      style: const TextStyle(
                        color: Colors.amberAccent,
                        fontWeight: FontWeight.w900,
                        fontSize: 9.5,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                hero.role,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 9,
                  color: hero.color,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),

              // Mô tả ngắn
              Expanded(
                child: Text(
                  hero.description,
                  style: const TextStyle(
                    fontSize: 9.5,
                    color: Colors.white60,
                    height: 1.2,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Nút hành động
              if (isSelected) ...[
                Container(
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.greenAccent),
                  ),
                  child: const Center(
                    child: Text(
                      'ĐANG CHỌN',
                      style: TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ] else if (isUnlocked) ...[
                SizedBox(
                  height: 32,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3F51B5),
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () async {
                      await PlayerStorage.selectHero(hero.id);
                      _showNotification('Đã chọn ${hero.name}!');
                    },
                    child: const Text(
                      'CHỌN',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ] else ...[
                SizedBox(
                  height: 32,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amberAccent,
                      foregroundColor: Colors.black87,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () async {
                      final price = hero.price ?? GameConstants.heroUnlockPrice;
                      if (profile.gold < price) {
                        _showNotification(
                          'Bạn không đủ Vàng! Cần $price Vàng để mở khóa.',
                          isSuccess: false,
                        );
                        return;
                      }
                      final success = await PlayerStorage.unlockHero(
                        hero.id,
                        price,
                      );
                      if (success) {
                        _showNotification(
                          'Mở khóa thành công ${hero.name} (-$price Vàng)!',
                        );
                      }
                    },
                    icon: const Icon(Icons.monetization_on_rounded, size: 14),
                    label: Text(
                      '${hero.price ?? GameConstants.heroUnlockPrice} VÀNG',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // --- TAB 2: TRỢ THỦ AI (COMPANIONS) ---
  Widget _buildCompanionsTab(PlayerProfile profile) {
    final companions = [
      _CompanionItem(
        id: 'comp_attack',
        name: 'Trợ Thủ Công Kích',
        tag: 'TIER 1 • ATTACK DRONE',
        description:
            'Tự động phát hiện và phóng tia plasma năng lượng vào quái.',
        price: 2000,
        color: const Color(0xFFFF5252),
        icon: Icons.rocket_launch_rounded,
      ),
      _CompanionItem(
        id: 'comp_defense',
        name: 'Trợ Thủ Phòng Ngự',
        tag: 'TIER 1 • SHIELD DRONE',
        description: 'Tạo lồng bảo hộ năng lượng giảm 30% sát thương nhận vào.',
        price: 2500,
        color: const Color(0xFF448AFF),
        icon: Icons.shield_rounded,
      ),
      _CompanionItem(
        id: 'comp_control',
        name: 'Trợ Thủ Khống Chế',
        tag: 'TIER 1 • FROST DRONE',
        description:
            'Tỏa aura băng tuyết làm chậm 40% tốc chạy của toàn bộ quái vật.',
        price: 3000,
        color: const Color(0xFF18FFFF),
        icon: Icons.ac_unit_rounded,
      ),
      _CompanionItem(
        id: 'cyber_drone',
        name: 'Cyber Drone (PIXEL-01)',
        tag: 'TIER 2 • SUPPORT (ASSET 1 & 2)',
        description: 'Drone sừng trắng mắt lam: Bắn đạn Plasma, hồi máu đồng minh & bật Khiên Cầu Năng Lượng.',
        price: 4000,
        color: const Color(0xFF00E5FF),
        icon: Icons.smart_toy_rounded,
        spriteAsset: 'assets/images/companions/cyber_drone.png',
      ),
      _CompanionItem(
        id: 'luna_fox',
        name: 'Hồ Ly Luna',
        tag: 'TIER 2 • PET FOX (ASSET 2)',
        description: 'Linh thú Hồ Ly trắng xanh: Bắn cầu linh lực băng lam làm chậm quái và hồi Ki.',
        price: 4500,
        color: const Color(0xFF80D8FF),
        icon: Icons.pets_rounded,
        spriteAsset: 'assets/images/companions/luna_fox.png',
      ),
      _CompanionItem(
        id: 'orbit_03',
        name: 'ORBIT-03 Drone',
        tag: 'TIER 2 • MECH SPHERE (ASSET 2)',
        description: 'Cầu cơ khí Hoàng Kim bắn tia laser năng lượng tốc độ cao liên hoàn.',
        price: 5000,
        color: const Color(0xFFFFAB00),
        icon: Icons.radar_rounded,
        spriteAsset: 'assets/images/companions/orbit_03.png',
      ),
      _CompanionItem(
        id: 'aegis_x9',
        name: 'Aegis-X9 Lôi Từ',
        tag: 'TIER 3 • HUYỀN THOẠI (ASSET 4)',
        description: 'Lõi bát diện Hoàng Kim: Hút vàng 120px, bắn tia Laser & mở Trường Trọng Lực + Khiên Vàng.',
        price: 8000,
        color: const Color(0xFFFFD700),
        icon: Icons.auto_awesome_rounded,
        spriteAsset: 'assets/images/companions/aegis_x9.png',
      ),
      _CompanionItem(
        id: 'pyro_frost_dragon',
        name: 'Pyro-Frost Dragon',
        tag: 'TIER 3 • HUYỀN THOẠI (ASSET 3)',
        description: 'Phun lửa & tuyết xen kẽ; kích hoạt Hơi Thở Bão Tố đóng băng kẻ địch và buff khiên lửa.',
        price: 10000,
        color: const Color(0xFFFF5252),
        icon: Icons.whatshot_rounded,
        spriteAsset: 'assets/images/companions/pyro_frost_dragon.png',
      ),
    ];

    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: companions.length,
      itemBuilder: (context, index) {
        final comp = companions[index];
        final isUnlocked = profile.unlockedCompanionIds.contains(comp.id);
        final isEquipped = profile.selectedCompanionId == comp.id;

        return Container(
          width: 190,
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF232038),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isEquipped
                  ? Colors.amberAccent
                  : isUnlocked
                  ? Colors.cyanAccent.withValues(alpha: 0.5)
                  : Colors.white12,
              width: isEquipped ? 2 : 1,
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 70,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: comp.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: comp.color.withValues(alpha: 0.4)),
                ),
                child: comp.spriteAsset != null
                    ? Image.asset(
                        comp.spriteAsset!,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.none,
                        errorBuilder: (_, _, _) => Center(
                          child: Icon(comp.icon, color: comp.color, size: 40),
                        ),
                      )
                    : Center(
                        child: Icon(comp.icon, color: comp.color, size: 40),
                      ),
              ),
              const SizedBox(height: 8),
              Text(
                comp.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  color: Colors.white,
                ),
                maxLines: 1,
              ),
              Text(
                comp.tag,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 9,
                  color: comp.color,
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Text(
                  comp.description,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white60,
                    height: 1.3,
                  ),
                  maxLines: 3,
                ),
              ),
              if (isEquipped) ...[
                SizedBox(
                  height: 32,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amberAccent,
                      foregroundColor: Colors.black87,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () async {
                      await PlayerStorage.selectCompanion(null);
                      _showNotification('Đã gỡ trợ thủ!');
                    },
                    child: const Text(
                      'GỠ TRANG BỊ',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ] else if (isUnlocked) ...[
                SizedBox(
                  height: 32,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyan.shade700,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () async {
                      await PlayerStorage.selectCompanion(comp.id);
                      _showNotification('Đã trang bị ${comp.name}!');
                    },
                    child: const Text(
                      'TRANG BỊ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ] else ...[
                SizedBox(
                  height: 32,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amberAccent,
                      foregroundColor: Colors.black87,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () async {
                      if (profile.gold < comp.price) {
                        _showNotification(
                          'Không đủ Vàng để mua trợ thủ!',
                          isSuccess: false,
                        );
                        return;
                      }
                      final success = await PlayerStorage.unlockCompanion(
                        comp.id,
                        comp.price,
                      );
                      if (success) {
                        _showNotification(
                          'Đã mở khóa ${comp.name} (-${comp.price} Vàng)!',
                        );
                      }
                    },
                    icon: const Icon(Icons.monetization_on_rounded, size: 14),
                    label: Text(
                      '${comp.price} VÀNG',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // --- TAB 3: TRANG PHỤC (SKINS - THUẦN THẨM MỸ, FAIR PLAY) ---
}

class _CurrencyBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final int value;

  const _CurrencyBadge({
    required this.icon,
    required this.color,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final formatted = value.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 5),
          Text(
            formatted,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroItem {
  final String id;
  final String name;
  final String subtitle;
  final String role;
  final String description;
  final Color color;
  final IconData icon;
  final String? portraitAsset;
  final int? price;

  const _HeroItem({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.role,
    required this.description,
    required this.color,
    required this.icon,
    this.portraitAsset,
    this.price,
  });
}

class _CompanionItem {
  final String id;
  final String name;
  final String tag;
  final String description;
  final int price;
  final Color color;
  final IconData icon;
  final String? spriteAsset;

  const _CompanionItem({
    required this.id,
    required this.name,
    required this.tag,
    required this.description,
    required this.price,
    required this.color,
    required this.icon,
    this.spriteAsset,
  });
}
