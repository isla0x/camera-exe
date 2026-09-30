import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'capture_mode.dart';

/// 결과 사진 한 장. 이미지 모드는 [png], ASCII 모드는 [asciiLines] 가 채워진다.
class ProcessedShot {
  const ProcessedShot({required this.mode, this.png, this.width = 0, this.height = 0, this.asciiLines});

  final CaptureMode mode;
  final Uint8List? png;
  final int width;
  final int height;
  final List<String>? asciiLines;

  /// 출력 애니메이션이 몇 줄로 나눠서 보여줄지.
  int get printRows => asciiLines?.length ?? 24;
}

/// 기준 해상도. 옛 웹캠처럼 320 x 240 (4:3 가로).
const baseWidth = 320;
const baseHeight = 240;

/// 결과 이미지 해상도 (기준의 3배). 저장·공유할 때 흐릿해지지 않게 키운다.
const outWidth = 960;
const outHeight = 720;

/// 글자 그림 크기. 글자 칸이 세로로 길어서(가로:세로 ≈ 0.6) 줄 수를 줄인다.
const asciiCols = 48;
const asciiRows = 22;

/// 어두운 곳 → 밝은 곳.
const asciiRamp = ' .:-=+*#%@';

/// 카메라가 준 JPEG 을 처리한다. 무거우니 `Isolate.run` 으로 돌린다.
///
/// 픽셀만 다시 그려서 PNG 로 만들기 때문에 위치정보 같은 EXIF 는 결과에 남지 않는다.
ProcessedShot processShot(Uint8List jpeg, CaptureMode mode, {bool mirror = false}) {
  final base = prepareBase(jpeg, mirror: mirror);
  switch (mode) {
    case CaptureMode.webcam:
      final out = webcamFilter(base);
      return ProcessedShot(mode: mode, png: img.encodePng(out), width: out.width, height: out.height);
    case CaptureMode.crt:
      final out = crtFilter(base);
      return ProcessedShot(mode: mode, png: img.encodePng(out), width: out.width, height: out.height);
    case CaptureMode.ascii:
      return ProcessedShot(mode: mode, asciiLines: asciiArt(base));
  }
}

/// 방향을 바로잡고, 가운데를 4:3 가로로 잘라 320 x 240 으로 줄인다.
/// (촬영 화면의 뷰파인더도 가운데 4:3 을 보여준다.)
img.Image prepareBase(Uint8List jpeg, {bool mirror = false}) {
  final decoded = img.decodeImage(jpeg);
  if (decoded == null) {
    throw const FormatException('사진을 읽지 못했어요.');
  }
  var src = img.bakeOrientation(decoded);
  if (mirror) src = img.flipHorizontal(src);
  return centerCropResize(src, baseWidth, baseHeight);
}

img.Image centerCropResize(img.Image src, int w, int h) {
  final target = w / h;
  var cw = src.width;
  var ch = (src.width / target).round();
  if (ch > src.height) {
    ch = src.height;
    cw = (src.height * target).round();
  }
  final cropped = img.copyCrop(
    src,
    x: (src.width - cw) ~/ 2,
    y: (src.height - ch) ~/ 2,
    width: cw,
    height: ch,
  );
  return img.copyResize(cropped, width: w, height: h, interpolation: img.Interpolation.average);
}

int _clamp(num v) => v < 0 ? 0 : (v > 255 ? 255 : v.round());

/// 같은 사진이면 같은 노이즈가 나오게 하는 간단한 난수.
int _hash(int x, int y) {
  var h = x * 374761393 + y * 668265263;
  h = (h ^ (h >> 13)) * 1274126177;
  return (h ^ (h >> 16)) & 0xFF;
}

/// WEBCAM: 큼직한 픽셀, 바랜 색, 따뜻한 색조, 자글자글한 노이즈.
img.Image webcamFilter(img.Image base) {
  const lowW = 160;
  const lowH = 120;
  final low = img.copyResize(base, width: lowW, height: lowH, interpolation: img.Interpolation.average);

  final colors = Uint8List(lowW * lowH * 3);
  for (var y = 0; y < lowH; y++) {
    for (var x = 0; x < lowW; x++) {
      final p = low.getPixel(x, y);
      var r = p.r.toDouble();
      var g = p.g.toDouble();
      var b = p.b.toDouble();
      final luma = 0.299 * r + 0.587 * g + 0.114 * b;
      // 채도 65%
      r = luma + (r - luma) * 0.65;
      g = luma + (g - luma) * 0.65;
      b = luma + (b - luma) * 0.65;
      // 대비를 살짝 낮추고 검정을 띄운다
      r = (r - 128) * 0.88 + 128 + 10;
      g = (g - 128) * 0.88 + 128 + 10;
      b = (b - 128) * 0.88 + 128 + 10;
      // 따뜻한 색조
      r += 10;
      g += 3;
      b -= 8;
      // 노이즈 ±10
      final n = (_hash(x, y) / 255.0 - 0.5) * 20;
      final i = (y * lowW + x) * 3;
      colors[i] = _clamp(r + n);
      colors[i + 1] = _clamp(g + n);
      colors[i + 2] = _clamp(b + n);
    }
  }

  final out = img.Image(width: outWidth, height: outHeight);
  const block = outWidth ~/ lowW; // 6
  for (var y = 0; y < outHeight; y++) {
    final ly = math.min(y ~/ block, lowH - 1);
    for (var x = 0; x < outWidth; x++) {
      final lx = math.min(x ~/ block, lowW - 1);
      final i = (ly * lowW + lx) * 3;
      out.setPixelRgb(x, y, colors[i], colors[i + 1], colors[i + 2]);
    }
  }
  return out;
}

