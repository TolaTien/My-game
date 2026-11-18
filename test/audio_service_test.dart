import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/services/audio_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (MethodCall methodCall) async => 1,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (MethodCall methodCall) async => 1,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getAll') return <String, Object>{};
        return true;
      },
    );
  });

  group('Group 1: AudioService Default State & ValueNotifiers', () {
    late AudioService audioService;

    setUp(() {
      audioService = MockAudioService();
    });

    test('Initial default volumes and enabled flags match specification', () {
      expect(audioService.bgmVolume, closeTo(0.8, 0.001));
      expect(audioService.sfxVolume, closeTo(1.0, 0.001));
      expect(audioService.isBgmEnabled, isTrue);
      expect(audioService.isSfxEnabled, isTrue);
      expect(audioService.currentBgmTrack, isNull);
      expect(audioService.isPlayingBgm, isFalse);
    });

    test('ValueNotifiers reflect initial property values', () {
      expect(audioService.bgmVolumeNotifier.value, closeTo(0.8, 0.001));
      expect(audioService.sfxVolumeNotifier.value, closeTo(1.0, 0.001));
      expect(audioService.isBgmEnabledNotifier.value, isTrue);
      expect(audioService.isSfxEnabledNotifier.value, isTrue);
    });
  });

  group('Group 2: Volume Boundaries & Clamping [0.0, 1.0]', () {
    late AudioService audioService;

    setUp(() {
      audioService = MockAudioService();
    });

    test('Clamps negative BGM and SFX volumes to 0.0', () {
      audioService.setBgmVolume(-0.75);
      expect(audioService.bgmVolume, equals(0.0));
      expect(audioService.bgmVolumeNotifier.value, equals(0.0));

      audioService.setSfxVolume(-10.0);
      expect(audioService.sfxVolume, equals(0.0));
      expect(audioService.sfxVolumeNotifier.value, equals(0.0));
    });

    test('Clamps overflow BGM and SFX volumes to 1.0', () {
      audioService.setBgmVolume(1.85);
      expect(audioService.bgmVolume, equals(1.0));
      expect(audioService.bgmVolumeNotifier.value, equals(1.0));

      audioService.setSfxVolume(99.0);
      expect(audioService.sfxVolume, equals(1.0));
      expect(audioService.sfxVolumeNotifier.value, equals(1.0));
    });

    test('Accepts valid intermediate volume levels', () {
      audioService.setBgmVolume(0.42);
      expect(audioService.bgmVolume, closeTo(0.42, 0.001));

      audioService.setSfxVolume(0.67);
      expect(audioService.sfxVolume, closeTo(0.67, 0.001));
    });
  });

  group('Group 3: Mute & Unmute Lifecycle', () {
    late AudioService audioService;

    setUp(() {
      audioService = MockAudioService();
    });

    test('toggleMute mutes both channels when at least one is active', () {
      expect(audioService.isBgmEnabled, isTrue);
      expect(audioService.isSfxEnabled, isTrue);

      audioService.toggleMute();
      expect(audioService.isBgmEnabled, isFalse);
      expect(audioService.isSfxEnabled, isFalse);
      expect(audioService.isBgmEnabledNotifier.value, isFalse);
      expect(audioService.isSfxEnabledNotifier.value, isFalse);
    });

    test('toggleMute un-mutes both channels when both are muted', () {
      audioService.toggleMute(); // mute
      expect(audioService.isBgmEnabled, isFalse);
      expect(audioService.isSfxEnabled, isFalse);

      audioService.toggleMute(); // un-mute
      expect(audioService.isBgmEnabled, isTrue);
      expect(audioService.isSfxEnabled, isTrue);
    });

    test('Individual toggles operate independently', () {
      audioService.toggleBgm();
      expect(audioService.isBgmEnabled, isFalse);
      expect(audioService.isSfxEnabled, isTrue);

      audioService.toggleSfx();
      expect(audioService.isBgmEnabled, isFalse);
      expect(audioService.isSfxEnabled, isFalse);

      audioService.toggleBgm();
      expect(audioService.isBgmEnabled, isTrue);
      expect(audioService.isSfxEnabled, isFalse);
    });

    test('Muting BGM pauses playback state', () async {
      await audioService.playBgm(BgmTrack.dungeon);
      expect(audioService.isPlayingBgm, isTrue);

      audioService.isBgmEnabled = false;
      expect(audioService.isPlayingBgm, isFalse);
      expect(audioService.currentBgmTrack, equals(BgmTrack.dungeon));

      audioService.isBgmEnabled = true;
      expect(audioService.isPlayingBgm, isTrue);
    });
  });

  group('Group 4: BGM State Transitions & Track Enumeration', () {
    late AudioService audioService;

    setUp(() {
      audioService = MockAudioService();
    });

    test('BgmTrack enum provides exact filenames and descriptions', () {
      expect(BgmTrack.lobby.fileName, equals('nhac-sanh-cho.mp3'));
      expect(BgmTrack.dungeon.fileName, equals('dungeon_bgm.mp3'));
      expect(BgmTrack.boss.fileName, equals('boss_bgm.mp3'));
      expect(BgmTrack.pvp.fileName, equals('pvp_bgm.mp3'));

      expect(BgmTrack.values.length, equals(4));
    });

    test('BgmTrack.fromName resolves by enum name, file name, or base name', () {
      expect(BgmTrack.fromName('lobby'), equals(BgmTrack.lobby));
      expect(BgmTrack.fromName('lobby_bgm.mp3'), equals(BgmTrack.lobby));
      expect(BgmTrack.fromName('dungeon_bgm'), equals(BgmTrack.dungeon));
      expect(BgmTrack.fromName('BOSS'), equals(BgmTrack.boss));
      expect(BgmTrack.fromName('pvp'), equals(BgmTrack.pvp));
      expect(BgmTrack.fromName('non_existent'), isNull);
      expect(BgmTrack.fromName(null), isNull);
    });

    test('playBgm transitions tracks and sets playing state', () async {
      await audioService.playBgm(BgmTrack.lobby);
      expect(audioService.currentBgmTrack, equals(BgmTrack.lobby));
      expect(audioService.isPlayingBgm, isTrue);

      await audioService.playBgm(BgmTrack.boss);
      expect(audioService.currentBgmTrack, equals(BgmTrack.boss));
      expect(audioService.isPlayingBgm, isTrue);
    });

    test('pauseBgm, resumeBgm, and stopBgm transition states accurately', () async {
      await audioService.playBgm(BgmTrack.pvp);

      await audioService.pauseBgm();
      expect(audioService.isPlayingBgm, isFalse);
      expect(audioService.currentBgmTrack, equals(BgmTrack.pvp));

      await audioService.resumeBgm();
      expect(audioService.isPlayingBgm, isTrue);
      expect(audioService.currentBgmTrack, equals(BgmTrack.pvp));

      await audioService.stopBgm();
      expect(audioService.isPlayingBgm, isFalse);
      expect(audioService.currentBgmTrack, isNull);
    });
  });

  group('Group 5: SFX Trigger Matrix & AudioCallEvent Tracking', () {
    late MockAudioService mockAudio;

    setUp(() {
      mockAudio = MockAudioService();
    });

    test('SfxSound enum contains all 11 required sound effects', () {
      expect(SfxSound.values.length, equals(11));

      expect(SfxSound.attackHammer.fileName, equals('sfx_attack_hammer.wav'));
      expect(SfxSound.attackArrow.fileName, equals('sfx_attack_arrow.wav'));
      expect(SfxSound.skillHurricane.fileName, equals('sfx_skill_hurricane.wav'));
      expect(SfxSound.skillSmash.fileName, equals('sfx_skill_smash.wav'));
      expect(SfxSound.skillBerserk.fileName, equals('sfx_skill_berserk.wav'));
      expect(SfxSound.pickupCoin.fileName, equals('sfx_pickup_coin.wav'));
      expect(SfxSound.pickupGem.fileName, equals('sfx_pickup_gem.wav'));
      expect(SfxSound.pickupPotion.fileName, equals('sfx_pickup_potion.wav'));
      expect(SfxSound.wheelSpin.fileName, equals('sfx_wheel_spin.wav'));
      expect(SfxSound.wheelJackpot.fileName, equals('sfx_wheel_jackpot.wav'));
      expect(SfxSound.uiClick.fileName, equals('sfx_ui_click.wav'));
    });

    test('SfxSound.fromName resolves various string formats', () {
      expect(SfxSound.fromName('attackHammer'), equals(SfxSound.attackHammer));
      expect(SfxSound.fromName('sfx_attack_arrow.wav'), equals(SfxSound.attackArrow));
      expect(SfxSound.fromName('skillHurricane'), equals(SfxSound.skillHurricane));
      expect(SfxSound.fromName('sfx_wheel_jackpot'), equals(SfxSound.wheelJackpot));
      expect(SfxSound.fromName('invalid_sfx'), isNull);
      expect(SfxSound.fromName(null), isNull);
    });

    test('All 11 SFX triggers are recorded in MockAudioService callHistory', () async {
      for (final sfx in SfxSound.values) {
        await mockAudio.playSfx(sfx);
      }

      expect(mockAudio.callHistory.length, equals(11));
      for (int i = 0; i < SfxSound.values.length; i++) {
        expect(mockAudio.callHistory[i].method, equals('playSfx'));
        expect(mockAudio.callHistory[i].target, equals(SfxSound.values[i]));
      }
    });

    test('SFX playback is suppressed when isSfxEnabled is false', () async {
      mockAudio.isSfxEnabled = false;
      mockAudio.clearHistory();

      await mockAudio.playSfx(SfxSound.uiClick);
      expect(mockAudio.callHistory, isEmpty);
    });

    test('SFX volume override is recorded correctly', () async {
      await mockAudio.playSfx(SfxSound.pickupCoin, volume: 0.5);
      final event = mockAudio.callHistory.last;
      expect(event.method, equals('playSfx'));
      expect(event.target, equals(SfxSound.pickupCoin));
      expect(event.volume, closeTo(0.5, 0.001));
    });
  });

  group('Group 6: Zero-Crash Error Resilience (Headless FlameAudioService)', () {
    late FlameAudioService flameAudio;

    setUp(() {
      flameAudio = FlameAudioService();
    });

    test('initialize completes without throwing unhandled exceptions in test environment', () async {
      await expectLater(flameAudio.initialize(), completes);
    });

    test('playBgm handles headless test environment defensively', () async {
      await expectLater(flameAudio.playBgm(BgmTrack.lobby), completes);
      expect(flameAudio.currentBgmTrack, equals(BgmTrack.lobby));
      expect(flameAudio.isPlayingBgm, isTrue);
    });

    test('stopBgm, pauseBgm, resumeBgm handle headless environment safely', () async {
      await expectLater(flameAudio.playBgm(BgmTrack.dungeon), completes);
      await expectLater(flameAudio.pauseBgm(), completes);
      expect(flameAudio.isPlayingBgm, isFalse);

      await expectLater(flameAudio.resumeBgm(), completes);
      expect(flameAudio.isPlayingBgm, isTrue);

      await expectLater(flameAudio.stopBgm(), completes);
      expect(flameAudio.isPlayingBgm, isFalse);
      expect(flameAudio.currentBgmTrack, isNull);
    });

    test('playSfx completes without throwing even with MissingPluginException', () async {
      await expectLater(flameAudio.playSfx(SfxSound.attackHammer), completes);
      await expectLater(flameAudio.playSfx(SfxSound.uiClick, volume: 0.8), completes);
    });

    test('Unknown track or sfx strings handle safely without crashing', () async {
      await expectLater(flameAudio.playBgm('mystery_nonexistent_track.mp3'), completes);
      await expectLater(flameAudio.playSfx('nonexistent_sfx.wav'), completes);
    });
  });

  group('Group 7: Reactive UI Integration (ValueNotifier Listeners)', () {
    late AudioService audioService;

    setUp(() {
      audioService = MockAudioService();
    });

    test('bgmVolumeNotifier notifies subscribers on volume adjustments', () {
      double? notifiedVal;
      audioService.bgmVolumeNotifier.addListener(() {
        notifiedVal = audioService.bgmVolumeNotifier.value;
      });

      audioService.setBgmVolume(0.65);
      expect(notifiedVal, closeTo(0.65, 0.001));

      audioService.setBgmVolume(0.20);
      expect(notifiedVal, closeTo(0.20, 0.001));
    });

    test('sfxVolumeNotifier notifies subscribers on volume adjustments', () {
      double? notifiedVal;
      audioService.sfxVolumeNotifier.addListener(() {
        notifiedVal = audioService.sfxVolumeNotifier.value;
      });

      audioService.setSfxVolume(0.55);
      expect(notifiedVal, closeTo(0.55, 0.001));
    });

    test('isBgmEnabledNotifier and isSfxEnabledNotifier notify on mute toggles', () {
      int bgmToggleCount = 0;
      int sfxToggleCount = 0;

      audioService.isBgmEnabledNotifier.addListener(() => bgmToggleCount++);
      audioService.isSfxEnabledNotifier.addListener(() => sfxToggleCount++);

      audioService.toggleMute();
      expect(bgmToggleCount, equals(1));
      expect(sfxToggleCount, equals(1));

      audioService.toggleMute();
      expect(bgmToggleCount, equals(2));
      expect(sfxToggleCount, equals(2));
    });
  });

  group('Group 8: MockAudioService Spy & Project Contract Compatibility', () {
    test('AudioService singleton instance can be replaced and restored', () {
      final original = AudioService.instance;
      final mock = MockAudioService();

      AudioService.setInstance(mock);
      expect(identical(AudioService.instance, mock), isTrue);

      AudioService.setInstance(original);
      expect(identical(AudioService.instance, original), isTrue);
    });

    test('Dynamic string API overloads match PROJECT.md contract', () async {
      final mock = MockAudioService();
      AudioService.setInstance(mock);

      // Play BGM with string
      await AudioService.instance.playBgm('lobby_bgm.mp3', volume: 0.9);
      expect(mock.currentBgmTrack, equals(BgmTrack.lobby));

      // Play SFX with string
      await AudioService.instance.playSfx('sfx_attack_hammer.wav', volume: 0.7);
      final lastSfx = mock.callHistory.last;
      expect(lastSfx.method, equals('playSfx'));
      expect(lastSfx.target, equals('sfx_attack_hammer.wav'));
      expect(lastSfx.volume, closeTo(0.7, 0.001));

      // toggleMute
      AudioService.instance.toggleMute();
      expect(AudioService.instance.isBgmEnabled, isFalse);
      expect(AudioService.instance.isSfxEnabled, isFalse);

      mock.clearHistory();
      expect(mock.callHistory, isEmpty);

      AudioService.setInstance(FlameAudioService());
    });
  });
}
