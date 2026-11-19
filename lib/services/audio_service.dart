import 'dart:async';
import 'dart:io' show Platform;

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Enumeration of BGM tracks used throughout the game.
enum BgmTrack {
  lobby('nhac-sanh-cho.mp3', 'Heroic Lobby Theme'),
  dungeon('dungeon_bgm.mp3', 'Dungeon Crawler Theme'),
  boss('boss_bgm.mp3', 'Boss Orchestral Theme'),
  pvp('pvp_bgm.mp3', 'PvP Adrenaline Combat Theme');

  final String fileName;
  final String description;
  const BgmTrack(this.fileName, this.description);

  /// Resolves a [BgmTrack] from enum name, file name, or base name without extension.
  static BgmTrack? fromName(dynamic input) {
    if (input == null) return null;
    if (input is BgmTrack) return input;
    final str = input.toString().trim().toLowerCase();
    if (str == 'lobby' ||
        str == 'lobby_bgm' ||
        str == 'lobby_bgm.mp3' ||
        str == 'nhac-sanh-cho' ||
        str == 'nhac-sanh-cho.mp3') {
      return BgmTrack.lobby;
    }
    for (final track in values) {
      if (track.name.toLowerCase() == str ||
          track.fileName.toLowerCase() == str ||
          track.fileName.replaceAll('.mp3', '').toLowerCase() == str) {
        return track;
      }
    }
    return null;
  }
}

/// Enumeration of Sound Effects (SFX) used in combat, metagame, and UI.
enum SfxSound {
  attackHammer('sfx_attack_hammer.wav', 'Heavy hammer whoosh'),
  attackArrow('sfx_attack_arrow.wav', 'Bow twang and arrow flight'),
  skillHurricane('sfx_skill_hurricane.wav', 'Whirlwind 360 cleave'),
  skillSmash('sfx_skill_smash.wav', 'Earth-shattering ground thud'),
  skillBerserk('sfx_skill_berserk.wav', 'Fury roar & fiery ignition'),
  pickupCoin('sfx_pickup_coin.wav', 'Gold coin metallic clink'),
  pickupGem('sfx_pickup_gem.wav', 'Magical chime sparkle'),
  pickupPotion('sfx_pickup_potion.wav', 'Liquid gulp / heal shimmer'),
  wheelSpin('sfx_wheel_spin.wav', 'Mechanical ticker click'),
  wheelJackpot('sfx_wheel_jackpot.wav', 'Trumpet victory fanfare'),
  uiClick('sfx_ui_click.wav', 'Snappy button click feedback');

  final String fileName;
  final String description;
  const SfxSound(this.fileName, this.description);

  /// Resolves an [SfxSound] from enum name, file name, or base name without extension.
  static SfxSound? fromName(dynamic input) {
    if (input == null) return null;
    if (input is SfxSound) return input;
    final str = input.toString().trim();
    for (final sound in values) {
      if (sound.name.toLowerCase() == str.toLowerCase() ||
          sound.fileName.toLowerCase() == str.toLowerCase() ||
          sound.fileName.replaceAll('.wav', '').toLowerCase() ==
              str.toLowerCase()) {
        return sound;
      }
    }
    return null;
  }
}

/// Record of an audio call for verification in [MockAudioService].
class AudioCallEvent {
  final String method;
  final dynamic target;
  final double? volume;
  final bool? loop;
  final DateTime timestamp;

  AudioCallEvent({required this.method, this.target, this.volume, this.loop})
    : timestamp = DateTime.now();

  @override
  String toString() =>
      'AudioCallEvent(method: $method, target: $target, volume: $volume, loop: $loop)';
}

/// Abstract contract for the Gold Rush Audio Subsystem.
abstract class AudioService {
  static AudioService? _instance;

  /// Singleton accessor. Defaults to [FlameAudioService].
  static AudioService get instance {
    _instance ??= FlameAudioService();
    return _instance!;
  }

  /// Sets or overrides the singleton instance (e.g. for testing).
  static void setInstance(AudioService service) {
    _instance = service;
  }

  // Reactive State Notifiers for UI bindings
  ValueNotifier<double> get bgmVolumeNotifier;
  ValueNotifier<double> get sfxVolumeNotifier;
  ValueNotifier<bool> get isBgmEnabledNotifier;
  ValueNotifier<bool> get isSfxEnabledNotifier;

