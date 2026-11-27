import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';
import '../models/player_profile.dart';
import 'database_service.dart';
import 'firebase_bootstrap.dart';
import 'friend_party_service.dart';
import 'player_storage.dart';

/// Lỗi xác thực đã được dịch sang tiếng Việt để hiển thị trực tiếp lên UI.
class AuthFailure implements Exception {
  final String message;
  const AuthFailure(this.message);

  @override
  String toString() => message;
}

/// Dịch vụ Đăng ký / Đăng nhập bằng Email + Mật khẩu (Firebase Authentication).
///
/// Dữ liệu người chơi được lưu trên Firebase Realtime Database:
/// ```
/// players/{uid}/account  -> { email, displayName, createdAt, lastLoginAt }
/// players/{uid}/profile  -> PlayerProfile.toJson() (vàng, tướng, rank, ...)
/// ```
/// Mọi lần [PlayerStorage.saveProfile] sẽ tự động đồng bộ (debounce) lên
/// `players/{uid}/profile` khi người chơi đã đăng nhập.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  Timer? _syncDebounce;
  PlayerProfile? _pendingProfile;

  /// Firebase đã khởi tạo thành công => có thể đăng nhập online.
  bool get isAvailable => FirebaseBootstrap.isReady && Firebase.apps.isNotEmpty;

  FirebaseAuth get _auth => FirebaseAuth.instance;

  User? get currentUser => isAvailable ? _auth.currentUser : null;

  bool get isSignedIn => currentUser != null;

  FirebaseDatabase get _db => FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: DefaultFirebaseOptions.databaseUrl,
      );

  DatabaseReference _playerRef(String uid) => _db.ref('players/$uid');

  DatabaseReference _usernameRef(String nameKey) => _db.ref('usernames/$nameKey');

  static final RegExp _gmailRegex = RegExp(
    r'^[a-zA-Z0-9]+(?:[._+-][a-zA-Z0-9]+)*@gmail\.com$',
    caseSensitive: false,
  );

  static final RegExp _displayNameAllowedRegex = RegExp(
    r'^[\p{L}\p{N}_\- ]+$',
    unicode: true,
  );

  /// Chuẩn hóa khoảng trắng tên hiển thị (gộp nhiều dấu cách liên tiếp thành 1).
  static String cleanDisplayName(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// Chuẩn hóa key lưu trên nhánh `usernames/{nameKey}` (không phân biệt hoa/thường).
  static String normalizeUsernameKey(String displayName) =>
      cleanDisplayName(displayName).toLowerCase();

  /// Kiểm tra định dạng `@gmail.com` hợp lệ.
  static bool isValidGmail(String rawEmail) =>
      _gmailRegex.hasMatch(rawEmail.trim());

  /// Kiểm tra hợp lệ tên nhân vật (3–16 ký tự, không chứa ký tự đặc biệt cấm của Firebase).
  static String? validateDisplayName(String? raw) {
    final cleaned = cleanDisplayName(raw ?? '');
    if (cleaned.isEmpty) return 'Chưa nhập tên nhân vật';
    if (cleaned.length < 3 || cleaned.length > 16) {
      return 'Tên nhân vật cần từ 3 đến 16 ký tự';
    }
    if (!_displayNameAllowedRegex.hasMatch(cleaned)) {
      return 'Tên chỉ được gồm chữ cái, số, khoảng trắng, gạch ngang/dưới';
    }
    return null;
  }

  /// Kiểm tra hợp lệ địa chỉ Gmail.
  static String? validateGmail(String? raw) {
    final s = raw?.trim() ?? '';
    if (s.isEmpty) return 'Chưa nhập email';
    if (!isValidGmail(s)) {
      return 'Vui lòng nhập địa chỉ @gmail.com hợp lệ (VD: tenban@gmail.com)';
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // PUBLIC API
  // ---------------------------------------------------------------------------

  /// Khôi phục phiên đăng nhập cũ (nếu có) khi mở game.
  /// Trả về `true` nếu người chơi đã đăng nhập và hồ sơ đã được nạp.
  Future<bool> restoreSession() async {
    final user = currentUser;
    if (user == null) return false;
    try {
      await _loadUserIntoStorage(user);
      return true;
    } catch (e) {
      debugPrint('AuthService.restoreSession failed: $e');
      // Không đọc được dữ liệu online -> vẫn cho vào game bằng bản cache cục bộ.
      PlayerStorage.attachUser(user.uid, _syncProfileToCloud);
      await PlayerStorage.loadProfile();
      return true;
    }
  }

  /// Đăng ký tài khoản mới (bắt buộc @gmail.com & tên nhân vật duy nhất)
  /// và tạo hồ sơ người chơi trên Realtime Database.
  Future<void> register({
    required String displayName,
    required String email,
    required String password,
  }) async {
    _ensureAvailable();

    final nameError = validateDisplayName(displayName);
    if (nameError != null) {
      throw AuthFailure(nameError);
    }
    final emailError = validateGmail(email);
    if (emailError != null) {
      throw AuthFailure(emailError);
    }
    if (password.length < 6) {
      throw const AuthFailure('Mật khẩu quá yếu (tối thiểu 6 ký tự).');
    }

    final cleanName = cleanDisplayName(displayName);
    final nameKey = normalizeUsernameKey(cleanName);
    final cleanEmail = email.trim().toLowerCase();

    // Bước 1: Kiểm tra nhanh tên đã có người đặt chưa trước khi tạo Auth user
    try {
      final existingSnap = await _usernameRef(nameKey).get();
      if (existingSnap.exists) {
        throw AuthFailure(
          'Tên nhân vật "$cleanName" đã có người sử dụng. Vui lòng chọn tên khác.',
        );
      }
    } on AuthFailure {
      rethrow;
    } catch (e) {
      debugPrint('AuthService precheck username skipped: $e');
    }

    // Bước 2: Tạo tài khoản Firebase Authentication (tự chặn trùng Gmail)
    UserCredential cred;
    try {
      cred = await _auth.createUserWithEmailAndPassword(
        email: cleanEmail,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_mapAuthError(e));
    }

    final user = cred.user!;

    // Bước 3: Kiểm tra cả dữ liệu cũ trong `directory` + khóa nguyên tử (Transaction) nhánh `usernames/{nameKey}`
    try {
      final isTakenInDirectory = await _isNameTakenInLegacyDirectory(
        nameKey: nameKey,
        ownUid: user.uid,
      );
      if (isTakenInDirectory) {
        await _rollbackCreatedAuthUser(user);
        throw AuthFailure(
          'Tên nhân vật "$cleanName" đã có người sử dụng. Vui lòng chọn tên khác.',
        );
      }

      final txResult = await _usernameRef(nameKey).runTransaction((current) {
        if (current != null && current is Map) {
          final existingUid = current['uid']?.toString();
          if (existingUid != null &&
              existingUid.isNotEmpty &&
              existingUid != user.uid) {
            return Transaction.abort();
          }
        }
        return Transaction.success({
          'uid': user.uid,
          'displayName': cleanName,
          'claimedAt': ServerValue.timestamp,
        });
      });

      if (!txResult.committed) {
        await _rollbackCreatedAuthUser(user);
        throw AuthFailure(
          'Tên nhân vật "$cleanName" vừa có người đăng ký. Vui lòng chọn tên khác.',
        );
      }
    } on AuthFailure {
      rethrow;
    } catch (e) {
      debugPrint('AuthService username reservation warning: $e');
    }

    try {
      await user.updateDisplayName(cleanName);
    } catch (_) {}

    final profile = PlayerProfile.defaultProfile(playerName: cleanName);
    try {
      await _playerRef(user.uid).set({
        'account': {
          'uid': user.uid,
          'email': cleanEmail,
          'displayName': cleanName,
          'createdAt': ServerValue.timestamp,
          'lastLoginAt': ServerValue.timestamp,
        },
        'profile': _profileToCloudJson(profile),
      });
    } catch (e) {
      debugPrint('AuthService.register write profile failed: $e');
      throw const AuthFailure(
        'Tạo tài khoản thành công nhưng không lưu được hồ sơ lên máy chủ. '
        'Kiểm tra Database Rules rồi đăng nhập lại.',
      );
    }

    PlayerStorage.attachUser(user.uid, _syncProfileToCloud);
    await PlayerStorage.saveProfile(profile, syncCloud: false);
    await _afterProfileReady(profile);
  }

  /// Đăng nhập bằng Email + Mật khẩu và nạp hồ sơ từ Realtime Database.
  Future<void> login({required String email, required String password}) async {
    _ensureAvailable();
    UserCredential cred;
    try {
      cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_mapAuthError(e));
    }
    await _loadUserIntoStorage(cred.user!);
  }

  /// Gửi email đặt lại mật khẩu.
  Future<void> sendPasswordReset(String email) async {
    _ensureAvailable();
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_mapAuthError(e));
    }
  }

  /// Đăng xuất: đẩy nốt dữ liệu đang chờ lên server, đặt trạng thái Offline rồi thoát phiên.
  Future<void> logout() async {
    await flushPendingSync();
    await FriendPartyService.instance.onUserLoggedOut();
    PlayerStorage.detachUser();
    if (isAvailable) {
      try {
        await _auth.signOut();
      } catch (e) {
        debugPrint('AuthService.logout failed: $e');
      }
    }
  }

  /// Ghi ngay hồ sơ đang chờ debounce lên server.
  Future<void> flushPendingSync() async {
    _syncDebounce?.cancel();
    _syncDebounce = null;
    final pending = _pendingProfile;
    _pendingProfile = null;
    if (pending != null) await _writeProfile(pending);
  }

  // ---------------------------------------------------------------------------
  // INTERNAL
  // ---------------------------------------------------------------------------

  void _ensureAvailable() {
    if (!isAvailable) {
      throw const AuthFailure(
        'Không kết nối được máy chủ Firebase. Kiểm tra mạng rồi thử lại.',
      );
    }
  }

  Future<void> _loadUserIntoStorage(User user) async {
    final ref = _playerRef(user.uid);
    final snap = await ref.child('profile').get();

    PlayerProfile profile;
    if (snap.exists && snap.value is Map) {
      final map = jsonDecode(jsonEncode(snap.value)) as Map<String, dynamic>;
      profile = PlayerProfile.fromJson(map);
    } else {
      // Tài khoản có trên Auth nhưng chưa có hồ sơ (VD: đăng ký lỗi giữa chừng)
      final name = (user.displayName?.trim().isNotEmpty ?? false)
          ? user.displayName!.trim()
          : null;
      profile = PlayerProfile.defaultProfile(playerName: name);
      await ref.child('profile').set(_profileToCloudJson(profile));
    }

    unawaited(ref.child('account').update({
      'uid': user.uid,
      'email': user.email,
      'displayName': profile.playerName,
      'lastLoginAt': ServerValue.timestamp,
    }).catchError((Object e) {
      debugPrint('AuthService update account failed: $e');
    }));

    PlayerStorage.attachUser(user.uid, _syncProfileToCloud);
    await PlayerStorage.saveProfile(profile, syncCloud: false);
    // Chạy lại loadProfile để áp dụng các bước nâng cấp dữ liệu cũ (mã GR, ...)
    final loaded = await PlayerStorage.loadProfile();
    unawaited(_backfillUsernameReservation(user.uid, loaded.playerName));
    await _afterProfileReady(loaded);
  }

  Future<bool> _isNameTakenInLegacyDirectory({
    required String nameKey,
    required String ownUid,
  }) async {
    try {
      final dirSnap = await _db.ref('directory').get();
      if (dirSnap.exists && dirSnap.value is Map) {
        final dirMap = dirSnap.value as Map;
        for (final value in dirMap.values) {
          if (value is Map) {
            final entryName = value['name']?.toString() ?? '';
            if (normalizeUsernameKey(entryName) == nameKey) {
              return true;
            }
          }
        }
      }

      final lbSnap = await _db.ref('leaderboard').get();
      if (lbSnap.exists && lbSnap.value is Map) {
        final lbMap = lbSnap.value as Map;
        for (final entry in lbMap.entries) {
          final key = entry.key.toString();
          if (key.startsWith('seed_') || key == ownUid) continue;
          final val = entry.value;
          if (val is Map) {
            final entryUid = val['uid']?.toString() ?? key;
            if (entryUid == ownUid) continue;
            final entryName = val['name']?.toString() ?? '';
            if (normalizeUsernameKey(entryName) == nameKey) {
              return true;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('AuthService legacy directory check skipped: $e');
    }
    return false;
  }

  Future<void> _rollbackCreatedAuthUser(User user) async {
    try {
      await user.delete();
    } catch (e) {
      debugPrint('AuthService rollback delete user failed: $e');
    }
    try {
      await _auth.signOut();
    } catch (_) {}
  }

  /// Tự động đăng ký giữ chỗ tên cho các tài khoản cũ đã tạo trước khi có bảng `usernames`.
  Future<void> _backfillUsernameReservation(
    String uid,
    String playerName,
  ) async {
    final cleaned = cleanDisplayName(playerName);
    if (cleaned.length < 3 ||
        cleaned.length > 16 ||
        cleaned.startsWith('Chiến Binh #') ||
        !_displayNameAllowedRegex.hasMatch(cleaned)) {
      return;
    }
    final nameKey = normalizeUsernameKey(cleaned);
    try {
      await _usernameRef(nameKey).runTransaction((current) {
        if (current != null) {
          return Transaction.abort();
        }
        return Transaction.success({
          'uid': uid,
          'displayName': cleaned,
          'claimedAt': ServerValue.timestamp,
        });
      });
    } catch (_) {}
  }

  Future<void> _afterProfileReady(PlayerProfile profile) async {
    try {
      await DatabaseService.instance.updateLeaderboard(profile);
    } catch (_) {}
  }

  /// Hook được [PlayerStorage] gọi sau mỗi lần lưu hồ sơ.
  void _syncProfileToCloud(PlayerProfile profile) {
    _pendingProfile = profile;
    _syncDebounce?.cancel();
    _syncDebounce = Timer(const Duration(milliseconds: 800), () {
      final p = _pendingProfile;
      _pendingProfile = null;
      if (p != null) unawaited(_writeProfile(p));
    });
  }

  Future<void> _writeProfile(PlayerProfile profile) async {
    final user = currentUser;
    if (user == null) return;
    try {
      final ref = _playerRef(user.uid);
      await ref.update({
        'profile': _profileToCloudJson(profile),
        'account/displayName': profile.playerName,
        'account/updatedAt': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('AuthService sync profile failed: $e');
    }
  }

  /// Realtime Database không lưu giá trị null => loại bỏ để dữ liệu gọn.
  Map<String, dynamic> _profileToCloudJson(PlayerProfile profile) {
    final json = profile.toJson()..removeWhere((_, v) => v == null);
    return json;
  }

  String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Email không hợp lệ.';
      case 'user-disabled':
        return 'Tài khoản này đã bị khóa.';
      case 'user-not-found':
        return 'Không tìm thấy tài khoản với email này.';
      case 'wrong-password':
      case 'invalid-credential':
      case 'INVALID_LOGIN_CREDENTIALS':
        return 'Email hoặc mật khẩu không đúng.';
      case 'email-already-in-use':
        return 'Email này đã được đăng ký. Hãy đăng nhập.';
      case 'weak-password':
        return 'Mật khẩu quá yếu (tối thiểu 6 ký tự).';
      case 'too-many-requests':
        return 'Bạn thử quá nhiều lần. Vui lòng đợi một lát.';
      case 'network-request-failed':
        return 'Lỗi kết nối mạng. Kiểm tra internet rồi thử lại.';
      case 'operation-not-allowed':
        return 'Đăng nhập Email/Mật khẩu chưa được bật trên Firebase Console.';
      default:
        return e.message ?? 'Đã xảy ra lỗi (${e.code}).';
    }
  }
}
