import 'package:flutter/material.dart';
import '../services/audio_service.dart';
import '../services/auth_service.dart';
import '../services/player_storage.dart';
import 'auth_screen.dart';

class SettingsDialog extends StatelessWidget {
  const SettingsDialog({super.key});

  static Future<void> show(BuildContext context) {
    AudioService.instance.playSfx(SfxSound.uiClick);
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const SettingsDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final audio = AudioService.instance;
    final profile = PlayerStorage.currentProfile;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 480),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0F1528),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF00E5FF), width: 1.8),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00E5FF).withValues(alpha: 0.25),
                blurRadius: 24,
                spreadRadius: 2,
              ),
              const BoxShadow(
                color: Colors.black87,
                blurRadius: 20,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. HEADER DIALOG
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Color(0x3300E5FF), width: 1.5),
                  ),
                  gradient: LinearGradient(
                    colors: [Color(0xFF142445), Color(0xFF0E1A34)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF00E5FF).withValues(alpha: 0.6),
                        ),
                      ),
                      child: const Icon(
                        Icons.volume_up_rounded,
                        color: Color(0xFF00E5FF),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CÀI ĐẶT ÂM THANH',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Tùy chỉnh âm lượng nhạc nền và hiệu ứng âm thanh',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        audio.playSfx(SfxSound.uiClick);
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      tooltip: 'Đóng',
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),

              // 2. NỘI DUNG ÂM THANH
              Flexible(
                child: _buildAudioSection(audio),
              ),

              // 3. FOOTER DIALOG: THÔNG TIN TÀI KHOẢN & NÚT HÀNH ĐỘNG
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: const BoxDecoration(
                  color: Color(0xFF0B101E),
                  border: Border(
                    top: BorderSide(color: Color(0x2200E5FF), width: 1),
                  ),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(18),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF00E676),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              AuthService.instance.isSignedIn
                                  ? '${AuthService.instance.currentUser?.email ?? ''} • ID: ${profile.playerCode}'
                                  : 'ID: ${profile.playerCode}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 10.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (AuthService.instance.isSignedIn) ...[
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => _confirmLogout(context),
                        icon: const Icon(Icons.logout_rounded, size: 16),
                        label: const Text('Đăng xuất', style: TextStyle(fontSize: 11)),
                      ),
                      const SizedBox(width: 4),
                    ],
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white60,
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () {
                        audio.setBgmVolume(0.8);
                        audio.setSfxVolume(1.0);
                        audio.isBgmEnabled = true;
                        audio.isSfxEnabled = true;
                        audio.playSfx(SfxSound.uiClick);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Đã khôi phục cài đặt âm thanh mặc định!'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.restore_rounded, size: 16),
                      label: const Text('Mặc định', style: TextStyle(fontSize: 11)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E5FF),
                        foregroundColor: const Color(0xFF0A1633),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () {
                        audio.playSfx(SfxSound.uiClick);
                        Navigator.of(context).pop();
                      },
                      child: const Text(
                        'XONG',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- ĐĂNG XUẤT TÀI KHOẢN ---
  Future<void> _confirmLogout(BuildContext context) async {
    AudioService.instance.playSfx(SfxSound.uiClick);
    final email = AuthService.instance.currentUser?.email ?? '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F1528),
        title: const Text('Đăng xuất?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Tiến trình của tài khoản $email đã được lưu trên máy chủ.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    final navigator = Navigator.of(context, rootNavigator: true);
    await AuthService.instance.logout();
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  }

  // --- CÀI ĐẶT ÂM THANH (AUDIO) ---
  Widget _buildAudioSection(AudioService audio) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // NHẠC NỀN (BGM)
          ValueListenableBuilder<bool>(
            valueListenable: audio.isBgmEnabledNotifier,
            builder: (context, isBgmOn, _) {
              return ValueListenableBuilder<double>(
                valueListenable: audio.bgmVolumeNotifier,
                builder: (context, bgmVol, _) {
                  return _buildSettingCard(
                    title: 'Nhạc nền (BGM)',
                    subtitle: 'Âm thanh giai điệu tại Sảnh Chờ và Đấu Trường',
                    icon: isBgmOn ? Icons.music_note_rounded : Icons.music_off_rounded,
                    iconColor: const Color(0xFF00E5FF),
                    trailing: Switch.adaptive(
                      value: isBgmOn,
                      activeTrackColor: const Color(0xFF00E5FF),
                      onChanged: (val) {
                        audio.isBgmEnabled = val;
                      },
                    ),
                    bottomWidget: isBgmOn
                        ? Row(
                            children: [
                              Icon(
                                bgmVol == 0
                                    ? Icons.volume_mute_rounded
                                    : (bgmVol < 0.5
                                        ? Icons.volume_down_rounded
                                        : Icons.volume_up_rounded),
                                color: const Color(0xFF00E5FF),
                                size: 20,
                              ),
                              Expanded(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    activeTrackColor: const Color(0xFF00E5FF),
                                    inactiveTrackColor: Colors.white12,
                                    thumbColor: const Color(0xFF00E5FF),
                                    overlayColor: const Color(0xFF00E5FF).withValues(alpha: 0.2),
                                    trackHeight: 4,
                                  ),
                                  child: Slider(
                                    value: bgmVol,
                                    min: 0.0,
                                    max: 1.0,
                                    onChanged: (v) {
                                      audio.setBgmVolume(v);
                                    },
                                  ),
                                ),
                              ),
                              Text(
                                '${(bgmVol * 100).round()}%',
                                style: const TextStyle(
                                  color: Color(0xFF00E5FF),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          )
                        : null,
                  );
                },
              );
            },
          ),
          const SizedBox(height: 10),

          // HIỆU ỨNG ÂM THANH (SFX)
          ValueListenableBuilder<bool>(
            valueListenable: audio.isSfxEnabledNotifier,
            builder: (context, isSfxOn, _) {
              return ValueListenableBuilder<double>(
                valueListenable: audio.sfxVolumeNotifier,
                builder: (context, sfxVol, _) {
                  return _buildSettingCard(
                    title: 'Hiệu ứng âm thanh (SFX)',
                    subtitle: 'Tiếng va chạm, tung kỹ năng, nhặt vàng, tiếng click UI',
                    icon: isSfxOn ? Icons.graphic_eq_rounded : Icons.volume_off_rounded,
                    iconColor: const Color(0xFFFFD700),
                    trailing: Switch.adaptive(
                      value: isSfxOn,
                      activeTrackColor: const Color(0xFFFFD700),
                      onChanged: (val) {
                        audio.isSfxEnabled = val;
                        if (val) {
                          audio.playSfx(SfxSound.uiClick);
                        }
                      },
                    ),
                    bottomWidget: isSfxOn
                        ? Row(
                            children: [
                              Icon(
                                sfxVol == 0
                                    ? Icons.volume_mute_rounded
                                    : (sfxVol < 0.5
                                        ? Icons.volume_down_rounded
                                        : Icons.volume_up_rounded),
                                color: const Color(0xFFFFD700),
                                size: 20,
                              ),
                              Expanded(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    activeTrackColor: const Color(0xFFFFD700),
                                    inactiveTrackColor: Colors.white12,
                                    thumbColor: const Color(0xFFFFD700),
                                    overlayColor: const Color(0xFFFFD700).withValues(alpha: 0.2),
                                    trackHeight: 4,
                                  ),
                                  child: Slider(
                                    value: sfxVol,
                                    min: 0.0,
                                    max: 1.0,
                                    onChangeEnd: (v) {
                                      audio.playSfx(SfxSound.uiClick);
                                    },
                                    onChanged: (v) {
                                      audio.setSfxVolume(v);
                                    },
                                  ),
                                ),
                              ),
                              Text(
                                '${(sfxVol * 100).round()}%',
                                style: const TextStyle(
                                  color: Color(0xFFFFD700),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          )
                        : null,
                  );
                },
              );
            },
          ),
          const SizedBox(height: 10),

          // NÚT TẮT TIẾNG TOÀN BỘ (MUTE ALL)
          ValueListenableBuilder<bool>(
            valueListenable: audio.isBgmEnabledNotifier,
            builder: (context, bgmOn, _) {
              return ValueListenableBuilder<bool>(
                valueListenable: audio.isSfxEnabledNotifier,
                builder: (context, sfxOn, _) {
                  final isMuted = !bgmOn && !sfxOn;
                  return OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isMuted ? const Color(0xFFFF5252) : Colors.white70,
                      side: BorderSide(
                        color: isMuted ? const Color(0xFFFF5252) : Colors.white24,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () {
                      audio.toggleMute();
                      if (audio.isSfxEnabled) {
                        audio.playSfx(SfxSound.uiClick);
                      }
                    },
                    icon: Icon(
                      isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                      size: 18,
                    ),
                    label: Text(
                      isMuted ? 'BẬT LẠI TOÀN BỘ ÂM THANH' : 'TẮT TIẾNG TOÀN BỘ (MUTE ALL)',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSettingCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    Widget? trailing,
    Widget? bottomWidget,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF131B32),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          if (bottomWidget != null) ...[
            const SizedBox(height: 4),
            bottomWidget,
          ],
        ],
      ),
    );
  }
}
