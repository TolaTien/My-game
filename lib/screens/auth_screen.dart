import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../services/audio_service.dart';
import '../services/auth_service.dart';
import 'lobby_screen.dart';

/// Màn hình Đăng nhập / Đăng ký Tài khoản của BIG-WAR.
/// Thiết kế hiện đại dạng Card 2 cột chia đôi:
/// - Bên trái: Hình ảnh Chibi Rồng Lửa tươi sáng, phong cách game dễ thương & dũng mãnh.
/// - Bên phải: Khung Welcome 👋, nhập Email & Password, nút Login màu cam nổi bật,
///   loại bỏ nút FB, Google, Quên mật khẩu theo đúng yêu cầu người dùng.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

enum _AuthMode { login, register }

class _AuthScreenState extends State<AuthScreen> {
  // Bảng màu thiết kế theo ảnh mẫu
  static const Color _cardBg = Color(0xFF1E232B);
  static const Color _fieldBg = Color(0xFF282D37);
  static const Color _borderField = Color(0xFF353C4A);
  static const Color _primaryOrange = Color(0xFFE65100);
  static const Color _brightOrange = Color(0xFFF97316);
  static const Color _textMuted = Color(0xFF94A3B8);

  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  final _nameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passFocus = FocusNode();

  _AuthMode _mode = _AuthMode.login;
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  bool get _isRegister => _mode == _AuthMode.register;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusFirstField();
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _nameFocus.dispose();
    _emailFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  void _focusFirstField() {
    if (_isRegister) {
      _nameFocus.requestFocus();
    } else {
      _emailFocus.requestFocus();
    }
  }

  void _switchMode(_AuthMode mode) {
    if (_loading || mode == _mode) return;
    AudioService.instance.playSfx(SfxSound.uiClick);
    setState(() {
      _mode = mode;
      _error = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusFirstField();
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    AudioService.instance.playSfx(SfxSound.uiClick);
    setState(() {
      _loading = true;
      _error = null;
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
      if (!mounted) return;
      setState(() => _error = e.message);
      if (!_isRegister) {
        _passCtrl.clear();
        _passFocus.requestFocus();
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Đã xảy ra lỗi: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070403),
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Nền chuyển sắc ấm áp tỏa hào quang cam hổ phách
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.0, -0.05),
                  radius: 1.15,
                  colors: [
                    const Color(0xFF3E1705), // Vùng sáng ấm trung tâm
                    const Color(0xFF220C03),
                    const Color(0xFF110602),
                    const Color(0xFF070302),
                  ],
                  stops: const [0.0, 0.35, 0.70, 1.0],
                ),
              ),
            ),
          ),

          // 2. Khung thẻ chính (Card)
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 640;
                final isCompact = constraints.maxHeight < 460;
                final cardWidth = math.min(760.0, constraints.maxWidth - 28.0);

