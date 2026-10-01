import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'capture_mode.dart';

/// 결과 사진 한 장. 이미지 모드는 [png], ASCII 모드는 [asciiLines] 가 채워진다.
class ProcessedShot {
  const ProcessedShot({
    required this.mode,
    this.quality = CaptureQuality.x2,
    this.png,
    this.width = 0,
    this.height = 0,
    this.resWidth = 0,
    this.resHeight = 0,
    this.asciiLines,
  });

  final CaptureMode mode;
  final CaptureQuality quality;
  final Uint8List? png;

  /// [png] 크기
  final int width;
  final int height;

  /// 기준 해상도 (뷰어 창 아래에 `640 x 480` 처럼 보인다)
  final int resWidth;
  final int resHeight;
  final List<String>? asciiLines;

  /// 출력 애니메이션이 몇 줄로 나눠서 보여줄지.
  int get printRows => asciiLines?.length ?? 24;

  /// 저장 · 공유할 때 화면을 몇 배로 떠야 사진이 뭉개지지 않는지 (사진 칸은 화면에서 약 300pt).
  double get exportPixelRatio {
    final w = asciiLines != null ? (asciiLines!.first.length * 12) : width;
    return (w / 300).clamp(3.0, 6.0).toDouble();
  }
}

/// 화질별 크기.
class QualitySpec {
  const QualitySpec({
    required this.baseWidth,
    required this.baseHeight,
    required this.webcamLowWidth,
    required this.webcamScale,
    required this.crtScale,
    required this.asciiCols,
    required this.asciiRows,
  });

  /// 기준 크기 (가운데 4:3 을 잘라 이 크기로 줄인다). MAX 는 사진이 작으면 더 작아질 수 있다.
  final int baseWidth;
  final int baseHeight;

  /// WEBCAM: 이 가로 크기로 줄였다가 [webcamScale] 배로 키워 픽셀을 키운다. base 와 같으면 픽셀화 없음.
  final int webcamLowWidth;
  final int webcamScale;

  /// CRT: base 를 몇 배로 키우면서 스캔라인을 넣는지.
  final int crtScale;

  final int asciiCols;
  final int asciiRows;

  static QualitySpec of(CaptureQuality q) => switch (q) {
        CaptureQuality.x2 => const QualitySpec(
            baseWidth: 640,
            baseHeight: 480,
            webcamLowWidth: 320,
            webcamScale: 4,
            crtScale: 2,
            asciiCols: 96,
            asciiRows: 44,
          ),
        CaptureQuality.max => const QualitySpec(
            baseWidth: 1440,
            baseHeight: 1080,
            webcamLowWidth: 1440,
            webcamScale: 1,
            crtScale: 1,
            asciiCols: 128,
            asciiRows: 58,
          ),
      };
}

/// 어두운 곳 → 밝은 곳.
const asciiRamp = ' .:-=+*#%@';

int _mini(int a, int b) => a < b ? a : b;
int _maxi(int a, int b) => a > b ? a : b;

/// 카메라가 준 JPEG 을 처리한다. 무거우니 [processShotInBackground] 로 돌린다.
///
/// 픽셀만 다시 그려서 PNG 로 만들기 때문에 위치정보 같은 EXIF 는 결과에 남지 않는다.
ProcessedShot processShot(Uint8List jpeg, CaptureMode mode, {bool mirror = false, CaptureQuality quality = CaptureQuality.x2}) {
  final spec = QualitySpec.of(quality);
  final base = prepareBase(jpeg, mirror: mirror, quality: quality);
  ProcessedShot image(img.Image out) => ProcessedShot(
        mode: mode,
        quality: quality,
        png: img.encodePng(out, level: 4),
        width: out.width,
        height: out.height,
        resWidth: base.width,
        resHeight: base.height,
      );
  switch (mode) {
    case CaptureMode.webcam:
      return image(webcamFilter(base, spec));
    case CaptureMode.crt:
      return image(crtFilter(base, spec));
    case CaptureMode.ascii:
      return ProcessedShot(
        mode: mode,
        quality: quality,
        resWidth: base.width,
        resHeight: base.height,
        asciiLines: asciiArt(base, cols: spec.asciiCols, rows: spec.asciiRows),
      );
  }
}

/// [processShot] 을 다른 Isolate 에서 돌린다.
///
/// 꼭 이렇게 맨 바깥(top-level) 함수에서 불러야 한다. 화면(State)의 async 메서드 안에서
/// `Isolate.run(() => ...)` 을 만들면 클로저가 화면 전체를 붙잡고 넘어가려다
/// "object is unsendable" 오류가 난다.
Future<ProcessedShot> processShotInBackground(
  Uint8List jpeg,
  CaptureMode mode, {
  bool mirror = false,
  CaptureQuality quality = CaptureQuality.x2,
}) {
  return Isolate.run(() => processShot(jpeg, mode, mirror: mirror, quality: quality));
}

