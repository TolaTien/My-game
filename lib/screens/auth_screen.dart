import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../services/audio_service.dart';
import '../services/auth_service.dart';
import 'lobby_screen.dart';

/// Màn hình Đăng nhập / Đăng ký Tạo tài khoản của BIG-WAR.
/// Thiết kế bám sát bố cục cổng game RPG kinh điển từ ảnh tham chiếu nhưng theo
/// phong cách chiến trường hầm hố (Rồng Chiến Thần trấn giữ bên trái, Pháo Đài
/// bên phải, Cặp Hộ Vệ giao chiến phía dưới, Logo BIG-WAR rực lửa góc trên phải,
/// Bảng lệnh Giáp Hoàng Kim ở trung tâm).
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

enum _AuthMode { login, register }

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  // --- BRAND TOKENS (Đồng bộ bảng màu Hoàng Kim – Nham Thạch – Thép Titan) ---
  static const Color _gold = Color(0xFFFFD54F);
  static const Color _goldBright = Color(0xFFFEF08A);
  static const Color _jade = Color(0xFF10B981);
  static const Color _bgSkyTop = Color(0xFF0A2239);
  static const Color _textPrimary = Color(0xFFECFDF5);
  static const String? _brandFontFamily = null; // Đổi tên font tại đây nếu cần

  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  final _nameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passFocus = FocusNode();

  late final AnimationController _sceneCtrl;

  _AuthMode _mode = _AuthMode.login;
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  bool get _isRegister => _mode == _AuthMode.register;

  @override
  void initState() {
    super.initState();
    _sceneCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusFirstField();
    });
  }

  @override
  void dispose() {
    _sceneCtrl.dispose();
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

  static bool _isValidEmail(String v) =>
      RegExp(r'^[\w.+\-]+@[\w\-]+(\.[\w\-]+)+$').hasMatch(v.trim());

  // ---------------------------------------------------------------------------
  // UI BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgSkyTop,
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Toàn bộ bối cảnh Thế Giới Chiến Trường BIG-WAR tự vẽ bằng Canvas
          //    (Bầu trời chiến họa, Rồng Chiến Thần khổng lồ bên trái, Pháo Đài
          //    bên phải, Đồi chiến trường & 2 Hộ Vệ giao chiến bên dưới)
          AnimatedBuilder(
            animation: _sceneCtrl,
            builder: (context, _) {
              return CustomPaint(
                painter: _BigWarScenePainter(
                  time: _sceneCtrl.value * 2 * math.pi,
                ),
              );
            },
          ),

          // 2. Lớp giao diện tương tác (Logo BIG-WAR góc trên phải + Bảng lệnh giữa màn)
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 680;

                if (!isWide) {
                  return Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildBigWarLogo(compact: true),
                          const SizedBox(height: 10),
                          _buildCentralCommandBox(isWide: false),
                        ],
                      ),
                    ),
                  );
                }

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Góc trên phải: Logo BIG-WAR kèm Hỏa Cầu Chiến Thần (đúng vị trí ảnh mẫu)
                    Positioned(
                      top: 12,
                      right: math.max(24, constraints.maxWidth * 0.08),
                      child: _buildBigWarLogo(compact: false),
                    ),

                    // Trung tâm hơi chếch phải (nhường không gian bên trái cho Rồng Chiến Thần
                    // và bên dưới cho 2 Hộ Vệ giao chiến, đúng bố cục ảnh mẫu)
                    Align(
                      alignment: const Alignment(0.10, -0.10),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: _buildCentralCommandBox(isWide: true),
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

  /// Cụm Logo BIG-WAR góc trên phải với Quả Cầu Hỏa Ngục cháy rực phía trên
  Widget _buildBigWarLogo({required bool compact}) {
    final titleSize = compact ? 30.0 : 40.0;
    final orbSize = compact ? 44.0 : 58.0;

    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Quả cầu lửa bốc cháy phía trên góc phải chữ BIG-WAR (như ảnh mẫu)
          Positioned(
            top: compact ? -14 : -20,
            right: compact ? 8 : 12,
            child: SizedBox(
              width: orbSize,
              height: orbSize,
              child: CustomPaint(
                painter: _BlazingWarOrbPainter(),
              ),
            ),
          ),

          Padding(
            padding: EdgeInsets.only(top: compact ? 10 : 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  children: [
                    // Lớp viền ngọc lục bảo tối dày tạo khối 3D hầm hố đồng bộ Rồng Chiến Thần
                    Text(
                      'BIG-WAR',
                      style: TextStyle(
                        fontFamily: _brandFontFamily,
                        fontSize: titleSize,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3.0,
                        height: 1.0,
                        foreground: Paint()
                          ..style = PaintingStyle.stroke
                          ..strokeWidth = 6.0
                          ..strokeJoin = StrokeJoin.round
                          ..color = const Color(0xFF042F2E),
                      ),
                    ),
                    // Lớp viền lục bảo phát sáng thứ hai
                    Text(
                      'BIG-WAR',
                      style: TextStyle(
                        fontFamily: _brandFontFamily,
                        fontSize: titleSize,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3.0,
                        height: 1.0,
                        foreground: Paint()
                          ..style = PaintingStyle.stroke
                          ..strokeWidth = 2.6
                          ..strokeJoin = StrokeJoin.round
                          ..color = _jade,
                      ),
                    ),
                    // Mặt chữ kim loại Hoàng Kim – Ngọc Lục Bảo chuyển sắc
                    ShaderMask(
                      shaderCallback: (rect) => const LinearGradient(
                        colors: [
                          Color(0xFFFFFFFF),
                          _goldBright,
                          _gold,
                          Color(0xFF34D399),
                        ],
                        stops: [0.0, 0.35, 0.72, 1.0],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ).createShader(rect),
                      child: Text(
                        'BIG-WAR',
                        style: TextStyle(
                          fontFamily: _brandFontFamily,
                          color: Colors.white,
                          fontSize: titleSize,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 3.0,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xE6260B03),
                        Color(0xE6451505),
                        Color(0xE6260B03),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: _gold.withValues(alpha: 0.85),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF5722).withValues(alpha: 0.35),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.sports_kabaddi_rounded,
                        color: _goldBright,
                        size: 11,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'ĐẤU TRƯỜNG SINH TỬ',
                        style: TextStyle(
                          fontFamily: _brandFontFamily,
                          color: _goldBright,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.6,
                        ),
                      ),
                      SizedBox(width: 5),
                      Icon(
                        Icons.sports_kabaddi_rounded,
                        color: _goldBright,
                        size: 11,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Bảng lệnh Đăng nhập / Tạo tài khoản trung tâm phong cách Chiến Giáp Hầm Hố
  Widget _buildCentralCommandBox({required bool isWide}) {
    final online = AuthService.instance.isAvailable;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: isWide ? 415 : 380),
      child: CustomPaint(
        painter: _OrnateRpgBoxPainter(
          isRegister: _isRegister,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 24, 26, 22),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Tiêu đề trạng thái cổng chiến trường dập nổi hầm hố
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 28,
                      height: 2.0,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.transparent, Color(0xFFFFB300)],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      _isRegister
                          ? Icons.local_fire_department_rounded
                          : Icons.shield_rounded,
                      color: _isRegister ? const Color(0xFFFF7043) : _goldBright,
                      size: 19,
                      shadows: [
                        BoxShadow(
                          color: _isRegister ? const Color(0xFFFF5722) : _gold,
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    const SizedBox(width: 7),
                    Text(
                      _isRegister
                          ? 'TẠO TÀI KHOẢN CHIẾN BINH'
                          : 'ĐĂNG NHẬP CHIẾN TRƯỜNG',
                      style: const TextStyle(
                        fontFamily: _brandFontFamily,
                        color: _goldBright,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
                        shadows: [
                          Shadow(
                            color: Color(0xFFE65100),
                            blurRadius: 8,
                            offset: Offset(0, 1),
                          ),
                          Shadow(
                            color: Colors.black,
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 28,
                      height: 2.0,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFFFFB300), Colors.transparent],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                if (!online) ...[
                  _buildBanner(
                    'Không kết nối được máy chủ. Vui lòng kiểm tra mạng rồi thử lại.',
                    Colors.orangeAccent,
                    Icons.wifi_off_rounded,
                  ),
                  const SizedBox(height: 10),
                ],

                // Hàng 0 (Khi Đăng ký): Chiến danh
                if (_isRegister) ...[
                  _buildRpgFieldRow(
                    label: 'Chiến danh',
                    icon: Icons.military_tech_rounded,
                    controller: _nameCtrl,
                    focusNode: _nameFocus,
                    placeholder: 'Nhập tên nhân vật (3–16 ký tự)',
                    action: TextInputAction.next,
                    onSubmitted: (_) => _emailFocus.requestFocus(),
                    validator: (v) {
                      final s = v?.trim() ?? '';
                      if (s.isEmpty) return 'Chưa nhập tên nhân vật';
                      if (s.length < 3 || s.length > 16) {
                        return 'Tên nhân vật cần từ 3 đến 16 ký tự';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 11),
                ],

                // Hàng 1: Tài khoản
                _buildRpgFieldRow(
                  label: 'Tài khoản',
                  icon: Icons.badge_rounded,
                  controller: _emailCtrl,
                  focusNode: _emailFocus,
                  placeholder: 'Nhập email chiến binh',
                  keyboard: TextInputType.emailAddress,
                  action: TextInputAction.next,
                  autofill: const [AutofillHints.email],
                  onSubmitted: (_) => _passFocus.requestFocus(),
                  validator: (v) {
                    final s = v?.trim() ?? '';
                    if (s.isEmpty) return 'Chưa nhập email';
                    if (!_isValidEmail(s)) {
                      return 'Email phải có dấu @ và tên miền hợp lệ';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 11),

                // Hàng 2: Mật khẩu
                _buildRpgFieldRow(
                  label: 'Mật khẩu',
                  icon: Icons.lock_rounded,
                  controller: _passCtrl,
                  focusNode: _passFocus,
                  placeholder: _isRegister
                      ? 'Tạo mật khẩu (tối thiểu 6 ký tự)'
                      : 'Nhập mật khẩu',
                  obscure: _obscure,
                  action: TextInputAction.done,
                  autofill: [
                    _isRegister
                        ? AutofillHints.newPassword
                        : AutofillHints.password,
                  ],
                  onSubmitted: (_) => _submit(),
                  trailingButton: Tooltip(
                    message: _obscure ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => setState(() => _obscure = !_obscure),
                      child: Container(
                        width: 36,
                        height: 42,
                        margin: const EdgeInsets.only(left: 6),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF2E1908), Color(0xFF140B04)],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: const Color(0xFFFFB300).withValues(alpha: 0.8),
                            width: 1.3,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFF6F00).withValues(alpha: 0.25),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Icon(
                          _obscure
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded,
                          color: _goldBright,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                  validator: (v) {
                    final s = v ?? '';
                    if (s.isEmpty) return 'Chưa nhập mật khẩu';
                    if (s.length < 6) return 'Mật khẩu cần ít nhất 6 ký tự';
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                if (_error != null) ...[
                  _buildBanner(
                    _error!,
                    const Color(0xFFFF5252),
                    Icons.error_outline_rounded,
                  ),
                  const SizedBox(height: 12),
                ],

                // Nút hành động chính dập nổi Hoàng Kim chiến đấu
                Center(
                  child: _buildEmbossedSubmitButton(online: online),
                ),
                const SizedBox(height: 12),

                // Link chuyển đổi chế độ ("Đăng ký" / "Đăng nhập") dưới nút chính
                _buildFooterLinks(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Hàng nhãn bên trái + ô nhập bên phải thiết kế theo khoang giáp chiến thuật
  Widget _buildRpgFieldRow({
    required String label,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String placeholder,
    IconData? icon,
    bool obscure = false,
    TextInputType? keyboard,
    TextInputAction? action,
    Iterable<String>? autofill,
    Widget? trailingButton,
    String? Function(String?)? validator,
    void Function(String)? onSubmitted,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: const BorderSide(
        color: Color(0xFF3B4861),
        width: 1.4,
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Nhãn bên trái dập nổi viền đen bóng đêm kèm icon chiến binh
        SizedBox(
          width: 98,
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 15,
                    color: _goldBright,
                  ),
                  const SizedBox(width: 5),
                ],
                Expanded(
                  child: Stack(
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontFamily: _brandFontFamily,
                          fontSize: 13.0,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                          foreground: Paint()
                            ..style = PaintingStyle.stroke
                            ..strokeWidth = 3.2
                            ..color = const Color(0xFF0F0500),
                        ),
                      ),
                      Text(
                        label,
                        style: const TextStyle(
                          fontFamily: _brandFontFamily,
                          color: _goldBright,
                          fontSize: 13.0,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Ô nhập chính thiết kế theo khoang giáp Titan Đen
        Expanded(
          child: TextFormField(
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
              fontFamily: _brandFontFamily,
              color: Color(0xFFF8FAFC),
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
            cursorColor: _gold,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 11,
              ),
              hintText: placeholder,
              hintStyle: const TextStyle(
                fontFamily: _brandFontFamily,
                color: Color(0xFF64748B),
                fontSize: 12.0,
                fontWeight: FontWeight.w400,
              ),
              filled: true,
              fillColor: const Color(0xFF070B16),
              border: border,
              enabledBorder: border,
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(
                  color: Color(0xFFFFB300),
                  width: 2.0,
                ),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(
                  color: Color(0xFFEF4444),
                  width: 1.6,
                ),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(
                  color: Color(0xFFEF4444),
                  width: 2.0,
                ),
              ),
              errorStyle: const TextStyle(
                fontFamily: _brandFontFamily,
                color: Color(0xFFFCA5A5),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),

        ?trailingButton,
      ],
    );
  }

  /// Nút bấm chiến đấu dập nổi Hoàng Kim – Hỏa Ngục cực kỳ hầm hố
  Widget _buildEmbossedSubmitButton({required bool online}) {
    final disabled = _loading || !online;
    return SizedBox(
      width: 235,
      height: 48,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: disabled
              ? LinearGradient(
                  colors: [
                    const Color(0xFF5A4A32).withValues(alpha: 0.5),
                    const Color(0xFF261D12).withValues(alpha: 0.5),
                  ],
                )
              : const LinearGradient(
                  colors: [
                    Color(0xFFFFF9C4), // Ánh kim đỉnh nút
                    Color(0xFFFFD54F), // Vàng kim rực rỡ
                    Color(0xFFFF8F00), // Cam hoàng kim
                    Color(0xFFE65100), // Lửa chiến trận
                    Color(0xFF3E1205), // Khối đáy 3D
                  ],
                  stops: [0.0, 0.22, 0.55, 0.88, 1.0],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: disabled ? Colors.white24 : const Color(0xFFFFF176),
            width: 2.2,
          ),
          boxShadow: disabled
              ? null
              : [
                  const BoxShadow(
                    color: Color(0xFF1B0702),
                    blurRadius: 0,
                    offset: Offset(0, 4),
                  ),
                  BoxShadow(
                    color: const Color(0xFFFF6D00).withValues(alpha: 0.55),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ],
        ),
        child: ElevatedButton(
          onPressed: disabled ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: _loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.8,
                    color: Color(0xFF200B02),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isRegister
                          ? Icons.local_fire_department_rounded
                          : Icons.sports_kabaddi_rounded,
                      color: const Color(0xFF200B02),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Stack(
                      children: [
                        Text(
                          _isRegister ? 'TẠO TÀI KHOẢN' : 'ĐĂNG NHẬP',
                          style: TextStyle(
                            fontFamily: _brandFontFamily,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            foreground: Paint()
                              ..style = PaintingStyle.stroke
                              ..strokeWidth = 3.6
                              ..color = const Color(0xFFFFF9C4),
                          ),
                        ),
                        Text(
                          _isRegister ? 'TẠO TÀI KHOẢN' : 'ĐĂNG NHẬP',
                          style: const TextStyle(
                            fontFamily: _brandFontFamily,
                            color: Color(0xFF2E0D03),
                            fontSize: 15.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      _isRegister
                          ? Icons.local_fire_department_rounded
                          : Icons.sports_kabaddi_rounded,
                      color: const Color(0xFF200B02),
                      size: 20,
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  /// Link chuyển đổi chế độ ("Đăng ký" / "Đăng nhập") căn giữa bên dưới nút chính
  Widget _buildFooterLinks() {
    return Center(
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: _loading
            ? null
            : () => _switchMode(
                  _isRegister ? _AuthMode.login : _AuthMode.register,
                ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _gold.withValues(alpha: 0.4),
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isRegister ? Icons.login_rounded : Icons.person_add_alt_1_rounded,
                size: 14,
                color: _goldBright,
              ),
              const SizedBox(width: 6),
              Text(
                _isRegister
                    ? 'Đã có tài khoản? Đăng nhập'
                    : 'Chưa có tài khoản? Đăng ký ngay',
                style: const TextStyle(
                  fontFamily: _brandFontFamily,
                  color: _goldBright,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  decoration: TextDecoration.underline,
                  decorationColor: _gold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBanner(String text, Color color, IconData icon) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: color.withValues(alpha: 0.7)),
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
                  fontFamily: _brandFontFamily,
                  color: _textPrimary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// CUSTOM PAINTERS — THẾ GIỚI BIG-WAR (RỒNG CHIẾN THẦN, PHÁO ĐÀI, 2 HỘ VỆ, KHUNG GIÁP)
// =============================================================================

/// Vẽ khung bảng lệnh RPG viền Giáp Hoàng Kim Chiến Trận hầm hố (Vát góc 45 độ, đinh tán cơ khí, ngàm kẹp thép)
class _OrnateRpgBoxPainter extends CustomPainter {
  final bool isRegister;

  const _OrnateRpgBoxPainter({required this.isRegister});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;
    const c = 14.0; // Độ vát góc 45 độ

    // Đường viền bát giác vát góc chiến trận
    final chamferPath = Path()
      ..moveTo(c, 0)
      ..lineTo(w - c, 0)
      ..lineTo(w, c)
      ..lineTo(w, h - c)
      ..lineTo(w - c, h)
      ..lineTo(c, h)
      ..lineTo(0, h - c)
      ..lineTo(0, c)
      ..close();

    // 1. Đổ bóng sâu & Hào quang lửa nham thạch rực sáng phía sau
    canvas.drawShadow(chamferPath, const Color(0xFF000000), 24, true);
    canvas.drawPath(
      chamferPath,
      Paint()
        ..color = const Color(0xFFFF5722).withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
    );

    // 2. Tấm giáp Titan Hắc Kim nguyên khối (Độ sâu tương phản cao > 12:1)
    canvas.drawPath(
      chamferPath,
      Paint()
        ..shader = const LinearGradient(
          colors: [
            Color(0xF5131C2E), // Thép titan góc trên trái
            Color(0xF80A101C), // Hắc kim lõi trung tâm
            Color(0xFA050810), // Đen bóng đêm đáy
            Color(0xF6101827), // Phản quang góc phải
          ],
          stops: [0.0, 0.45, 0.85, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(rect),
    );

    // 3. Viền giáp ngoài đúc Hoàng Kim – Hỏa Ngục dập nổi (3.2px)
    canvas.drawPath(
      chamferPath,
      Paint()
        ..shader = const LinearGradient(
          colors: [
            Color(0xFFFFF9C4), // Vàng kim sáng
            Color(0xFFFFD54F),
            Color(0xFFFF8F00), // Cam hoàng kim
            Color(0xFFFF3D00), // Lửa chiến trường
            Color(0xFFFFD54F),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2,
    );

    // 4. Viền rãnh năng lượng dạ quang bên trong (Inner Energy Inset Line)
    final innerPath = Path()
      ..moveTo(c + 4, 6)
      ..lineTo(w - c - 4, 6)
      ..lineTo(w - 6, c + 4)
      ..lineTo(w - 6, h - c - 4)
      ..lineTo(w - c - 4, h - 6)
      ..lineTo(c + 4, h - 6)
      ..lineTo(6, h - c - 4)
      ..lineTo(6, c + 4)
      ..close();

    canvas.drawPath(
      innerPath,
      Paint()
        ..color = const Color(0xFFFFB300).withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // 5. Đinh tán cơ khí thép dập nổi 3D tại 8 vị trí chiến thuật
    final rivetPositions = [
      const Offset(c + 2, c + 2),
      Offset(w - c - 2, c + 2),
      Offset(c + 2, h - c - 2),
      Offset(w - c - 2, h - c - 2),
      Offset(w / 2, 5),
      Offset(w / 2, h - 5),
      Offset(5, h / 2),
      Offset(w - 5, h / 2),
    ];

    for (final pos in rivetPositions) {
      // Vòng đệm kim loại ngoài
      canvas.drawCircle(
        pos,
        4.0,
        Paint()..color = const Color(0xFFD4AF37),
      );
      // Tâm đinh tán đổ bóng tạo khối 3D
      canvas.drawCircle(
        pos + const Offset(-0.8, -0.8),
        2.2,
        Paint()..color = const Color(0xFFFFF9C4),
      );
      canvas.drawCircle(
        pos + const Offset(0.6, 0.6),
        1.6,
        Paint()..color = const Color(0xFF3E1205),
      );
    }

    // 6. Ngàm thép cường lực ở 2 bên sườn khung kèm vạch chiến thuật Chevrons
    void drawArmorBracket(double x, double y, bool isLeft) {
      const bracketW = 8.0;
      const bracketH = 36.0;
      final bRect = Rect.fromCenter(
        center: Offset(x, y),
        width: bracketW,
        height: bracketH,
      );
      // Nền ngàm thép
      canvas.drawRRect(
        RRect.fromRectAndRadius(bRect, const Radius.circular(2)),
        Paint()..color = const Color(0xFF263238),
      );
      // Viền ngàm vàng kim
      canvas.drawRRect(
        RRect.fromRectAndRadius(bRect, const Radius.circular(2)),
        Paint()
          ..color = const Color(0xFFFFD54F)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
      // 3 Vạch khía chiến thuật
      final linePaint = Paint()
        ..color = const Color(0xFFFF8F00)
        ..strokeWidth = 1.5;
      for (int i = -1; i <= 1; i++) {
        canvas.drawLine(
          Offset(x - 2, y + i * 8),
          Offset(x + 2, y + i * 8),
          linePaint,
        );
      }
    }

    drawArmorBracket(3.5, h * 0.35, true);
    drawArmorBracket(3.5, h * 0.65, true);
    drawArmorBracket(w - 3.5, h * 0.35, false);
    drawArmorBracket(w - 3.5, h * 0.65, false);

    // 7. Huy hiệu Chiến Trận trên đỉnh (Top Battle Crest)
    final crestPath = Path()
      ..moveTo(w / 2 - 20, 0)
      ..lineTo(w / 2, -7)
      ..lineTo(w / 2 + 20, 0)
      ..lineTo(w / 2, 7)
      ..close();
    canvas.drawPath(
      crestPath,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFFFF9C4), Color(0xFFFF8F00)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(w / 2 - 20, -7, 40, 14)),
    );
    canvas.drawPath(
      crestPath,
      Paint()
        ..color = const Color(0xFF3E1205)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
  }

  @override
  bool shouldRepaint(covariant _OrnateRpgBoxPainter oldDelegate) =>
      oldDelegate.isRegister != isRegister;
}

/// Vẽ Quả Cầu Lửa Chiến Thần trên đỉnh chữ BIG-WAR
class _BlazingWarOrbPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.58);
    final r = size.width * 0.34;

    // Ngọn lửa hồng-đỏ rực cháy bốc lên trên quả cầu (giống quả cầu lửa trên logo ảnh mẫu)
    final outerFlame = Path()
      ..moveTo(center.dx - r * 0.95, center.dy)
      ..quadraticBezierTo(
        center.dx - r * 1.15,
        center.dy - r * 1.2,
        center.dx - r * 0.35,
        center.dy - r * 1.65,
      )
      ..quadraticBezierTo(
        center.dx - r * 0.1,
        center.dy - r * 1.1,
        center.dx + r * 0.1,
        center.dy - r * 1.85,
      )
      ..quadraticBezierTo(
        center.dx + r * 0.55,
        center.dy - r * 1.35,
        center.dx + r * 0.45,
        center.dy - r * 0.95,
      )
      ..quadraticBezierTo(
        center.dx + r * 1.1,
        center.dy - r * 1.15,
        center.dx + r * 0.95,
        center.dy,
      )
      ..close();

    canvas.drawPath(
      outerFlame,
      Paint()
        ..shader = const LinearGradient(
          colors: [
            Color(0xFFFFF59D),
            Color(0xFFFF4081),
            Color(0xFFD50000),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromCircle(center: center, radius: r * 1.8)),
    );

    // Quả cầu ngọc hồng-đỏ phát sáng
    final orbRect = Rect.fromCircle(center: center, radius: r);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.3, -0.35),
          colors: [
            Color(0xFFFFFFFF),
            Color(0xFFFF80AB),
            Color(0xFFC51162),
            Color(0xFF4A0025),
          ],
          stops: [0.0, 0.25, 0.72, 1.0],
        ).createShader(orbRect),
    );
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = const Color(0xFFFFF59D)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
  }

  @override
  bool shouldRepaint(covariant _BlazingWarOrbPainter oldDelegate) => false;
}

/// Vẽ toàn bộ bối cảnh Chiến Trường BIG-WAR dựa trên bố cục ảnh tham chiếu:
/// - Bầu trời chiến họa, Mặt trăng/Thiên cầu khổng lồ & Mây tầng
/// - Rồng Chiến Thần Lục Bảo – Hắc Ám khổng lồ sải cánh bên trái
/// - Pháo Đài / Tháp Chiến Trận mái ngói lam thép bên phải
/// - Đồi núi, nấm/tinh thể ma thuật góc trái dưới & Thảm cỏ chiến trường
/// - Cặp Hộ Vệ (Tinh Linh Hỏa Vũ & Ác Quỷ Lôi Dực) giao chiến dưới khung đăng nhập
class _BigWarScenePainter extends CustomPainter {
  final double time;

  const _BigWarScenePainter({required this.time});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. BẦU TRỜI CHIẾN TRƯỜNG (Chuyển sắc Lam Ngọc – Chàm Sâu)
    final skyRect = Offset.zero & size;
    canvas.drawRect(
      skyRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0A2239),
            Color(0xFF13405E),
            Color(0xFF1F6E7A),
            Color(0xFF2B8C7E),
          ],
          stops: [0.0, 0.4, 0.75, 1.0],
        ).createShader(skyRect),
    );

    // 2. THIÊN CẦU / MẶT TRĂNG KHỔNG LỒ MỜ ẢO PHÍA SAU (như vòng cung mặt trăng lớn trong ảnh mẫu)
    final moonCenter = Offset(w * 0.34, h * 0.42);
    final moonRadius = h * 0.52;
    canvas.drawCircle(
      moonCenter,
      moonRadius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.2, -0.2),
          colors: [
            const Color(0xFFE0F7FA).withValues(alpha: 0.25),
            const Color(0xFF80DEEA).withValues(alpha: 0.12),
            Colors.transparent,
          ],
          stops: const [0.0, 0.7, 1.0],
        ).createShader(Rect.fromCircle(center: moonCenter, radius: moonRadius)),
    );

    // 3. MÂY CHIẾN TRƯỜNG TRÔI NHẸ
    _drawClouds(canvas, size);

    // 4. DÃY ĐỒI NÚI & DOANH TRẠI XA XA
    _drawDistantHillsAndVillage(canvas, size);

    // 5. PHÁO ĐÀI / LÂU ĐÀI MÁI NGÓI LAM THÉP BÊN PHẢI (như tòa nhà mái xanh bên phải ảnh mẫu)
    _drawRightFortressTower(canvas, size);

    // 6. RỒNG CHIẾN THẦN LỤC BẢO KHỔNG LỒ SẢI CÁNH BÊN TRÁI (nhân vật chính bên trái ảnh mẫu)
    _drawColossalEmeraldWarDragon(canvas, size);

    // 7. CẶP HỘ VỆ GIAO CHIẾN PHÍA DƯỚI KHUNG ĐĂNG NHẬP (Tinh Linh Hỏa Vũ vs Ác Quỷ Lôi Dực)
    _drawDuelingBottomGuardians(canvas, size);

    // 8. THẢM CỎ & TINH THỂ / NẤM MA THUẬT TIỀN CẢNH DƯỚI ĐÁY
    _drawForegroundTurfAndCrystals(canvas, size);

    // 9. TÀN LỬA CHIẾN TRƯỜNG BAY LƠ LỬNG TRONG GIÓ
    _drawWarEmbers(canvas, size);
  }

  void _drawWarEmbers(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final emberPaint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < 18; i++) {
      final seed = i * 47.13;
      final speed = 0.6 + (i % 4) * 0.25;
      final progress = (time * speed + seed) % (2 * math.pi);
      final norm = progress / (2 * math.pi);

      final x = (w * (0.04 + (i * 0.055) % 0.92) + math.sin(time * 1.5 + seed) * 22) % w;
      final y = h * (0.95 - norm * 0.90);
      final radius = 1.4 + (i % 3) * 0.8;
      final alpha = math.sin(norm * math.pi).clamp(0.0, 1.0);

      emberPaint.color = (i % 2 == 0 ? const Color(0xFFFF5722) : const Color(0xFFFFB300))
          .withValues(alpha: alpha * 0.7);
      canvas.drawCircle(Offset(x, y), radius, emberPaint);
    }
  }

  void _drawClouds(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final drift = math.sin(time * 0.5) * 14.0;
    final cloudPaint = Paint()
      ..color = const Color(0xFFE0F2FE).withValues(alpha: 0.22);

    void drawCloudBank(double cx, double cy, double scale) {
      canvas.drawCircle(Offset(cx, cy), 38 * scale, cloudPaint);
      canvas.drawCircle(Offset(cx + 30 * scale, cy + 6 * scale), 30 * scale, cloudPaint);
      canvas.drawCircle(Offset(cx - 30 * scale, cy + 8 * scale), 28 * scale, cloudPaint);
      canvas.drawCircle(Offset(cx + 55 * scale, cy + 12 * scale), 22 * scale, cloudPaint);
    }

    drawCloudBank(w * 0.16 + drift, h * 0.16, 1.3);
    drawCloudBank(w * 0.62 - drift, h * 0.14, 1.4);
    drawCloudBank(w * 0.45 + drift * 0.6, h * 0.26, 1.1);
  }

  void _drawDistantHillsAndVillage(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Đồi xa
    final farHill = Path()
      ..moveTo(0, h * 0.78)
      ..quadraticBezierTo(w * 0.18, h * 0.60, w * 0.38, h * 0.75)
      ..quadraticBezierTo(w * 0.58, h * 0.62, w * 0.82, h * 0.76)
      ..lineTo(w, h * 0.72)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      farHill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF1E564B),
            const Color(0xFF133A36),
          ],
        ).createShader(Offset.zero & size),
    );

    // Đồi gần
    final nearHill = Path()
      ..moveTo(0, h * 0.85)
      ..quadraticBezierTo(w * 0.25, h * 0.72, w * 0.52, h * 0.84)
      ..quadraticBezierTo(w * 0.75, h * 0.74, w, h * 0.82)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      nearHill,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF236B48),
            Color(0xFF14452F),
          ],
        ).createShader(Offset.zero & size),
    );

    // Các chòi canh / doanh trại chiến trường dưới chân đồi (tương ứng các ngôi nhà nhỏ trong ảnh mẫu)
    void drawBastionHouse(double x, double y, double s, Color roofColor) {
      final wallRect = Rect.fromLTWH(x, y, 46 * s, 32 * s);
      canvas.drawRect(wallRect, Paint()..color = const Color(0xFFD6C7B2));
      canvas.drawRect(
        wallRect,
        Paint()
          ..color = const Color(0xFF4A3B2C)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      // Cửa sổ phát sáng
      canvas.drawRect(
        Rect.fromLTWH(x + 16 * s, y + 10 * s, 12 * s, 12 * s),
        Paint()..color = const Color(0xFFFFD54F),
      );
      // Mái nhọn
      final roof = Path()
        ..moveTo(x - 6 * s, y)
        ..lineTo(x + 23 * s, y - 22 * s)
        ..lineTo(x + 52 * s, y)
        ..close();
      canvas.drawPath(roof, Paint()..color = roofColor);
    }

    drawBastionHouse(w * 0.16, h * 0.80, 0.95, const Color(0xFFB91C1C));
    drawBastionHouse(w * 0.03, h * 0.82, 0.78, const Color(0xFF991B1B));
    drawBastionHouse(w * 0.39, h * 0.82, 0.82, const Color(0xFFB45309));
  }

  /// Vẽ Pháo Đài / Lâu Đài mái ngói lam thép bên phải (bám sát tòa tháp mái xanh bên phải ảnh mẫu)
  void _drawRightFortressTower(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final towerLeft = w * 0.83;

    // Thân tường đá pháo đài
    final wallPath = Path()
      ..moveTo(towerLeft + 18, h * 0.42)
      ..lineTo(w + 20, h * 0.36)
      ..lineTo(w + 20, h * 0.92)
      ..lineTo(towerLeft + 8, h * 0.92)
      ..close();
    canvas.drawPath(
      wallPath,
      Paint()
        ..shader = LinearGradient(
          colors: [const Color(0xFFD6D3C4), const Color(0xFF8C887B)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ).createShader(Rect.fromLTWH(towerLeft, h * 0.35, w - towerLeft, h * 0.6)),
    );

    // Khung gỗ/thép chữ thập trên tường pháo đài
    final timberPaint = Paint()
      ..color = const Color(0xFF475569)
      ..strokeWidth = 4.0;
    canvas.drawLine(
      Offset(towerLeft + 14, h * 0.56),
      Offset(w, h * 0.53),
      timberPaint,
    );
    canvas.drawLine(
      Offset(towerLeft + 48, h * 0.42),
      Offset(towerLeft + 38, h * 0.90),
      timberPaint,
    );

    // Ô cửa sổ pháo đài phát sáng vàng kim
    final winRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(towerLeft + 58, h * 0.58, 28, 36),
      const Radius.circular(6),
    );
    canvas.drawRRect(winRect, Paint()..color = const Color(0xFFFFCA28));
    canvas.drawRRect(
      winRect,
      Paint()
        ..color = const Color(0xFF1E293B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Mái ngói lam thép dốc cao kèm chóp nhọn chiến trường
    final roofPath = Path()
      ..moveTo(towerLeft - 12, h * 0.44)
      ..lineTo(w * 0.92, h * 0.08)
      ..lineTo(w + 24, h * 0.12)
      ..lineTo(w + 24, h * 0.41)
      ..close();
    canvas.drawPath(
      roofPath,
      Paint()
        ..shader = LinearGradient(
          colors: [
            const Color(0xFF2563EB),
            const Color(0xFF1E3A8A),
            const Color(0xFF0F172A),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(Rect.fromLTWH(towerLeft, h * 0.08, w - towerLeft, h * 0.4)),
    );
    canvas.drawPath(
      roofPath,
      Paint()
        ..color = const Color(0xFF60A5FA)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    // Các đường gờ ngói ngang trên mái
    final tileLinePaint = Paint()
      ..color = const Color(0xFF93C5FD).withValues(alpha: 0.35)
      ..strokeWidth = 1.6;
    for (int i = 1; i <= 5; i++) {
      final y = h * (0.14 + i * 0.05);
      canvas.drawLine(Offset(towerLeft + (5 - i) * 12, y), Offset(w, y - 8), tileLinePaint);
    }

    // Tán cây cổ thụ rậm rạp bên sườn pháo đài
    final foliagePaint = Paint()..color = const Color(0xFF15803D);
    final foliageHighlight = Paint()..color = const Color(0xFF4ADE80);
    for (final c in [
      Offset(w * 0.96, h * 0.44),
      Offset(w * 0.93, h * 0.52),
      Offset(w * 0.97, h * 0.60),
      Offset(w * 0.94, h * 0.68),
    ]) {
      canvas.drawCircle(c, 34, foliagePaint);
      canvas.drawCircle(c + const Offset(-6, -6), 20, foliageHighlight);
    }
  }

  /// Vẽ Rồng Chiến Thần Lục Bảo – Hắc Ám khổng lồ sải cánh bên trái (như con Rồng xanh bên trái ảnh mẫu)
  void _drawColossalEmeraldWarDragon(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final breath = math.sin(time * 2.0) * 5.0;
    final wingFlap = math.sin(time * 2.0) * 12.0;
    final cx = w * 0.23;
    final cy = h * 0.46 + breath;
    final s = (h / 460.0).clamp(0.65, 1.35);

    canvas.save();
    canvas.translate(cx, cy);
    canvas.scale(s);

    // 1. Hào quang Lục Bảo Thần Long phía sau
    canvas.drawCircle(
      const Offset(0, 10),
      135,
      Paint()
        ..color = const Color(0xFF10B981).withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28),
    );

    final wingMembraneShader = const LinearGradient(
      colors: [Color(0xFFA7F3D0), Color(0xFF10B981), Color(0xFF064E3B)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ).createShader(const Rect.fromLTWH(-200, -140, 400, 240));

    final wingBonePaint = Paint()
      ..color = const Color(0xFF065F46)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.2
      ..strokeCap = StrokeCap.round;

    // 2. CÁNH RỒNG BÊN TRÁI (Sải rộng hầm hố)
    final leftWing = Path()
      ..moveTo(-25, -20)
      ..quadraticBezierTo(-110, -115 + wingFlap, -195, -85 + wingFlap)
      ..quadraticBezierTo(-155, -25 + wingFlap * 0.6, -165, 30 + wingFlap * 0.4)
      ..quadraticBezierTo(-115, 5, -95, 45)
      ..quadraticBezierTo(-55, 18, -30, 35)
      ..close();
    canvas.drawPath(leftWing, Paint()..shader = wingMembraneShader);
    canvas.drawPath(leftWing, wingBonePaint);
    // Xương cánh rồng trái
    canvas.drawLine(
      const Offset(-35, -35),
      Offset(-165, 30 + wingFlap * 0.4),
      wingBonePaint..strokeWidth = 2.5,
    );
    canvas.drawLine(
      const Offset(-35, -35),
      Offset(-95, 45),
      wingBonePaint..strokeWidth = 2.5,
    );

    // 3. CÁNH RỒNG BÊN PHẢI (Sải về phía khung đăng nhập như ảnh mẫu)
    final rightWing = Path()
      ..moveTo(25, -25)
      ..quadraticBezierTo(115, -105 + wingFlap, 185, -70 + wingFlap)
      ..quadraticBezierTo(140, -18 + wingFlap * 0.5, 130, 32 + wingFlap * 0.3)
      ..quadraticBezierTo(85, 8, 65, 40)
      ..quadraticBezierTo(40, 15, 22, 28)
      ..close();
    canvas.drawPath(rightWing, Paint()..shader = wingMembraneShader);
    canvas.drawPath(rightWing, wingBonePaint..strokeWidth = 4.0);

    // 4. ĐUÔI RỒNG GAI GÓC CUỘN PHÍA DƯỚI
    final tailPath = Path()
      ..moveTo(-25, 75)
      ..quadraticBezierTo(-115, 85, -135, 125)
      ..quadraticBezierTo(-85, 140, -15, 115)
      ..close();
    canvas.drawPath(tailPath, Paint()..color = const Color(0xFF047857));
    canvas.drawPath(tailPath, wingBonePaint..strokeWidth = 3.0);

    // 5. THÂN RỒNG & GIÁP NGỰC
    final bodyPath = Path()
      ..moveTo(-32, -35)
      ..quadraticBezierTo(-58, 45, -38, 120)
      ..lineTo(42, 120)
      ..quadraticBezierTo(58, 45, 28, -35)
      ..close();
    canvas.drawPath(
      bodyPath,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF059669), Color(0xFF064E3B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(const Rect.fromLTWH(-60, -40, 120, 160)),
    );

    // Giáp bụng rồng có vảy ngang sáng màu
    final bellyPath = Path()
      ..moveTo(-16, -20)
      ..quadraticBezierTo(-28, 45, -18, 115)
      ..lineTo(20, 115)
      ..quadraticBezierTo(30, 45, 16, -20)
      ..close();
    canvas.drawPath(bellyPath, Paint()..color = const Color(0xFFA7F3D0));
    final scaleLine = Paint()
      ..color = const Color(0xFF047857)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    for (int i = 0; i < 6; i++) {
      final sy = -5.0 + i * 20.0;
      canvas.drawArc(
        Rect.fromCenter(center: Offset(0, sy), width: 38, height: 14),
        0,
        math.pi,
        false,
        scaleLine,
      );
    }

    // 6. HAI TAY & VUỐT RỒNG SẮC NHỌN PHÍA TRƯỚC NGỰC
    for (final side in [-1.0, 1.0]) {
      final armX = side * 34;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(armX, 26), width: 22, height: 34),
          const Radius.circular(8),
        ),
        Paint()..color = const Color(0xFF047857),
      );
      // 3 móng vuốt sắc
      final clawPaint = Paint()..color = const Color(0xFFFEF08A);
      for (int c = -1; c <= 1; c++) {
        final cxOffset = armX + c * 6.0;
        final claw = Path()
          ..moveTo(cxOffset - 3, 40)
          ..lineTo(cxOffset, 54)
          ..lineTo(cxOffset + 3, 40)
          ..close();
        canvas.drawPath(claw, clawPaint);
      }
    }

    // 7. ĐẦU RỒNG, CẶP SỪNG VÀNG KIM & MẮT RỰC LỬA
    // Cặp sừng dài cong vút lên đỉnh
    final hornPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFFEF08A), Color(0xFFD97706)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(const Rect.fromLTWH(-60, -145, 120, 80));

    final leftHorn = Path()
      ..moveTo(-14, -72)
      ..quadraticBezierTo(-42, -115, -36, -145)
      ..quadraticBezierTo(-18, -110, -4, -75)
      ..close();
    final rightHorn = Path()
      ..moveTo(10, -72)
      ..quadraticBezierTo(45, -115, 52, -142)
      ..quadraticBezierTo(30, -102, 22, -70)
      ..close();
    canvas.drawPath(leftHorn, hornPaint);
    canvas.drawPath(rightHorn, hornPaint);

    // Hộp sọ & Mõm Rồng hướng sang phải
    final headPath = Path()
      ..moveTo(-24, -74)
      ..lineTo(22, -74)
      ..lineTo(48, -48)
      ..lineTo(18, -32)
      ..lineTo(-22, -40)
      ..close();
    canvas.drawPath(headPath, Paint()..color = const Color(0xFF059669));
    canvas.drawPath(
      headPath,
      Paint()
        ..color = const Color(0xFF064E3B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Mắt Rồng phát sáng Hoàng Kim - Đỏ
    final eyeGlow = Paint()
      ..color = const Color(0xFFFFD54F)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawOval(const Rect.fromLTWH(2, -62, 16, 9), eyeGlow);
    canvas.drawOval(
      const Rect.fromLTWH(4, -61, 12, 7),
      Paint()..color = const Color(0xFFFFEA00),
    );
    canvas.drawOval(
      const Rect.fromLTWH(9, -61, 4, 7),
      Paint()..color = const Color(0xFFD50000),
    );

    // 8. Làn sương mây trắng mờ dưới chân Rồng (như mây dưới chân Rồng trong ảnh mẫu)
    final mistPaint = Paint()
      ..color = const Color(0xFFE0F2FE).withValues(alpha: 0.55)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(-20, 120), width: 190, height: 38),
      mistPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(25, 124), width: 150, height: 32),
      mistPaint,
    );

    canvas.restore();
  }

  /// Vẽ 2 Hộ Vệ giao chiến phía dưới bảng đăng nhập (như Tinh Linh Hồng & Tiểu Quỷ Xanh trong ảnh mẫu)
  void _drawDuelingBottomGuardians(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final bob1 = math.sin(time * 3.0) * 5.0;
    final bob2 = math.cos(time * 3.2) * 6.0;
    final s = (h / 480.0).clamp(0.65, 1.2);

    // --- 1. HỘ VỆ TRÁI: TINH LINH HỎA VŨ (Vị trí trung tâm-dưới, cánh sáng, vòng hào quang vàng, vung quyền trượng) ---
    final leftPos = Offset(w * 0.52, h * 0.80 + bob1);
    canvas.save();
    canvas.translate(leftPos.dx, leftPos.dy);
    canvas.scale(s);

    // Đôi cánh ánh sáng phía sau
    final wingPaint = Paint()
      ..color = const Color(0xFFFCE7F3).withValues(alpha: 0.72);
    canvas.drawOval(const Rect.fromLTWH(-46, -24, 32, 20), wingPaint);
    canvas.drawOval(const Rect.fromLTWH(-42, -4, 28, 18), wingPaint);

    // Thân & Đầu Tinh Linh Hồng-Đỏ
    final spiritGrad = const RadialGradient(
      center: Alignment(-0.2, -0.3),
      colors: [Color(0xFFFFCDD2), Color(0xFFFF4081), Color(0xFFC2185B)],
    ).createShader(Rect.fromCircle(center: Offset.zero, radius: 36));
    canvas.drawCircle(const Offset(0, -10), 30, Paint()..shader = spiritGrad);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, 26), width: 34, height: 28),
      Paint()..shader = spiritGrad,
    );

    // Vòng hào quang Hoàng Kim trên đỉnh đầu
    canvas.save();
    canvas.translate(2, -48);
    canvas.rotate(-0.18);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 38, height: 11),
      Paint()
        ..color = const Color(0xFFFFD54F)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0,
    );
    canvas.restore();

    // Đôi mắt to sắc nét
    canvas.drawOval(
      const Rect.fromLTWH(-14, -14, 11, 14),
      Paint()..color = const Color(0xFF111827),
    );
    canvas.drawCircle(
      const Offset(-11, -10),
      3,
      Paint()..color = Colors.white,
    );
    canvas.drawOval(
      const Rect.fromLTWH(8, -14, 11, 14),
      Paint()..color = const Color(0xFF111827),
    );
    canvas.drawCircle(
      const Offset(11, -10),
      3,
      Paint()..color = Colors.white,
    );

    // Quyền trượng ánh sao chỉ về phía đối thủ bên phải
    canvas.drawLine(
      const Offset(18, 12),
      const Offset(56, -18),
      Paint()
        ..color = const Color(0xFFFFB300)
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      const Offset(58, -20),
      6,
      Paint()
        ..color = const Color(0xFFFFF59D)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.restore();

    // --- 2. HỘ VỆ PHẢI: ÁC QUỶ LÔI DỰC (Bay lơ lửng bên phải-dưới, cánh dơi đen, sừng lam, mắt sắc, vung trượng sét) ---
    final rightPos = Offset(w * 0.69, h * 0.70 + bob2);
    canvas.save();
    canvas.translate(rightPos.dx, rightPos.dy);
    canvas.scale(s);

    // Đôi cánh dơi bóng đêm
    final batWingPaint = Paint()..color = const Color(0xFF1E293B);
    final leftBatWing = Path()
      ..moveTo(-24, -6)
      ..lineTo(-56, -26)
      ..lineTo(-48, 8)
      ..lineTo(-26, 10)
      ..close();
    final rightBatWing = Path()
      ..moveTo(24, -6)
      ..lineTo(58, -24)
      ..lineTo(52, 12)
      ..lineTo(26, 10)
      ..close();
    canvas.drawPath(leftBatWing, batWingPaint);
    canvas.drawPath(rightBatWing, batWingPaint);

    // Thân tròn Ác Quỷ Lam Thép
    final demonGrad = const RadialGradient(
      center: Alignment(-0.25, -0.35),
      colors: [Color(0xFF93C5FD), Color(0xFF2563EB), Color(0xFF1E3A8A)],
    ).createShader(Rect.fromCircle(center: Offset.zero, radius: 36));
    canvas.drawCircle(Offset.zero, 32, Paint()..shader = demonGrad);

    // Cặp sừng lam phát sáng
    final hornCyan = Paint()..color = const Color(0xFF00E5FF);
    canvas.drawPath(
      Path()
        ..moveTo(-18, -24)
        ..lineTo(-26, -42)
        ..lineTo(-8, -28)
        ..close(),
      hornCyan,
    );
    canvas.drawPath(
      Path()
        ..moveTo(18, -24)
        ..lineTo(26, -42)
        ..lineTo(8, -28)
        ..close(),
      hornCyan,
    );

    // Cặp mắt chiến thần sắc lẹm + răng nanh
    final angryEye = Paint()..color = const Color(0xFFFF1744);
    canvas.drawPath(
      Path()
        ..moveTo(-18, -6)
        ..lineTo(-6, -2)
        ..lineTo(-16, 3)
        ..close(),
      angryEye,
    );
    canvas.drawPath(
      Path()
        ..moveTo(18, -6)
        ..lineTo(6, -2)
        ..lineTo(16, 3)
        ..close(),
      angryEye,
    );

    // Trượng sấm sét chĩa xuống giao chiến với Tinh Linh
    canvas.drawLine(
      const Offset(-22, 6),
      const Offset(-58, -22),
      Paint()
        ..color = const Color(0xFF38BDF8)
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      const Offset(-60, -24),
      6,
      Paint()
        ..color = const Color(0xFF00E5FF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.restore();
  }

  /// Vẽ thảm cỏ tiền cảnh và cụm nấm/tinh thể ma thuật góc dưới trái (như ảnh mẫu)
  void _drawForegroundTurfAndCrystals(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Cụm nấm / tinh thể ma thuật góc dưới trái
    void drawMagicMushroom(double x, double y, double r, Color capColor) {
      // Thân nấm
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, y + r * 0.55), width: r * 0.7, height: r * 1.1),
          const Radius.circular(6),
        ),
        Paint()..color = const Color(0xFFFDE68A),
      );
      // Mũ nấm
      canvas.drawArc(
        Rect.fromCircle(center: Offset(x, y + r * 0.2), radius: r),
        math.pi,
        math.pi,
        true,
        Paint()..color = capColor,
      );
      // Đốm sáng trên mũ nấm
      final dotPaint = Paint()..color = Colors.white.withValues(alpha: 0.75);
      canvas.drawCircle(Offset(x - r * 0.35, y - r * 0.25), r * 0.16, dotPaint);
      canvas.drawCircle(Offset(x + r * 0.25, y - r * 0.35), r * 0.13, dotPaint);
    }

    drawMagicMushroom(w * 0.08, h * 0.90, 22, const Color(0xFF0284C7));
    drawMagicMushroom(w * 0.12, h * 0.92, 26, const Color(0xFF06B6D4));
    drawMagicMushroom(w * 0.095, h * 0.94, 16, const Color(0xFFE11D48));

    // Dải cỏ tiền cảnh chạy dọc đáy màn hình
    final turfRect = Rect.fromLTWH(0, h * 0.93, w, h * 0.07);
    canvas.drawRect(
      turfRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF4ADE80),
            Color(0xFF16A34A),
            Color(0xFF14532D),
          ],
        ).createShader(turfRect),
    );
  }

  @override
  bool shouldRepaint(covariant _BigWarScenePainter oldDelegate) =>
      oldDelegate.time != time;
}
