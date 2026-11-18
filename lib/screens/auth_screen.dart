import 'package:flutter/material.dart';

import '../services/audio_service.dart';
import '../services/auth_service.dart';
import '../services/player_storage.dart';
import 'lobby_screen.dart';

/// Màn hình Đăng nhập / Đăng ký trước khi vào Sảnh Chờ.
/// Tài khoản: Firebase Authentication (Email + Mật khẩu).
/// Hồ sơ người chơi: Firebase Realtime Database `players/{uid}`.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

enum _AuthMode { login, register }

class _AuthScreenState extends State<AuthScreen> {
  static const _cyan = Color(0xFF00E5FF);
  static const _gold = Color(0xFFFFD54F);
  static const _panel = Color(0xFF0F1528);

  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  _AuthMode _mode = _AuthMode.login;
  bool _loading = false;
  bool _obscure = true;
  String? _error;
  String? _info;

  bool get _isRegister => _mode == _AuthMode.register;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _switchMode(_AuthMode mode) {
    if (_loading || mode == _mode) return;
    AudioService.instance.playSfx(SfxSound.uiClick);
    setState(() {
      _mode = mode;
      _error = null;
      _info = null;
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    AudioService.instance.playSfx(SfxSound.uiClick);
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });

    try {
      if (_isRegister) {
        await AuthService.instance.register(
          displayName: _nameCtrl.text,
          email: _emailCtrl.text,
          password: _passCtrl.text,
        );
      } else {
        await AuthService.instance.login(
          email: _emailCtrl.text,
          password: _passCtrl.text,
        );
      }
      if (!mounted) return;
      _enterGame();
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Đã xảy ra lỗi: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailCtrl.text.trim();
    if (!_isValidEmail(email)) {
      setState(() {
        _info = null;
        _error = 'Nhập email hợp lệ ở ô Email để nhận link đặt lại mật khẩu.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });
    try {
      await AuthService.instance.sendPasswordReset(email);
      if (mounted) {
        setState(() => _info = 'Đã gửi email đặt lại mật khẩu tới $email.');
      }
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _playOffline() async {
    AudioService.instance.playSfx(SfxSound.uiClick);
    await PlayerStorage.loadProfile();
    if (mounted) _enterGame();
  }

  void _enterGame() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (_, _, _) => const LobbyScreen(),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  static bool _isValidEmail(String v) =>
      RegExp(r'^[\w.+\-]+@[\w\-]+(\.[\w\-]+)+$').hasMatch(v.trim());

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060A16),
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/ui/sanhcho.png',
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0xE6060A16), Color(0xB3060A16), Color(0xF2060A16)],
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, c) {
                final wide = c.maxWidth >= 720;
                final card = _buildCard();
                if (!wide) {
                  return Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: card,
                    ),
                  );
                }
                return Row(
                  children: [
                    Expanded(child: _buildBranding()),
                    SizedBox(
                      width: 420,
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(0, 16, 32, 16),
                          child: card,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBranding() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 24, 24, 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShaderMask(
            shaderCallback: (r) => const LinearGradient(
              colors: [Color(0xFFFFF59D), _gold, Color(0xFFFF8F00)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ).createShader(r),
            child: const Text(
              'GOLD RUSH',
              style: TextStyle(
                color: Colors.white,
                fontSize: 56,
                fontWeight: FontWeight.w900,
                letterSpacing: 4,
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Săn vàng trong hầm ngục • Leo rank PvP • Lập tổ đội cùng bạn bè',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 24),
          const Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _FeatureChip(icon: Icons.cloud_done_rounded, text: 'Lưu tiến trình trên cloud'),
              _FeatureChip(icon: Icons.devices_rounded, text: 'Chơi trên mọi thiết bị'),
              _FeatureChip(icon: Icons.emoji_events_rounded, text: 'Bảng xếp hạng server'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCard() {
    final online = AuthService.instance.isAvailable;
    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      decoration: BoxDecoration(
        color: _panel.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _cyan.withValues(alpha: 0.7), width: 1.4),
        boxShadow: [
          BoxShadow(color: _cyan.withValues(alpha: 0.18), blurRadius: 24),
          const BoxShadow(color: Colors.black54, blurRadius: 18, offset: Offset(0, 8)),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildModeToggle(),
            const SizedBox(height: 16),
            if (!online) ...[
              _buildBanner(
                'Không kết nối được máy chủ. Bạn vẫn có thể chơi offline (dữ liệu chỉ lưu trên máy).',
                Colors.orangeAccent,
                Icons.wifi_off_rounded,
              ),
              const SizedBox(height: 12),
            ],
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: _isRegister
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _field(
                        controller: _nameCtrl,
                        label: 'Tên nhân vật',
                        icon: Icons.person_rounded,
                        action: TextInputAction.next,
                        validator: (v) {
                          final s = v?.trim() ?? '';
                          if (s.length < 3) return 'Tên tối thiểu 3 ký tự';
                          if (s.length > 16) return 'Tên tối đa 16 ký tự';
                          return null;
                        },
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            _field(
              controller: _emailCtrl,
              label: 'Email',
              icon: Icons.alternate_email_rounded,
              keyboard: TextInputType.emailAddress,
              action: TextInputAction.next,
              autofill: const [AutofillHints.email],
              validator: (v) =>
                  _isValidEmail(v ?? '') ? null : 'Email không hợp lệ',
            ),
            const SizedBox(height: 12),
            _field(
              controller: _passCtrl,
              label: 'Mật khẩu',
              icon: Icons.lock_rounded,
              obscure: _obscure,
              action: _isRegister ? TextInputAction.next : TextInputAction.done,
              autofill: [_isRegister ? AutofillHints.newPassword : AutofillHints.password],
              onSubmitted: _isRegister ? null : (_) => _submit(),
              suffix: IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                  color: Colors.white54,
                  size: 20,
                ),
                tooltip: _obscure ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
              validator: (v) =>
                  (v ?? '').length < 6 ? 'Mật khẩu tối thiểu 6 ký tự' : null,
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: _isRegister
                  ? Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _field(
                        controller: _confirmCtrl,
                        label: 'Nhập lại mật khẩu',
                        icon: Icons.lock_outline_rounded,
                        obscure: _obscure,
                        action: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                        validator: (v) =>
                            v != _passCtrl.text ? 'Mật khẩu nhập lại không khớp' : null,
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            if (!_isRegister)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _loading || !online ? null : _forgotPassword,
                  style: TextButton.styleFrom(
                    foregroundColor: _cyan,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Quên mật khẩu?', style: TextStyle(fontSize: 12)),
                ),
              )
            else
              const SizedBox(height: 14),
            if (_error != null) ...[
              _buildBanner(_error!, Colors.redAccent, Icons.error_outline_rounded),
              const SizedBox(height: 10),
            ],
            if (_info != null) ...[
              _buildBanner(_info!, const Color(0xFF00E676), Icons.mark_email_read_rounded),
              const SizedBox(height: 10),
            ],
            SizedBox(
              height: 46,
              child: ElevatedButton(
                onPressed: _loading || !online ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _gold,
                  foregroundColor: const Color(0xFF2A1A00),
                  disabledBackgroundColor: _gold.withValues(alpha: 0.35),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.6,
                          color: Color(0xFF2A1A00),
                        ),
                      )
                    : Text(
                        _isRegister ? 'TẠO TÀI KHOẢN' : 'VÀO GAME',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          letterSpacing: 1.2,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _isRegister ? 'Đã có tài khoản?' : 'Chưa có tài khoản?',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                TextButton(
                  onPressed: () => _switchMode(
                    _isRegister ? _AuthMode.login : _AuthMode.register,
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: _cyan,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(
                    _isRegister ? 'Đăng nhập' : 'Đăng ký ngay',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            if (!online)
              OutlinedButton.icon(
                onPressed: _loading ? null : _playOffline,
                icon: const Icon(Icons.sports_esports_rounded, size: 18),
                label: const Text('CHƠI OFFLINE'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeToggle() {
    Widget tab(_AuthMode mode, String text) {
      final selected = _mode == mode;
      return Expanded(
        child: GestureDetector(
          onTap: () => _switchMode(mode),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? _cyan.withValues(alpha: 0.16) : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: selected ? _cyan : Colors.transparent,
                width: 1.2,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              text,
              style: TextStyle(
                color: selected ? _cyan : Colors.white60,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                fontSize: 13,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0F1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          tab(_AuthMode.login, 'ĐĂNG NHẬP'),
          const SizedBox(width: 4),
          tab(_AuthMode.register, 'ĐĂNG KÝ'),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    TextInputType? keyboard,
    TextInputAction? action,
    Iterable<String>? autofill,
    Widget? suffix,
    String? Function(String?)? validator,
    void Function(String)? onSubmitted,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Colors.white12),
    );
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboard,
      textInputAction: action,
      autofillHints: autofill,
      enabled: !_loading,
      validator: validator,
      onFieldSubmitted: onSubmitted,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.white54, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0xFF0A0F1E),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: const BorderSide(color: _cyan, width: 1.4),
        ),
        errorBorder: border.copyWith(
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: border.copyWith(
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.4),
        ),
        errorStyle: const TextStyle(fontSize: 11),
      ),
    );
  }

  Widget _buildBanner(String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontSize: 12, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _FeatureChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFFFFD54F)),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}