                return Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: isCompact ? 8 : 18,
                    ),
                    child: Container(
                      width: cardWidth,
                      constraints: BoxConstraints(
                        minHeight: isWide ? (isCompact ? 330 : 380) : 0,
                      ),
                      decoration: BoxDecoration(
                        color: _cardBg,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: const Color(0xFF2D3442),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.65),
                            blurRadius: 36,
                            spreadRadius: 4,
                            offset: const Offset(0, 10),
                          ),
                          BoxShadow(
                            color: _primaryOrange.withValues(alpha: 0.15),
                            blurRadius: 28,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: isWide
                          ? _buildHorizontalLayout(isCompact: isCompact)
                          : _buildVerticalLayout(isCompact: isCompact),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Bố cục 2 cột nằm ngang (chuẩn cho màn hình landscape điện thoại & web)
  Widget _buildHorizontalLayout({required bool isCompact}) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cột trái: Hình ảnh Chibi Rồng Lửa tươi sáng
          Expanded(
            flex: 10,
            child: _buildChibiDragonIllustration(),
          ),

          // Cột phải: Form Đăng nhập / Đăng ký
          Expanded(
            flex: 12,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                isCompact ? 22 : 32,
                isCompact ? 18 : 28,
                isCompact ? 24 : 34,
                isCompact ? 18 : 26,
              ),
              child: _buildAuthForm(isCompact: isCompact),
            ),
          ),
        ],
      ),
    );
  }

  /// Bố cục xếp chồng dọc dự phòng nếu màn hình rất hẹp
  Widget _buildVerticalLayout({required bool isCompact}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 160,
          child: _buildChibiDragonIllustration(),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: _buildAuthForm(isCompact: isCompact),
        ),
      ],
    );
  }

  Widget _buildChibiDragonIllustration() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Ảnh Rồng Chibi lửa tươi sáng
        Image.asset(
          'assets/images/ui/chibi_dragon_login.png',
          fit: BoxFit.cover,
          alignment: Alignment.center,
          errorBuilder: (context, error, stackTrace) {
            // Dự phòng nếu ảnh chưa nạp xong
            return Container(
              color: const Color(0xFF151922),
              child: const Center(
                child: Icon(
                  Icons.local_fire_department_rounded,
                  color: _brightOrange,
                  size: 64,
                ),
              ),
            );
          },
        ),

        // Gradient hòa sắc mờ êm dịu sang cột form bên phải (giống ảnh mẫu)
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.transparent,
                  Colors.transparent,
                  _cardBg.withValues(alpha: 0.4),
                  _cardBg,
                ],
                stops: const [0.0, 0.65, 0.90, 1.0],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Form đăng nhập / đăng ký
  Widget _buildAuthForm({required bool isCompact}) {
    final online = AuthService.instance.isAvailable;

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tiêu đề Welcome 👋
          Row(
            children: [
              Text(
                _isRegister ? 'Welcome' : 'Welcome',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isCompact ? 24.0 : 28.0,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _isRegister ? '⚔️' : '👋',
                style: TextStyle(fontSize: isCompact ? 22.0 : 26.0),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Lời giới thiệu ngắn
          Text(
            _isRegister
                ? 'Tạo tài khoản để tham gia chiến trường Big-War'
                : 'Please enter your email and password',
            style: TextStyle(
              color: _textMuted,
              fontSize: isCompact ? 11.5 : 12.5,
              fontWeight: FontWeight.w400,
            ),
          ),
          SizedBox(height: isCompact ? 14 : 20),

          if (!online) ...[
            _buildAlertBanner(
              'Không kết nối được máy chủ. Vui lòng kiểm tra mạng rồi thử lại.',
              Colors.orangeAccent,
              Icons.wifi_off_rounded,
            ),
            const SizedBox(height: 10),
          ],

          if (_error != null) ...[
            _buildAlertBanner(
              _error!,
              const Color(0xFFEF4444),
              Icons.error_outline_rounded,
            ),
            const SizedBox(height: 10),
          ],

          // Trường 0 (Khi Đăng ký): Chiến danh (không trùng lặp)
          if (_isRegister) ...[
            _buildPillField(
              controller: _nameCtrl,
              focusNode: _nameFocus,
              placeholder: 'Tên nhân vật duy nhất (3–16 ký tự)',
              icon: Icons.shield_outlined,
              action: TextInputAction.next,
              isCompact: isCompact,
              onSubmitted: (_) => _emailFocus.requestFocus(),
              validator: AuthService.validateDisplayName,
            ),
            SizedBox(height: isCompact ? 8 : 12),
          ],

          // Trường 1: Gmail (@gmail.com)
          _buildPillField(
            controller: _emailCtrl,
            focusNode: _emailFocus,
            placeholder: 'Gmail (VD: tenban@gmail.com)',
            icon: Icons.alternate_email_rounded,
            keyboard: TextInputType.emailAddress,
            action: TextInputAction.next,
            isCompact: isCompact,
            autofill: const [AutofillHints.email],
            onSubmitted: (_) => _passFocus.requestFocus(),
            validator: AuthService.validateGmail,
          ),
          SizedBox(height: isCompact ? 8 : 12),

          // Trường 2: Password
          _buildPillField(
            controller: _passCtrl,
            focusNode: _passFocus,
            placeholder: 'Password',
            icon: Icons.lock_outline_rounded,
            obscure: _obscure,
            action: TextInputAction.done,
            isCompact: isCompact,
            autofill: [
              _isRegister ? AutofillHints.newPassword : AutofillHints.password,
            ],
            onSubmitted: (_) => _submit(),
            trailingButton: Tooltip(
              message: _obscure ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
              child: IconButton(
                iconSize: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: const Color(0xFF64748B),
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            validator: (v) {
              final s = v ?? '';
              if (s.isEmpty) return 'Chưa nhập mật khẩu';
              if (s.length < 6) return 'Mật khẩu cần ít nhất 6 ký tự';
              return null;
            },
          ),
          SizedBox(height: isCompact ? 14 : 20),

          // Nút bấm cam đậm (Login / Register) đúng chuẩn ảnh mẫu
          SizedBox(
            width: double.infinity,
            height: isCompact ? 40.0 : 45.0,
            child: ElevatedButton(
              onPressed: (_loading || !online) ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryOrange,
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFF5A2A14),
                disabledForegroundColor: Colors.white54,
                elevation: 3,
                shadowColor: _primaryOrange.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      _isRegister ? 'Register' : 'Login',
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
            ),
          ),
          SizedBox(height: isCompact ? 12 : 18),

          // Dòng link chuyển đổi (Don't have an account? Register now!)
          Center(
            child: GestureDetector(
              onTap: _loading
                  ? null
                  : () => _switchMode(
                        _isRegister ? _AuthMode.login : _AuthMode.register,
                      ),
              child: Text.rich(
                TextSpan(
                  text: _isRegister
                      ? 'Already have an account? '
                      : "Don't have an account? ",
                  style: TextStyle(
                    color: _textMuted,
                    fontSize: isCompact ? 11.5 : 12.5,
                  ),
                  children: [
                    TextSpan(
                      text: _isRegister ? 'Login now!' : 'Register now!',
                      style: const TextStyle(
                        color: _brightOrange,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Ô nhập liệu phong cách bo tròn phẳng hiện đại
  Widget _buildPillField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String placeholder,
    required IconData icon,
    bool obscure = false,
    bool isCompact = false,
    TextInputType? keyboard,
    TextInputAction? action,
    Iterable<String>? autofill,
    Widget? trailingButton,
    String? Function(String?)? validator,
    void Function(String)? onSubmitted,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscure,
      keyboardType: keyboard,
      textInputAction: action,
      autofillHints: autofill,
      enabled: !_loading,
      validator: validator,
      onFieldSubmitted: onSubmitted,
      style: const TextStyle(
        color: Color(0xFFF8FAFC),
        fontSize: 13.5,
        fontWeight: FontWeight.w500,
      ),
      cursorColor: _brightOrange,
      decoration: InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: isCompact ? 10 : 13,
        ),
        prefixIcon: Icon(
          icon,
          size: 18,
          color: const Color(0xFF64748B),
        ),
        suffixIcon: trailingButton,
        hintText: placeholder,
        hintStyle: const TextStyle(
          color: Color(0xFF64748B),
          fontSize: 13.0,
          fontWeight: FontWeight.w400,
        ),
        filled: true,
        fillColor: _fieldBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: const BorderSide(color: _borderField, width: 1.0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: const BorderSide(color: _borderField, width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: const BorderSide(color: _brightOrange, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.6),
        ),
        errorStyle: const TextStyle(
          color: Color(0xFFFCA5A5),
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildAlertBanner(String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFFF1F5F9),
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