  // Convenience Getters / Setters (clamped [0.0, 1.0])
  double get bgmVolume;
  set bgmVolume(double val);
  double get sfxVolume;
  set sfxVolume(double val);

  bool get isBgmEnabled;
  set isBgmEnabled(bool val);
  bool get isSfxEnabled;
  set isSfxEnabled(bool val);

  BgmTrack? get currentBgmTrack;
  bool get isPlayingBgm;

  // Lifecycle & Playback APIs
  Future<void> initialize();
  Future<void> playBgm(dynamic track, {double? volume, bool loop = true});
  Future<void> stopBgm();
  Future<void> pauseBgm();
  Future<void> resumeBgm();
  Future<void> playSfx(dynamic sound, {double? volume});
  void setBgmVolume(double volume);
  void setSfxVolume(double volume);
  void toggleBgm();
  void toggleSfx();
  void toggleMute();
  void dispose();
}

/// Small output boundary so the real asynchronous playback ordering can be tested.
abstract class BgmPlayback {
  Future<void> play(String file, {required double volume});
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> setVolume(double volume);
}

class _FlameBgmPlayback implements BgmPlayback {
  @override
  Future<void> play(String file, {required double volume}) =>
      FlameAudio.bgm.play(file, volume: volume);
  @override
  Future<void> pause() => FlameAudio.bgm.pause();
  @override
  Future<void> resume() => FlameAudio.bgm.resume();
  @override
  Future<void> stop() => FlameAudio.bgm.stop();
  @override
  Future<void> setVolume(double volume) =>
      FlameAudio.bgm.audioPlayer.setVolume(volume);
}

/// Production implementation backed by FlameAudio with full zero-crash error suppression.
class FlameAudioService implements AudioService {
  FlameAudioService({BgmPlayback? bgmPlayback})
    : _bgmPlayback = bgmPlayback ?? _FlameBgmPlayback(),
      _hasCustomBgmPlayback = bgmPlayback != null,
      _platformAvailable = !isHeadlessTest;
  final BgmPlayback _bgmPlayback;
  final bool _hasCustomBgmPlayback;
  Future<void> get whenBgmSettled => _bgmCommands;
  Future<void> _bgmCommands = Future<void>.value();
  int _bgmRevision = 0;
  bool _wantBgmPlayback = false;
  bool _outputPlaying = false;
  String? _loadedBgmFile;
  double? _trackVolume;
  static const String _keyBgmVolume = 'audio_bgm_vol';
  static const String _keySfxVolume = 'audio_sfx_vol';
  static const String _keyBgmEnabled = 'audio_bgm_on';
  static const String _keySfxEnabled = 'audio_sfx_on';

  final ValueNotifier<double> _bgmVolumeNotifier = ValueNotifier<double>(0.8);
  final ValueNotifier<double> _sfxVolumeNotifier = ValueNotifier<double>(1.0);
  final ValueNotifier<bool> _isBgmEnabledNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<bool> _isSfxEnabledNotifier = ValueNotifier<bool>(true);

  BgmTrack? _currentBgmTrack;
  String? _rawBgmFileName;
  bool _isPlayingBgm = false;
  bool _initialized = false;
  bool _platformAvailable;