/// 방향을 바로잡고, 가운데를 4:3 가로로 잘라 화질에 맞는 크기로 줄인다.
/// (촬영 화면의 뷰파인더도 가운데 4:3 을 보여준다.)
img.Image prepareBase(Uint8List jpeg, {bool mirror = false, CaptureQuality quality = CaptureQuality.x2}) {
  final decoded = img.decodeImage(jpeg);
  if (decoded == null) {
    throw const FormatException('사진을 읽지 못했어요.');
  }
  var src = img.bakeOrientation(decoded);
  if (mirror) src = img.flipHorizontal(src);
  final spec = QualitySpec.of(quality);
  var w = spec.baseWidth;
  var h = spec.baseHeight;
  if (quality == CaptureQuality.max) {
    // 사진보다 크게 키우지는 않는다 (짝수로 맞춘다).
    final crop = _cropSize(src.width, src.height);
    if (crop.$1 < w) {
      w = crop.$1 & ~1;
      h = (w * 3 ~/ 4) & ~1;
    }
  }
  return centerCropResize(src, w, h);
}

(int, int) _cropSize(int sw, int sh) {
  var cw = sw;
  var ch = (sw * 3 / 4).round();
  if (ch > sh) {
    ch = sh;
    cw = (sh * 4 / 3).round();
  }
  return (cw, ch);
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
  if (cropped.width == w && cropped.height == h) return cropped;
  return img.copyResize(cropped, width: w, height: h, interpolation: img.Interpolation.average);
}

int _clamp(num v) => v < 0 ? 0 : (v > 255 ? 255 : v.round());

/// 같은 사진이면 같은 노이즈가 나오게 하는 간단한 난수.
int _hash(int x, int y) {
  var h = x * 374761393 + y * 668265263;
  h = (h ^ (h >> 13)) * 1274126177;
  return (h ^ (h >> 16)) & 0xFF;
}

/// WEBCAM: 바랜 색, 따뜻한 색조, 자글자글한 노이즈. 2X 는 큼직한 픽셀, MAX 는 픽셀화 없이.
img.Image webcamFilter(img.Image base, [QualitySpec? spec]) {
  final s = spec ?? QualitySpec.of(CaptureQuality.x2);
  final lowW = _mini(s.webcamLowWidth, base.width);
  final lowH = _maxi(1, (lowW * base.height / base.width).round());
  final low = (lowW == base.width && lowH == base.height)
      ? base
      : img.copyResize(base, width: lowW, height: lowH, interpolation: img.Interpolation.average);
  final noise = s.webcamScale > 1 ? 20.0 : 14.0;

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
      // 노이즈
      final n = (_hash(x, y) / 255.0 - 0.5) * noise;
      final i = (y * lowW + x) * 3;
      colors[i] = _clamp(r + n);
      colors[i + 1] = _clamp(g + n);
      colors[i + 2] = _clamp(b + n);
    }
  }

  final block = s.webcamScale;
  final outW = lowW * block;
  final outH = lowH * block;
  final out = img.Image(width: outW, height: outH);
  for (var y = 0; y < outH; y++) {
    final ly = y ~/ block;
    for (var x = 0; x < outW; x++) {
      final i = (ly * lowW + x ~/ block) * 3;
      out.setPixelRgb(x, y, colors[i], colors[i + 1], colors[i + 2]);
    }
  }
  return out;
}

/// CRT: 진한 색, 가로 스캔라인, RGB 번짐, 가장자리 어둠, 둥근 화면 모서리.
img.Image crtFilter(img.Image base, [QualitySpec? spec]) {
  final s = spec ?? QualitySpec.of(CaptureQuality.x2);
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
  // 번지는 거리: 해상도가 높을수록 조금 더 멀리
  final bleed = _maxi(1, w ~/ 480);
  final bled = Float32List(w * h * 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 3;
      final l = (y * w + (x >= bleed ? x - bleed : 0)) * 3;
      for (var c = 0; c < 3; c++) {
        bled[i + c] = src[i + c] * 0.75 + src[l + c] * 0.25;
      }
    }
  }

  // 2) 키우면서 스캔라인 · RGB 격자 · 비네팅 · 둥근 모서리
  final scale = s.crtScale;
  final outW = w * scale;
  final outH = h * scale;
  final out = img.Image(width: outW, height: outH);
  // 스캔라인 간격: 키운 만큼(2X) 또는 3줄마다(MAX)
  final period = scale > 1 ? scale : 3;
  final radius = 54.0 * outW / 960;
  final cx = outW / 2;
  final cy = outH / 2;
  for (var y = 0; y < outH; y++) {
    final sy = _mini(y ~/ scale, h - 1);
    final scan = (y % period == period - 1) ? 0.5 : 1.0;
    final dy = (y - cy) / cy;
    for (var x = 0; x < outW; x++) {
      if (!_insideRoundedRect(x.toDouble(), y.toDouble(), outW.toDouble(), outH.toDouble(), radius)) {
        out.setPixelRgb(x, y, 0, 0, 0);
        continue;
      }
      final sx = _mini(x ~/ scale, w - 1);
      final i = (sy * w + sx) * 3;
      final dx = (x - cx) / cx;
      final vignette = math.max(0.0, 1.0 - 0.5 * (dx * dx + dy * dy));
      final sub = x % 3; // 0=R 1=G 2=B 강조
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
List<String> asciiArt(img.Image base, {int cols = 96, int rows = 44}) {
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
