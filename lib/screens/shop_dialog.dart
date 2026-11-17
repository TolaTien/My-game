import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../models/player_profile.dart';
import '../services/player_storage.dart';
import '../core/constants.dart';
import '../game/combat/hero_kit.dart';

class ShopDialog extends StatefulWidget {
  final int initialTab;

  const ShopDialog({super.key, this.initialTab = 0})
    : assert(initialTab >= 0 && initialTab < 3);

  @override
  State<ShopDialog> createState() => _ShopDialogState();
}

class _ShopDialogState extends State<ShopDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab,
    );
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
                      const Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'CỬA HÀNG VẬT PHẨM',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                              color: Colors.amberAccent,
                            ),
                          ),
                        ),
                      ),

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
                      const SizedBox(width: 10),

                      // Số dư Kim Cương
                      _CurrencyBadge(
                        icon: Icons.diamond_rounded,
                        color: Colors.cyanAccent,
                        value: profile.diamonds,
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
                      Tab(text: 'TRANG PHỤC (SKIN)'),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // 3. NỘI DUNG TỪNG TAB
                Expanded(
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      dragDevices: {
                        ...ScrollConfiguration.of(context).dragDevices,
                        PointerDeviceKind.mouse,
                      },
                    ),
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        // TAB 1: NHÂN VẬT
                        _buildHeroesTab(profile),

                        // TAB 2: TRỢ THỦ AI
                        _buildCompanionsTab(profile),

                        // TAB 3: TRANG PHỤC (SKIN)
                        _buildSkinsTab(profile),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- TAB 1: NHÂN VẬT (ĐỒNG GIÁ 100 VÀNG THEO MỤC 6) ---
  Widget _buildHeroesTab(PlayerProfile profile) {
    final heroes = [
      _HeroItem(
        id: 'george',
        name: 'George',
        subtitle: 'Chiến Binh Búa',
        role: 'CẬN CHIẾN / TANKER',
        description: 'Vung búa cuồng phong, nện đất diện rộng, máu cực trâu.',
        color: const Color(0xFFFF5722),
        icon: Icons.shield_sharp,
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
      ),
      _HeroItem(
        id: 'kaelen',
        name: 'Kaelen Lôi Quang',
        subtitle: 'Kiếm Khách Thunderblade (Asset 4)',
        role: 'SÁT THỦ / LÔI QUANG',
        description: 'Song đao Lôi Hoàng: Lôi Ảnh Trảm (Dash sét), Lôi Điện Hộ Thể (4 kiếm xoay) & Thiên Phạt Lôi Ngục.',
        color: const Color(0xFF00E5FF),
        icon: Icons.bolt_rounded,
        portraitAsset: 'assets/images/heroes/kaelen_portrait.png',
      ),
      _HeroItem(
        id: 'nova_blade',
        name: 'Nova Blade (NOVA-07)',
        subtitle: 'Chiến Binh Neon (Asset 1 & 2)',
        role: 'FIGHTER / MELEE',
        description: 'Song kiếm Cyber Neon: Energy Slash (120% DMG), Shadow Dash (Lướt tím AoE) & Quantum Burst (Nổ lượng tử).',
        color: const Color(0xFF18FFFF),
        icon: Icons.auto_fix_high_rounded,
        portraitAsset: 'assets/images/heroes/nova_blade_portrait.png',
      ),
      _HeroItem(
        id: 'valeria',
        name: 'Pháp Sư Valeria',
        subtitle: 'Pháp Sư Băng Hỏa (Asset 3)',
        role: 'ELEMENTALIST / BĂNG HỎA',
        description: 'Quyền trượng Băng Tinh: Băng Hỏa Trảm, Vòng Xoáy Nguyên Tố & Mưa Thiên Thạch Băng Hỏa.',
        color: const Color(0xFF40C4FF),
        icon: Icons.ac_unit_rounded,
        portraitAsset: 'assets/images/heroes/valeria_portrait.png',
      ),
      _HeroItem(
        id: 'garrick',
        name: 'Chiến Binh Garrick',
        subtitle: 'Stone Guardian Cổ Đại (Asset 3)',
        role: 'TANK / ĐẠI ĐAO CỔ NGỮ',
        description: 'Đại đao đá cổ đại: Đất Lở (Gai đá thẳng), Hộ Thể Hoàng Kim (Giáp đá đẩy lùi) & Nội Địa Chấn.',
        color: const Color(0xFFFFD700),
        icon: Icons.fort_rounded,
        portraitAsset: 'assets/images/heroes/garrick_portrait.png',
      ),
      _HeroItem(
        id: 'shadow_01',
        name: 'SHADOW-01',
        subtitle: 'Sát Thủ Hư Không (Asset 2)',
        role: 'ASSASSIN / RANGED',
        description: 'Song dao năng lượng tím: Plasma Shot tầm xa, Cyber Spin 360° & Phantom Dash phân thân.',
        color: const Color(0xFFE040FB),
        icon: Icons.flare_rounded,
        portraitAsset: 'assets/images/heroes/shadow_01_portrait.png',
      ),
      _HeroItem(
        id: 'ember_02',
        name: 'EMBER-02',
        subtitle: 'Phù Thủy Hỏa Cầu (Asset 2)',
        role: 'MAGE / AOE FIRE',
        description: 'Pháp sư lửa: Hỏa Cầu Liên Hoàn, Cột Lửa Địa Ngục & Thái Dương Bộc Phá diện rộng.',
        color: const Color(0xFFFF6D00),
        icon: Icons.local_fire_department_rounded,
        portraitAsset: 'assets/images/heroes/ember_02_portrait.png',
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
                  HeroKit.isSpecialized(hero.id)
                      ? HeroKit.forHero(hero.id).skills
                            .asMap()
                            .entries
                            .map(
                              (entry) =>
                                  '${entry.key + 1}. ${entry.value.name}',
                            )
                            .join('\n')
                      : hero.description,
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
                      const price = GameConstants.heroUnlockPrice;
                      if (profile.gold < price) {
                        _showNotification(
                          'Bạn không đủ Vàng! Cần 100 Vàng để mở khóa.',
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
                          'Mở khóa thành công ${hero.name} (-100 Vàng)!',
                        );
                      }
                    },
                    icon: const Icon(Icons.monetization_on_rounded, size: 14),
                    label: const Text(
                      '100 VÀNG',
                      style: TextStyle(
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
        tag: 'ATTACK DRONE',
        description:
            'Tự động phát hiện và phóng tia plasma năng lượng vào quái.',
        price: 500,
        color: const Color(0xFFFF5252),
        icon: Icons.rocket_launch_rounded,
      ),
      _CompanionItem(
        id: 'comp_defense',
        name: 'Trợ Thủ Phòng Ngự',
        tag: 'SHIELD DRONE',
        description: 'Tạo lồng bảo hộ năng lượng giảm 30% sát thương nhận vào.',
        price: 600,
        color: const Color(0xFF448AFF),
        icon: Icons.shield_rounded,
      ),
      _CompanionItem(
        id: 'comp_control',
        name: 'Trợ Thủ Khống Chế',
        tag: 'FROST DRONE',
        description:
            'Tỏa aura băng tuyết làm chậm 40% tốc chạy của toàn bộ quái vật.',
        price: 700,
        color: const Color(0xFF18FFFF),
        icon: Icons.ac_unit_rounded,
      ),
      _CompanionItem(
        id: 'aegis_x9',
        name: 'Aegis-X9 Lôi Từ',
        tag: 'GOLDEN SPIRIT (ASSET 4)',
        description: 'Lõi bát diện Hoàng Kim: Hút vàng 120px, bắn tia Laser & mở Trường Trọng Lực + Khiên Vàng.',
        price: 800,
        color: const Color(0xFFFFD700),
        icon: Icons.auto_awesome_rounded,
        spriteAsset: 'assets/images/companions/aegis_x9.png',
      ),
      _CompanionItem(
        id: 'cyber_drone',
        name: 'Cyber Drone (PIXEL-01)',
        tag: 'SUPPORT • UTILITY (ASSET 1 & 2)',
        description: 'Drone sừng trắng mắt lam: Bắn đạn Plasma, hồi máu đồng minh & bật Khiên Cầu Năng Lượng.',
        price: 650,
        color: const Color(0xFF00E5FF),
        icon: Icons.smart_toy_rounded,
        spriteAsset: 'assets/images/companions/cyber_drone.png',
      ),
      _CompanionItem(
        id: 'pyro_frost_dragon',
        name: 'Pyro-Frost Dragon',
        tag: 'RỒNG BĂNG HỎA 2 ĐẦU (ASSET 3)',
        description: 'Phun lửa & tuyết xen kẽ; kích hoạt Hơi Thở Bão Tố đóng băng kẻ địch và buff khiên lửa.',
        price: 900,
        color: const Color(0xFFFF5252),
        icon: Icons.whatshot_rounded,
        spriteAsset: 'assets/images/companions/pyro_frost_dragon.png',
      ),
      _CompanionItem(
        id: 'gem_tumbler',
        name: 'Gem-Tumbler',
        tag: 'TINH THỂ HOÀNG KIM (ASSET 3)',
        description: 'Phun vụn đá gây choáng; kích hoạt Hoàng Kim Chấn hút vàng từ xa & tăng 30% giáp.',
        price: 850,
        color: const Color(0xFFFFB300),
        icon: Icons.hexagon_rounded,
        spriteAsset: 'assets/images/companions/gem_tumbler.png',
      ),
      _CompanionItem(
        id: 'luna_fox',
        name: 'Hồ Ly Luna',
        tag: 'PET FOX (ASSET 2)',
        description: 'Linh thú Hồ Ly trắng xanh: Bắn cầu linh lực băng lam làm chậm quái và hồi Ki.',
        price: 750,
        color: const Color(0xFF80D8FF),
        icon: Icons.pets_rounded,
        spriteAsset: 'assets/images/companions/luna_fox.png',
      ),
      _CompanionItem(
        id: 'orbit_03',
        name: 'ORBIT-03 Drone',
        tag: 'MECH SPHERE (ASSET 2)',
        description: 'Cầu cơ khí Hoàng Kim bắn tia laser năng lượng tốc độ cao liên hoàn.',
        price: 700,
        color: const Color(0xFFFFAB00),
        icon: Icons.radar_rounded,
        spriteAsset: 'assets/images/companions/orbit_03.png',
      ),
    ];

    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
  Widget _buildSkinsTab(PlayerProfile profile) {
    final skins = [
      _SkinItem(
        id: 'skin_george_gold',
        name: 'George Hoàng Kim',
        forHero: 'George',
        priceDiamonds: 50,
        color: const Color(0xFFFFD700),
      ),
      _SkinItem(
        id: 'skin_ranger_shadow',
        name: 'Ranger Bóng Đêm',
        forHero: 'Xạ Thủ Ranger',
        priceDiamonds: 40,
        color: const Color(0xFF7E57C2),
      ),
      _SkinItem(
        id: 'skin_tanker_magma',
        name: 'Hiệp Sĩ Dung Nham',
        forHero: 'Hiệp Sĩ Tanker',
        priceDiamonds: 45,
        color: const Color(0xFFFF3D00),
      ),
      _SkinItem(
        id: 'skin_ninja_thunder',
        name: 'Ninja Lôi Thần',
        forHero: 'Ninja Sát Thủ',
        priceDiamonds: 50,
        color: const Color(0xFF651FFF),
      ),
      _SkinItem(
        id: 'skin_kaelen_emperor',
        name: 'Kaelen Lôi Đế Hoàng Kim',
        forHero: 'Kaelen Lôi Quang',
        priceDiamonds: 60,
        color: const Color(0xFF00E5FF),
      ),
    ];

    return Column(
      children: [
        // Lưu ý Fair-Play
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.deepPurpleAccent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.deepPurpleAccent.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: const [
              Icon(Icons.verified_rounded, size: 16, color: Colors.cyanAccent),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'LƯU Ý CÔNG BẰNG: Toàn bộ Trang Phục (Skin) thuần thẩm mỹ, hoàn toàn KHÔNG thay đổi chỉ số!',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.cyanAccent,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),

        Expanded(
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            itemCount: skins.length,
            itemBuilder: (context, index) {
              final skin = skins[index];
              final isUnlocked = profile.unlockedSkinIds.contains(skin.id);
              final isEquipped = profile.selectedSkinId == skin.id;

              return Container(
                width: 160,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF232038),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isEquipped
                        ? skin.color
                        : isUnlocked
                        ? Colors.white24
                        : Colors.white12,
                    width: isEquipped ? 2.5 : 1,
                  ),
                ),
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      height: 70,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            skin.color.withValues(alpha: 0.2),
                            skin.color.withValues(alpha: 0.05),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: skin.color.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.checkroom_rounded,
                          color: skin.color,
                          size: 38,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      skin.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                    ),
                    Text(
                      'Tướng: ${skin.forHero}',
                      style: const TextStyle(
                        fontSize: 9.5,
                        color: Colors.white60,
                      ),
                    ),
                    const Spacer(),
                    if (isEquipped) ...[
                      SizedBox(
                        height: 30,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: skin.color,
                            foregroundColor: Colors.black87,
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () async {
                            await PlayerStorage.selectSkin(null);
                            _showNotification('Đã gỡ skin mặc định!');
                          },
                          child: const Text(
                            'GỠ SKIN',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ] else if (isUnlocked) ...[
                      SizedBox(
                        height: 30,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purple.shade700,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () async {
                            await PlayerStorage.selectSkin(skin.id);
                            _showNotification('Đã mặc ${skin.name}!');
                          },
                          child: const Text(
                            'MẶC',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ] else ...[
                      SizedBox(
                        height: 30,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.cyanAccent.shade700,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () async {
                            if (profile.diamonds < skin.priceDiamonds) {
                              _showNotification(
                                'Không đủ Kim Cương! Cần ${skin.priceDiamonds} KC.',
                                isSuccess: false,
                              );
                              return;
                            }
                            final success = await PlayerStorage.unlockSkin(
                              skin.id,
                              skin.priceDiamonds,
                            );
                            if (success) {
                              _showNotification(
                                'Đã sở hữu ${skin.name} (-${skin.priceDiamonds} KC)!',
                              );
                            }
                          },
                          icon: const Icon(Icons.diamond_rounded, size: 14),
                          label: Text(
                            '${skin.priceDiamonds} KC',
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
          ),
        ),
      ],
    );
  }
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

  const _HeroItem({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.role,
    required this.description,
    required this.color,
    required this.icon,
    this.portraitAsset,
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

class _SkinItem {
  final String id;
  final String name;
  final String forHero;
  final int priceDiamonds;
  final Color color;

  const _SkinItem({
    required this.id,
    required this.name,
    required this.forHero,
    required this.priceDiamonds,
    required this.color,
  });
}