  /// Returns true when running in a headless Flutter test environment.
  static bool get isHeadlessTest {
    if (kIsWeb) return false;
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  void setPlatformAvailableForTesting(bool available) {
    _platformAvailable = available;
  }

  @override
  ValueNotifier<double> get bgmVolumeNotifier => _bgmVolumeNotifier;

  @override
  ValueNotifier<double> get sfxVolumeNotifier => _sfxVolumeNotifier;

  @override
  ValueNotifier<bool> get isBgmEnabledNotifier => _isBgmEnabledNotifier;

  @override
  ValueNotifier<bool> get isSfxEnabledNotifier => _isSfxEnabledNotifier;

  @override
  double get bgmVolume => _bgmVolumeNotifier.value;

  @override
  set bgmVolume(double val) => setBgmVolume(val);

  @override
  double get sfxVolume => _sfxVolumeNotifier.value;

  @override
  set sfxVolume(double val) => setSfxVolume(val);

  @override
  bool get isBgmEnabled => _isBgmEnabledNotifier.value;

  @override
  set isBgmEnabled(bool val) {
    if (_isBgmEnabledNotifier.value != val) {
      _isBgmEnabledNotifier.value = val;
      _persistPreference(_keyBgmEnabled, val);
      if (!val) {
        pauseBgm();
      } else if (_currentBgmTrack != null || _rawBgmFileName != null) {
        resumeBgm();
      }
    }
  }

  @override
  bool get isSfxEnabled => _isSfxEnabledNotifier.value;

  @override
  set isSfxEnabled(bool val) {
    if (_isSfxEnabledNotifier.value != val) {
      _isSfxEnabledNotifier.value = val;
      _persistPreference(_keySfxEnabled, val);
    }
  }

  @override
  BgmTrack? get currentBgmTrack => _currentBgmTrack;

  @override
  bool get isPlayingBgm => _isPlayingBgm;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      FlameAudio.audioCache.prefix = 'assets/audio/';
    } catch (e) {
      debugPrint('AudioService: [suppressed cache prefix config] $e');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedBgmVol = prefs.getDouble(_keyBgmVolume);
      if (savedBgmVol != null) {
        _bgmVolumeNotifier.value = savedBgmVol.clamp(0.0, 1.0);
      }
      final savedSfxVol = prefs.getDouble(_keySfxVolume);
      if (savedSfxVol != null) {
        _sfxVolumeNotifier.value = savedSfxVol.clamp(0.0, 1.0);
      }
      final savedBgmOn = prefs.getBool(_keyBgmEnabled);
      if (savedBgmOn != null) {
        _isBgmEnabledNotifier.value = savedBgmOn;
      }
      final savedSfxOn = prefs.getBool(_keySfxEnabled);
      if (savedSfxOn != null) {
        _isSfxEnabledNotifier.value = savedSfxOn;
      }
    } catch (e) {
      debugPrint('AudioService: [suppressed SharedPreferences init] $e');
    }
    await _queueBgmSync();
  }

  // Every request updates desired state immediately. Only one output command
  // runs at a time; after an awaited play/resume, the latest settings win.
  Future<void> _queueBgmSync() {
    final request = ++_bgmRevision;
    final next = _bgmCommands.then((_) async {
      if ((!_platformAvailable && !_hasCustomBgmPlayback) ||
          request != _bgmRevision)
        return;
      try {
        int appliedRevision;
        do {
          appliedRevision = _bgmRevision;
          final file = _rawBgmFileName;
          if (file == null) {
            if (_loadedBgmFile != null || _outputPlaying)
              await _bgmPlayback.stop();
            _loadedBgmFile = null;
            _outputPlaying = false;
          } else if (!isBgmEnabled || !_wantBgmPlayback) {
            await _bgmPlayback.setVolume(0);
            await _bgmPlayback.pause();
            _outputPlaying = false;
          } else {
            if (_loadedBgmFile != file) {
              await _bgmPlayback.play(
                file,
                volume: (_trackVolume ?? bgmVolume).clamp(0.0, 1.0),
              );
              _loadedBgmFile = file;
              _outputPlaying = true;
            } else if (!_outputPlaying) {
              await _bgmPlayback.resume();
              _outputPlaying = true;
            }
            // A mute or slider change can arrive while play() is awaiting I/O.
            await _bgmPlayback.setVolume(
              isBgmEnabled && _wantBgmPlayback
                  ? (_trackVolume ?? bgmVolume).clamp(0.0, 1.0)
                  : 0,
            );
          }
        } while (appliedRevision != _bgmRevision);
      } catch (error) {
        _isPlayingBgm = false;
        _outputPlaying = false;
        _loadedBgmFile = null;
        _handlePlatformException(error, 'BGM output synchronization');
      }
    });
    _bgmCommands = next;
    return next;
  }

  @override
  Future<void> playBgm(
    dynamic track, {
    double? volume,
    bool loop = true,
  }) async {
    final resolvedTrack = BgmTrack.fromName(track);
    final fileName =
        resolvedTrack?.fileName ?? (track is String ? track : null);
    if (fileName == null || fileName.isEmpty) return;
    _currentBgmTrack = resolvedTrack;
    _rawBgmFileName = fileName;
    _trackVolume = volume?.clamp(0.0, 1.0);
    _wantBgmPlayback = true;
    _isPlayingBgm = isBgmEnabled;
    await _queueBgmSync();
  }

  @override
  Future<void> stopBgm() async {
    _isPlayingBgm = false;
    _wantBgmPlayback = false;
    _currentBgmTrack = null;
    _rawBgmFileName = null;
    _trackVolume = null;
    await _queueBgmSync();
  }

  @override
  Future<void> pauseBgm() async {
    _isPlayingBgm = false;
    _wantBgmPlayback = false;
    await _queueBgmSync();
  }

  @override
  Future<void> resumeBgm() async {
    if (!isBgmEnabled || _rawBgmFileName == null) return;
    _wantBgmPlayback = true;
    _isPlayingBgm = true;
    await _queueBgmSync();
  }

  @override
  Future<void> playSfx(dynamic sound, {double? volume}) async {
    if (!isSfxEnabled) return;

    String? fileName;
    if (sound is SfxSound) {
      fileName = sound.fileName;
    } else if (sound is String) {
      final resolved = SfxSound.fromName(sound);
      fileName = resolved?.fileName ?? sound;
    }

    if (fileName == null || fileName.isEmpty) return;

    final effectiveVolume = (volume ?? sfxVolume).clamp(0.0, 1.0);
    if (effectiveVolume <= 0.0) return;

    if (!_platformAvailable) return;

    final completer = Completer<void>();
    runZonedGuarded(
      () async {
        try {
          await FlameAudio.play(fileName!, volume: effectiveVolume);
        } catch (e) {
          _handlePlatformException(e, 'FlameAudio.play sfx');
        } finally {
          if (!completer.isCompleted) completer.complete();
        }
      },
      (e, st) {
        _handlePlatformException(e, 'unhandled zone sfx');
        if (!completer.isCompleted) completer.complete();
      },
    );

    return completer.future;
  }

  void _handlePlatformException(dynamic error, String context) {
    final errStr = error.toString();
    if (errStr.contains('MissingPluginException') ||
        errStr.contains('Binding has not yet been initialized') ||
        error is TimeoutException) {
      _platformAvailable = false;
    }
    debugPrint('AudioService: [suppressed $context] $error');
  }

  @override
  void setBgmVolume(double volume) {
    final clamped = volume.clamp(0.0, 1.0);
    _trackVolume = null;
    if (_bgmVolumeNotifier.value != clamped) {
      _bgmVolumeNotifier.value = clamped;
      _persistPreference(_keyBgmVolume, clamped);
    }
    unawaited(_queueBgmSync());
  }

  @override
  void setSfxVolume(double volume) {
    final clamped = volume.clamp(0.0, 1.0);
    if (_sfxVolumeNotifier.value != clamped) {
      _sfxVolumeNotifier.value = clamped;
      _persistPreference(_keySfxVolume, clamped);
    }
  }

  @override
  void toggleBgm() {
    isBgmEnabled = !isBgmEnabled;
  }

  @override
  void toggleSfx() {
    isSfxEnabled = !isSfxEnabled;
  }

  @override
  void toggleMute() {
    if (isBgmEnabled || isSfxEnabled) {
      // Mute both
      isBgmEnabled = false;
      isSfxEnabled = false;
    } else {
      // Restore both
      isBgmEnabled = true;
      isSfxEnabled = true;
    }
  }

  void _persistPreference(String key, dynamic value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value is double) {
        await prefs.setDouble(key, value);
      } else if (value is bool) {
        await prefs.setBool(key, value);
      }
    } catch (e) {
      debugPrint('AudioService: [suppressed SharedPreferences persist] $e');
    }
  }

  @override
  void dispose() {
    unawaited(stopBgm());
    _bgmVolumeNotifier.dispose();
    _sfxVolumeNotifier.dispose();
    _isBgmEnabledNotifier.dispose();
    _isSfxEnabledNotifier.dispose();
  }
}

