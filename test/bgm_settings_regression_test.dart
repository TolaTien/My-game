import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_game/screens/settings_dialog.dart';
import 'package:my_game/services/audio_service.dart';

class ControlledBgm implements BgmPlayback {
  final played = <String>[];
  final playStarted = Completer<void>();
  Completer<void>? playGate;
  bool running = false;
  double volume = 0;
  String? file;
  @override
  Future<void> play(String file, {required double volume}) async {
    if (!playStarted.isCompleted) playStarted.complete();
    final gate = playGate;
    if (gate != null) await gate.future;
    this.file = file;
    this.volume = volume;
    running = true;
    played.add(file);
  }

  @override
  Future<void> pause() async {
    running = false;
  }

  @override
  Future<void> resume() async {
    running = true;
  }

  @override
  Future<void> stop() async {
    running = false;
    file = null;
  }

  @override
  Future<void> setVolume(double volume) async {
    this.volume = volume;
  }
}

void main() {
  late ControlledBgm output;
  late FlameAudioService service;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    output = ControlledBgm();
    service = FlameAudioService(bgmPlayback: output);
  });
  tearDown(() async {
    service.dispose();
    await service.whenBgmSettled;
  });

  test(
    'Turning music off pauses the real output and keeps its volume at zero',
    () async {
      await service.playBgm(BgmTrack.lobby);
      service.isBgmEnabled = false;
      await service.whenBgmSettled;
      expect(output.running, isFalse);
      expect(output.volume, 0);
      expect(service.isPlayingBgm, isFalse);
      await service.playBgm(BgmTrack.dungeon);
      expect(output.played, [BgmTrack.lobby.fileName]);
      service.isBgmEnabled = true;
      await service.whenBgmSettled;
      expect(output.running, isTrue);
      expect(output.file, BgmTrack.dungeon.fileName);
    },
  );
  test(
    'Mute during a slow play cannot be undone by late play completion',
    () async {
      output.playGate = Completer<void>();
      final playing = service.playBgm(BgmTrack.lobby);
      await output.playStarted.future;
      service.isBgmEnabled = false;
      output.playGate!.complete();
      await playing;
      await service.whenBgmSettled;
      expect(output.running, isFalse);
      expect(output.volume, 0);
      expect(service.isBgmEnabled, isFalse);
    },
  );
  test('Switching tracks then muting while loading preserves the last mute request', () async {
    output.playGate = Completer<void>();
    final playing = service.playBgm(BgmTrack.lobby);
    await output.playStarted.future;
    final switching = service.playBgm(BgmTrack.boss);
    service.isBgmEnabled = false;
    output.playGate!.complete();
    await playing;
    await switching;
    await service.whenBgmSettled;
    expect(output.running, isFalse);
    expect(output.volume, 0);
    expect(service.currentBgmTrack, BgmTrack.boss);
    service.isBgmEnabled = true;
    await service.whenBgmSettled;
    expect(output.file, BgmTrack.boss.fileName);
    expect(output.running, isTrue);
  });
  test('Volume slider changes live playback, including zero and explicit track volume', () async {
    await service.playBgm(BgmTrack.lobby, volume: .9);
    service.setBgmVolume(.25);
    await service.whenBgmSettled;
    expect(output.volume, .25);
    service.setBgmVolume(0);
    await service.whenBgmSettled;
    expect(output.volume, 0);
    service.isBgmEnabled = false;
    service.setBgmVolume(.7);
    await service.whenBgmSettled;
    expect(output.volume, 0);
    expect(output.running, isFalse);
    service.isBgmEnabled = true;
    await service.whenBgmSettled;
    expect(output.volume, .7);
  });
  test(
    'A saved mute survives service initialization and later scene requests',
    () async {
      SharedPreferences.setMockInitialValues({
        'audio_bgm_on': false,
        'audio_bgm_vol': .4,
      });
      await service.initialize();
      await service.playBgm(BgmTrack.lobby);
      await service.playBgm(BgmTrack.pvp);
      expect(output.played, isEmpty);
      expect(output.running, isFalse);
      service.isBgmEnabled = true;
      await service.whenBgmSettled;
      expect(output.file, BgmTrack.pvp.fileName);
      expect(output.volume, .4);
    },
  );
  test(
    'Rapid off-on-off ends muted and stop cannot be undone by a pending load',
    () async {
      output.playGate = Completer<void>();
      final playing = service.playBgm(BgmTrack.lobby);
      await output.playStarted.future;
      service.isBgmEnabled = false;
      service.isBgmEnabled = true;
      service.isBgmEnabled = false;
      final stop = service.stopBgm();
      output.playGate!.complete();
      await playing;
      await stop;
      await service.whenBgmSettled;
      expect(output.running, isFalse);
      expect(output.file, isNull);
    },
  );
  testWidgets(
    'Settings music switch controls playback, not only the switch appearance',
    (tester) async {
      service = FlameAudioService(bgmPlayback: output);
      AudioService.setInstance(service);
      final playing = service.playBgm(BgmTrack.lobby);
      await tester.pump();
      await playing;
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SettingsDialog())),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      await service.whenBgmSettled;
      expect(service.isBgmEnabled, isFalse);
      expect(output.running, isFalse);
      expect(output.volume, 0);
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      await service.whenBgmSettled;
      expect(service.isBgmEnabled, isTrue);
      expect(output.running, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      AudioService.setInstance(MockAudioService());
    },
  );
}

