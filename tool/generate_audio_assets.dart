// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// Generates valid minimal WAV (PCM 44.1kHz 16-bit mono) and MP3 (MPEG-1 Layer 3) files
/// for the Gold Rush Mobile game assets.
void main() {
  final audioDir = Directory('assets/audio');
  if (!audioDir.existsSync()) {
    audioDir.createSync(recursive: true);
  }

  // 11 SFX WAVs
  final sfxFiles = [
    'sfx_attack_hammer.wav',
    'sfx_attack_arrow.wav',
    'sfx_skill_hurricane.wav',
    'sfx_skill_smash.wav',
    'sfx_skill_berserk.wav',
    'sfx_pickup_coin.wav',
    'sfx_pickup_gem.wav',
    'sfx_pickup_potion.wav',
    'sfx_wheel_spin.wav',
    'sfx_wheel_jackpot.wav',
    'sfx_ui_click.wav',
  ];

  for (final name in sfxFiles) {
    final filePath = 'assets/audio/$name';
    final bytes = generateWavBytes(durationSeconds: 0.15, frequency: 440.0);
    File(filePath).writeAsBytesSync(bytes);
    print('Generated WAV: $filePath (${bytes.length} bytes)');
  }

  // 4 BGM MP3s
  final bgmFiles = [
    'lobby_bgm.mp3',
    'dungeon_bgm.mp3',
    'boss_bgm.mp3',
    'pvp_bgm.mp3',
  ];

  for (final name in bgmFiles) {
    final filePath = 'assets/audio/$name';
    final bytes = generateMp3Bytes(frameCount: 30);
    File(filePath).writeAsBytesSync(bytes);
    print('Generated MP3: $filePath (${bytes.length} bytes)');
  }

  print('\nAll 15 audio asset files generated successfully in assets/audio/!');
}

/// Generates standard RIFF PCM WAV bytes (44100 Hz, 16-bit, Mono)
Uint8List generateWavBytes({double durationSeconds = 0.15, double frequency = 440.0}) {
  const sampleRate = 44100;
  const numChannels = 1;
  const bitsPerSample = 16;
  const byteRate = sampleRate * numChannels * (bitsPerSample ~/ 8);
  const blockAlign = numChannels * (bitsPerSample ~/ 8);

  final sampleCount = (sampleRate * durationSeconds).round();
  final dataSize = sampleCount * numChannels * (bitsPerSample ~/ 8);
  final fileSize = 36 + dataSize;

  final buffer = ByteData(44 + dataSize);

  // RIFF header
  buffer.setUint8(0, 0x52); // 'R'
  buffer.setUint8(1, 0x49); // 'I'
  buffer.setUint8(2, 0x46); // 'F'
  buffer.setUint8(3, 0x46); // 'F'
  buffer.setUint32(4, fileSize, Endian.little);
  buffer.setUint8(8, 0x57);  // 'W'
  buffer.setUint8(9, 0x41);  // 'A'
  buffer.setUint8(10, 0x56); // 'V'
  buffer.setUint8(11, 0x45); // 'E'

  // fmt subchunk
  buffer.setUint8(12, 0x66); // 'f'
  buffer.setUint8(13, 0x6D); // 'm'
  buffer.setUint8(14, 0x74); // 't'
  buffer.setUint8(15, 0x20); // ' '
  buffer.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
  buffer.setUint16(20, 1, Endian.little);  // AudioFormat (1 = PCM)
  buffer.setUint16(22, numChannels, Endian.little);
  buffer.setUint32(24, sampleRate, Endian.little);
  buffer.setUint32(28, byteRate, Endian.little);
  buffer.setUint16(32, blockAlign, Endian.little);
  buffer.setUint16(34, bitsPerSample, Endian.little);

  // data subchunk
  buffer.setUint8(36, 0x64); // 'd'
  buffer.setUint8(37, 0x61); // 'a'
  buffer.setUint8(38, 0x74); // 't'
  buffer.setUint8(39, 0x61); // 'a'
  buffer.setUint32(40, dataSize, Endian.little);

  // Write PCM audio data (fading tone to prevent click)
  var offset = 44;
  for (var i = 0; i < sampleCount; i++) {
    final t = i / sampleRate;
    final envelope = sin(pi * (i / sampleCount)); // smooth fade in / fade out
    final sampleValue = (sin(2 * pi * frequency * t) * envelope * 2000).round();
    buffer.setInt16(offset, sampleValue, Endian.little);
    offset += 2;
  }

  return buffer.buffer.asUint8List();
}

/// Generates valid MPEG-1 Layer III (MP3) frames (128 kbps, 44100 Hz, mono)
Uint8List generateMp3Bytes({int frameCount = 30}) {
  // Standard MPEG-1 Layer III frame at 128 kbps, 44.1 kHz:
  // Frame size = 144 * 128000 / 44100 = 417 bytes (rounded)
  const frameSize = 417;
  final totalBytes = frameSize * frameCount;
  final result = Uint8List(totalBytes);

  for (var f = 0; f < frameCount; f++) {
    final offset = f * frameSize;
    // Syncword & Header (4 bytes):
    // 0xFF: 11111111 (sync)
    // 0xFB: 111 (sync) + 11 (MPEG-1) + 01 (Layer 3) + 1 (no CRC)
    // 0x90: 1001 (128 kbps) + 00 (44.1kHz) + 0 (no pad) + 0 (priv)
    // 0xC4: 11 (mono) + 00 (mode ext) + 0 (copy) + 1 (orig) + 00 (no emphasis)
    result[offset] = 0xFF;
    result[offset + 1] = 0xFB;
    result[offset + 2] = 0x90;
    result[offset + 3] = 0xC4;

    // Remaining bytes are frame payload / side info (zeroed silence)
  }

  return result;
}