/// Test Mock / Spy implementation for headless automated tests.
class MockAudioService implements AudioService {
  final ValueNotifier<double> _bgmVolumeNotifier = ValueNotifier<double>(0.8);
  final ValueNotifier<double> _sfxVolumeNotifier = ValueNotifier<double>(1.0);
  final ValueNotifier<bool> _isBgmEnabledNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<bool> _isSfxEnabledNotifier = ValueNotifier<bool>(true);

  BgmTrack? _currentBgmTrack;
  bool _isPlayingBgm = false;
  final List<AudioCallEvent> callHistory = [];

  @override
  ValueNotifier<double> get bgmVolumeNotifier => _bgmVolumeNotifier;

  @override
  ValueNotifier<double> get sfxVolumeNotifier => _sfxVolumeNotifier;

  @override
  ValueNotifier<bool> get isBgmEnabledNotifier => _isBgmEnabledNotifier;

  @override
  ValueNotifier<bool> get isSfxEnabledNotifier => _isSfxEnabledNotifier;

  @override
  double get bgmVolume => _bgmVolumeNotifier.value;

  @override
  set bgmVolume(double val) => setBgmVolume(val);

  @override
  double get sfxVolume => _sfxVolumeNotifier.value;

  @override
  set sfxVolume(double val) => setSfxVolume(val);

