import 'dart:typed_data';
import 'dart:ui' as ui;

/// Removes detached dark export debris at decode time, preserving source assets.
Future<ui.Image> cleanCompanionTexture(
  ui.Image source, {
  bool fox = false,
}) async {
  final data = await source.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) return source;
  final pixels = Uint8List.fromList(data.buffer.asUint8List());
  final w = source.width, h = source.height;
  final seen = Uint8List(w * h);
  for (var seed = 0; seed < seen.length; seed++) {
    if (seen[seed] != 0 || pixels[seed * 4 + 3] == 0) continue;
    final group = <int>[seed];
    seen[seed] = 1;
    var colored = 0;
    for (var cursor = 0; cursor < group.length; cursor++) {
      final n = group[cursor], p = n * 4;
      if (pixels[p] > 55 || pixels[p + 1] > 55 || pixels[p + 2] > 55) colored++;
      final x = n % w, y = n ~/ w;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx, ny = y + dy;
          if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
          final next = ny * w + nx;
          if (seen[next] == 0 && pixels[next * 4 + 3] != 0) {
            seen[next] = 1;
            group.add(next);
          }
        }
      }
    }
    if (colored == 0) {
      for (final n in group) {
        pixels[n * 4 + 3] = 0;
      }
    }
  }
  // Some export streaks touch a paw or wing, so component filtering alone
  // cannot remove them. Keep dark outline pixels only near colored artwork.
  final original = Uint8List.fromList(pixels);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = (y * w + x) * 4;
      // Luna's export includes a navy reflection below its paws, not anatomy.
      if (fox && y > h * .84 && x > w * .22 && x < w * .66) {
        pixels[p + 3] = 0;
        continue;
      }
      if (original[p + 3] == 0 ||
          original[p] > 65 ||
          original[p + 1] > 65 ||
          original[p + 2] > 65) {
        continue;
      }
      var nearColor = false;
      for (var dy = -3; dy <= 3 && !nearColor; dy++) {
        for (var dx = -3; dx <= 3; dx++) {
          final nx = x + dx, ny = y + dy;
          if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
          final n = (ny * w + nx) * 4;
          if (original[n + 3] > 30 &&
              (original[n] > 90 ||
                  original[n + 1] > 90 ||
                  original[n + 2] > 90)) {
            nearColor = true;
            break;
          }
        }
      }
      if (!nearColor) pixels[p + 3] = 0;
    }
  }
  // Raw RGBA is premultiplied. A transparent pixel must also have zero RGB;
  // leaving its old color produces dark/light streaks when the mesh samples it.
  for (var p = 0; p < pixels.length; p += 4) {
    if (pixels[p + 3] == 0) {
      pixels[p] = pixels[p + 1] = pixels[p + 2] = 0;
    }
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
  final descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: w,
    height: h,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  final codec = await descriptor.instantiateCodec();
  final frame = await codec.getNextFrame();
  codec.dispose();
  descriptor.dispose();
  buffer.dispose();
  return frame.image;
}
