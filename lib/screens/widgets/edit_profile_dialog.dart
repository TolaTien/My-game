import 'dart:math';
import 'package:flutter/material.dart';
import '../../models/player_profile.dart';
import '../../services/audio_service.dart';
import '../../services/player_storage.dart';

/// Hộp thoại cho phép người chơi đổi tên và cấp mã ID mới
/// Cực kỳ thuận tiện để kiểm thử tính năng Bạn Bè & Tổ Đội giữa nhiều tab Chrome hoặc cửa sổ ẩn danh!
class EditProfileDialog extends StatefulWidget {
  final PlayerProfile profile;

  const EditProfileDialog({super.key, required this.profile});

  static Future<void> show(BuildContext context, PlayerProfile profile) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => EditProfileDialog(profile: profile),
    );
  }

  @override
  State<EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<EditProfileDialog> {
  late TextEditingController _nameController;
  late TextEditingController _codeController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.playerName);
    _codeController = TextEditingController(text: widget.profile.playerCode);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _generateRandomId() {
    AudioService.instance.playSfx(SfxSound.uiClick);
    final rand = 1000 + Random().nextInt(8999);
    setState(() {
      _codeController.text = 'GR$rand';
      if (_nameController.text.startsWith('Chiến Binh #') ||
          _nameController.text.isEmpty) {
        _nameController.text = 'Chiến Binh #$rand';
      }
    });
  }

  void _applyQuickPreset(String name, String code) {
    AudioService.instance.playSfx(SfxSound.uiClick);
    setState(() {
      _nameController.text = name;
      _codeController.text = code;
    });
  }

  Future<void> _handleSave() async {
    final name = _nameController.text.trim();
    final code = _codeController.text.trim().toUpperCase();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập tên người chơi!'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (code.isEmpty || !code.startsWith('GR') || code.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mã ID phải bắt đầu bằng GR (ví dụ: GR1001, GR2048)!'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    AudioService.instance.playSfx(SfxSound.uiClick);
    await PlayerStorage.updateNameAndCode(name, code);

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Color(0xFF00E676)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Đã cập nhật: $name [$code] thành công!',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF142442),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF142442), Color(0xFF0C1628)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF29D8FF), width: 2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF29D8FF).withValues(alpha: 0.35),
              blurRadius: 18,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tiêu đề
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E5FF).withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.badge_rounded,
                    color: Color(0xFF00E5FF),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'ĐỔI TÊN & CẤP MÃ ID NGƯỜI CHƠI',
                  style: TextStyle(
                    color: Color(0xFF29D8FF),
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    letterSpacing: 1.0,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Nhập Tên người chơi
            const Text(
              'TÊN NHÂN VẬT (BẠN):',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 5),
            TextField(
              controller: _nameController,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.08),
                hintText: 'Nhập tên hiển thị của bạn...',
                hintStyle: const TextStyle(color: Colors.white30),
                prefixIcon: const Icon(Icons.person_rounded, color: Color(0xFF00E5FF)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF00E5FF), width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Mã ID kết bạn
            const Text(
              'MÃ ĐỊNH DANH DUY NHẤT (MÃ KẾT BẠN):',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeController,
                    style: const TextStyle(
                      color: Color(0xFFFFD54F),
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      letterSpacing: 1.2,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.08),
                      prefixIcon: const Icon(Icons.fingerprint_rounded, color: Color(0xFFFFD54F)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFFFD54F), width: 1.5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0288D1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _generateRandomId,
                  icon: const Icon(Icons.casino_rounded, size: 18),
                  label: const Text(
                    'NGẪU NHIÊN',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Gợi ý cài đặt nhanh để test 2 tab
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.cyan.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.cyan.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '⚡ GỢI Ý CÀI NHANH ĐỂ TEST 2 TAB TRÌNH DUYỆT:',
                    style: TextStyle(
                      color: Color(0xFF29D8FF),
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      ActionChip(
                        backgroundColor: const Color(0xFF1E3A6E),
                        side: const BorderSide(color: Color(0xFF00E5FF)),
                        avatar: const Icon(Icons.computer_rounded, size: 14, color: Color(0xFF00E5FF)),
                        label: const Text(
                          'Tab 1 [GR1001]',
                          style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () => _applyQuickPreset('Chủ Phòng #1', 'GR1001'),
                      ),
                      ActionChip(
                        backgroundColor: const Color(0xFF1E3A6E),
                        side: const BorderSide(color: Color(0xFFFFD54F)),
                        avatar: const Icon(Icons.tab_rounded, size: 14, color: Color(0xFFFFD54F)),
                        label: const Text(
                          'Tab 2 [GR2002]',
                          style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () => _applyQuickPreset('Đồng Đội #2', 'GR2002'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Nút Lưu thay đổi
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white30),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('HỦY', style: TextStyle(color: Colors.white70)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E676),
                      foregroundColor: const Color(0xFF062412),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _handleSave,
                    child: const Text(
                      'LƯU THAY ĐỔI',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
