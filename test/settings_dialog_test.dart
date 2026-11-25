import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/screens/settings_dialog.dart';
import 'package:my_game/services/audio_service.dart';

void main() {
  late MockAudioService mockAudio;

  setUp(() {
    mockAudio = MockAudioService();
    AudioService.setInstance(mockAudio);
  });

  Widget buildApp() {
    return const MaterialApp(
      home: Scaffold(
        body: Center(child: SettingsDialog()),
      ),
    );
  }

  testWidgets('SettingsDialog only shows audio controls (no graphics/FPS or combat tabs)', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(960, 540));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildApp());

    // Audio controls are present
    expect(find.text('CÀI ĐẶT ÂM THANH'), findsOneWidget);
    expect(find.text('Nhạc nền (BGM)'), findsOneWidget);
    expect(find.text('Hiệu ứng âm thanh (SFX)'), findsOneWidget);
    expect(find.text('TẮT TIẾNG TOÀN BỘ (MUTE ALL)'), findsOneWidget);

    // Removed non-functional sections are absent
    expect(find.text('ĐỒ HỌA & FPS'), findsNothing);
    expect(find.text('CHIẾN ĐẤU'), findsNothing);
    expect(find.text('Tốc độ khung hình (Frame Rate)'), findsNothing);
    expect(find.text('Hiển thị chỉ số sát thương'), findsNothing);
  });

  testWidgets('Audio switches, mute all, and reset default buttons update AudioService', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(960, 540));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildApp());

    // Mute all
    await tester.tap(find.text('TẮT TIẾNG TOÀN BỘ (MUTE ALL)'));
    await tester.pump();
    expect(mockAudio.isBgmEnabled, isFalse);
    expect(mockAudio.isSfxEnabled, isFalse);
    expect(find.text('BẬT LẠI TOÀN BỘ ÂM THANH'), findsOneWidget);

    // Change volumes while muted then click Mặc định
    mockAudio.setBgmVolume(0.2);
    mockAudio.setSfxVolume(0.3);
    await tester.tap(find.text('Mặc định'));
    await tester.pump();

    expect(mockAudio.isBgmEnabled, isTrue);
    expect(mockAudio.isSfxEnabled, isTrue);
    expect(mockAudio.bgmVolume, 0.8);
    expect(mockAudio.sfxVolume, 1.0);
  });
}