/// CRT: 진한 색, 가로 스캔라인, RGB 번짐, 가장자리 어둠, 둥근 화면 모서리.
img.Image crtFilter(img.Image base) {
  final w = base.width;
  final h = base.height;

  // 1) 색을 진하게 + 옆 픽셀로 살짝 번지게
  final src = Float32List(w * h * 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = base.getPixel(x, y);
      var r = p.r.toDouble();
      var g = p.g.toDouble();
      var b = p.b.toDouble();
      final luma = 0.299 * r + 0.587 * g + 0.114 * b;
      r = luma + (r - luma) * 1.35;
      g = luma + (g - luma) * 1.35;
      b = luma + (b - luma) * 1.35;
      r = (r - 128) * 1.12 + 128;
      g = (g - 128) * 1.12 + 128;
      b = (b - 128) * 1.12 + 128;
      final i = (y * w + x) * 3;
      src[i] = r;
      src[i + 1] = g;
      src[i + 2] = b;
    }
  }
  final bled = Float32List(w * h * 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 3;
      final l = (y * w + math.max(x - 1, 0)) * 3;
      for (var c = 0; c < 3; c++) {
        bled[i + c] = src[i + c] * 0.75 + src[l + c] * 0.25;
      }
    }
  }

  // 2) 3배로 키우면서 스캔라인·RGB 격자·비네팅·둥근 모서리
  final out = img.Image(width: outWidth, height: outHeight);
  const scale = outWidth ~/ baseWidth; // 3
  const radius = 54.0;
  final cx = outWidth / 2;
  final cy = outHeight / 2;
  for (var y = 0; y < outHeight; y++) {
    final sy = math.min(y ~/ scale, h - 1);
    final scan = (y % scale == scale - 1) ? 0.45 : 1.0;
    final dy = (y - cy) / cy;
    for (var x = 0; x < outWidth; x++) {
      if (!_insideRoundedRect(x.toDouble(), y.toDouble(), outWidth.toDouble(), outHeight.toDouble(), radius)) {
        out.setPixelRgb(x, y, 0, 0, 0);
        continue;
      }
      final sx = math.min(x ~/ scale, w - 1);
      final i = (sy * w + sx) * 3;
      final dx = (x - cx) / cx;
      final vignette = math.max(0.0, 1.0 - 0.5 * (dx * dx + dy * dy));
      final sub = x % scale; // 0=R 1=G 2=B 강조
      final f = scan * vignette;
      out.setPixelRgb(
        x,
        y,
        _clamp(bled[i] * f * (sub == 0 ? 1.0 : 0.82)),
        _clamp(bled[i + 1] * f * (sub == 1 ? 1.0 : 0.82)),
        _clamp(bled[i + 2] * f * (sub == 2 ? 1.0 : 0.82)),
      );
    }
  }
  return out;
}

bool _insideRoundedRect(double x, double y, double w, double h, double r) {
  final nx = x < r ? r - x : (x > w - 1 - r ? x - (w - 1 - r) : 0.0);
  final ny = y < r ? r - y : (y > h - 1 - r ? y - (h - 1 - r) : 0.0);
  return nx * nx + ny * ny <= r * r;
}

/// ASCII: 밝기만 남겨 글자로 바꾼다. 어두운 곳은 빈칸, 밝은 곳은 @.
List<String> asciiArt(img.Image base, {int cols = asciiCols, int rows = asciiRows}) {
  final cellW = base.width / cols;
  final cellH = base.height / rows;
  final values = List<double>.filled(cols * rows, 0);

  for (var r = 0; r < rows; r++) {
    final y0 = (r * cellH).floor();
    final y1 = math.max(y0 + 1, ((r + 1) * cellH).floor());
    for (var c = 0; c < cols; c++) {
      final x0 = (c * cellW).floor();
      final x1 = math.max(x0 + 1, ((c + 1) * cellW).floor());
      var sum = 0.0;
      var n = 0;
      for (var y = y0; y < y1 && y < base.height; y++) {
        for (var x = x0; x < x1 && x < base.width; x++) {
          final p = base.getPixel(x, y);
          sum += 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
          n++;
        }
      }
      values[r * cols + c] = n == 0 ? 0 : sum / n;
    }
  }

  // 어두운 사진도 글자가 보이게 밝기 범위를 넓힌다.
  var lo = 255.0;
  var hi = 0.0;
  for (final v in values) {
    lo = math.min(lo, v);
    hi = math.max(hi, v);
  }
  final span = hi - lo < 1 ? 1.0 : hi - lo;

  final lines = <String>[];
  final sb = StringBuffer();
  for (var r = 0; r < rows; r++) {
    sb.clear();
    for (var c = 0; c < cols; c++) {
      final t = ((values[r * cols + c] - lo) / span).clamp(0.0, 1.0);
      sb.write(asciiRamp[(t * (asciiRamp.length - 1)).round()]);
    }
    lines.add(sb.toString());
  }
  return lines;
}