  @override
  bool get isBgmEnabled => _isBgmEnabledNotifier.value;

  @override
  set isBgmEnabled(bool val) {
    if (_isBgmEnabledNotifier.value != val) {
      _isBgmEnabledNotifier.value = val;
      callHistory.add(AudioCallEvent(method: 'setIsBgmEnabled', target: val));
      if (!val) {
        _isPlayingBgm = false;
      } else if (_currentBgmTrack != null) {
        _isPlayingBgm = true;
      }
    }
  }

  @override
  bool get isSfxEnabled => _isSfxEnabledNotifier.value;

  @override
  set isSfxEnabled(bool val) {
    if (_isSfxEnabledNotifier.value != val) {
      _isSfxEnabledNotifier.value = val;
      callHistory.add(AudioCallEvent(method: 'setIsSfxEnabled', target: val));
    }
  }

  @override
  BgmTrack? get currentBgmTrack => _currentBgmTrack;

  @override
  bool get isPlayingBgm => _isPlayingBgm;

  @override
  Future<void> initialize() async {
    callHistory.add(AudioCallEvent(method: 'initialize'));
  }

  @override
  Future<void> playBgm(
    dynamic track, {
    double? volume,
    bool loop = true,
  }) async {
    final resolved = track is BgmTrack ? track : BgmTrack.fromName(track);
    _currentBgmTrack = resolved;
    _isPlayingBgm = isBgmEnabled;

    callHistory.add(
      AudioCallEvent(
        method: 'playBgm',
        target: track,
        volume: volume ?? bgmVolume,
        loop: loop,
      ),
    );
  }

  @override
  Future<void> stopBgm() async {
    _isPlayingBgm = false;
    _currentBgmTrack = null;
    callHistory.add(AudioCallEvent(method: 'stopBgm'));
  }

  @override
  Future<void> pauseBgm() async {
    _isPlayingBgm = false;
    callHistory.add(AudioCallEvent(method: 'pauseBgm'));
  }

  @override
  Future<void> resumeBgm() async {
    if (isBgmEnabled && _currentBgmTrack != null) {
      _isPlayingBgm = true;
    }
    callHistory.add(AudioCallEvent(method: 'resumeBgm'));
  }

  @override
  Future<void> playSfx(dynamic sound, {double? volume}) async {
    if (!isSfxEnabled) return;
    callHistory.add(
      AudioCallEvent(
        method: 'playSfx',
        target: sound,
        volume: volume ?? sfxVolume,
      ),
    );
  }

  @override
  void setBgmVolume(double volume) {
    final clamped = volume.clamp(0.0, 1.0);
    _bgmVolumeNotifier.value = clamped;
    callHistory.add(AudioCallEvent(method: 'setBgmVolume', volume: clamped));
  }

  @override
  void setSfxVolume(double volume) {
    final clamped = volume.clamp(0.0, 1.0);
    _sfxVolumeNotifier.value = clamped;
    callHistory.add(AudioCallEvent(method: 'setSfxVolume', volume: clamped));
  }

  @override
  void toggleBgm() {
    isBgmEnabled = !isBgmEnabled;
    callHistory.add(AudioCallEvent(method: 'toggleBgm', target: isBgmEnabled));
  }

  @override
  void toggleSfx() {
    isSfxEnabled = !isSfxEnabled;
    callHistory.add(AudioCallEvent(method: 'toggleSfx', target: isSfxEnabled));
  }

  @override
  void toggleMute() {
    if (isBgmEnabled || isSfxEnabled) {
      isBgmEnabled = false;
      isSfxEnabled = false;
      callHistory.add(AudioCallEvent(method: 'toggleMute', target: false));
    } else {
      isBgmEnabled = true;
      isSfxEnabled = true;
      callHistory.add(AudioCallEvent(method: 'toggleMute', target: true));
    }
  }

  void clearHistory() {
    callHistory.clear();
  }

  @override
  void dispose() {
    _bgmVolumeNotifier.dispose();
    _sfxVolumeNotifier.dispose();
    _isBgmEnabledNotifier.dispose();
    _isSfxEnabledNotifier.dispose();
  }
}
