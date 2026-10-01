import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'capture_mode.dart';

/// 결과 사진 한 장.
class ProcessedShot {
  const ProcessedShot({
    required this.mode,
    this.quality = CaptureQuality.x2,
    this.png,
    this.width = 0,
    this.height = 0,
    this.resWidth = 0,
    this.resHeight = 0,
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

  /// 가로/세로 비율 (가로 사진 4:3, 세로 사진 3:4)
  double get aspect => resWidth > 0 && resHeight > 0 ? resWidth / resHeight : 4 / 3;

  /// 출력 애니메이션이 몇 줄로 나눠서 보여줄지.
  int get printRows => 24;

  /// 저장 · 공유할 때 화면을 몇 배로 떠야 사진이 뭉개지지 않는지 (사진 칸은 화면에서 약 300pt).
  double get exportPixelRatio {
    return (width / 300).clamp(3.0, 6.0).toDouble();
  }
}

/// 화질별 크기.
class QualitySpec {
  const QualitySpec({
    required this.baseWidth,
    required this.baseHeight,
    required this.webcamLowWidth,
    required this.webcamScale,
  });

  /// 기준 크기 (가운데 4:3 을 잘라 이 크기로 줄인다). MAX 는 사진이 작으면 더 작아질 수 있다.
  final int baseWidth;
  final int baseHeight;

  /// WEBCAM: 이 가로 크기로 줄였다가 [webcamScale] 배로 키워 픽셀을 키운다. base 와 같으면 픽셀화 없음.
  final int webcamLowWidth;
  final int webcamScale;

  static QualitySpec of(CaptureQuality q) => switch (q) {
        CaptureQuality.x2 => const QualitySpec(
            baseWidth: 640,
            baseHeight: 480,
            webcamLowWidth: 320,
            webcamScale: 4,
          ),
        CaptureQuality.max => const QualitySpec(
            baseWidth: 1440,
            baseHeight: 1080,
            webcamLowWidth: 1440,
            webcamScale: 1,
          ),
      };
}


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
      return image(webcamFilter(base, spec: spec));
    case CaptureMode.butter:
      return image(butterFilter(base));
    case CaptureMode.trip:
      return image(tripFilter(base));
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

/// 방향을 바로잡고, 가운데를 4:3 (세로 사진이면 3:4) 로 잘라 화질에 맞는 크기로 줄인다.
/// (촬영 화면의 뷰파인더도 가운데 3:4 를 보여준다. 폰을 눕히면 그대로 4:3 이 된다.)
img.Image prepareBase(Uint8List jpeg, {bool mirror = false, CaptureQuality quality = CaptureQuality.x2}) {
  final decoded = img.decodeImage(jpeg);
  if (decoded == null) {
    throw const FormatException('사진을 읽지 못했어요.');
  }
  var src = img.bakeOrientation(decoded);
  if (mirror) src = img.flipHorizontal(src);
  final spec = QualitySpec.of(quality);
  // 폰을 세워 찍으면 세로(3:4), 눕혀 찍으면 가로(4:3). 카메라가 폰 방향을 사진에 적어 주고
  // bakeOrientation 이 그 방향대로 돌려 놓았으니, 사진 모양만 보면 된다.
  final portrait = src.height > src.width;
  final tw = portrait ? spec.baseHeight : spec.baseWidth;
  final th = portrait ? spec.baseWidth : spec.baseHeight;
  var w = tw, h = th;
  if (quality == CaptureQuality.max) {
    // 사진보다 크게 키우지는 않는다 (짝수로 맞춘다).
    final crop = _cropSize(src.width, src.height, tw / th);
    if (crop.$1 < w) {
      w = crop.$1 & ~1;
      h = (w * th / tw).round() & ~1;
    }
  }
  return centerCropResize(src, w, h);
}

/// [aspect] (가로/세로) 로 가운데를 자를 때의 크기.
(int, int) _cropSize(int sw, int sh, double aspect) {
  var cw = sw;
  var ch = (sw / aspect).round();
  if (ch > sh) {
    ch = sh;
    cw = (sh * aspect).round();
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
/// [seed] 를 바꾸면 노이즈 모양이 바뀐다 (클립에서 프레임마다 자글자글 움직이게).
img.Image webcamFilter(img.Image base, {QualitySpec? spec, int seed = 0}) {
  final s = spec ?? QualitySpec.of(CaptureQuality.x2);
  // 기준 크기에 대한 비율로 줄인다 (세로 사진이면 가로가 더 좁다).
  final lowW = _mini(base.width, _maxi(1, (base.width * s.webcamLowWidth / s.baseWidth).round()));
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
      final n = (_hash(x + seed * 7919, y + seed * 104729) / 255.0 - 0.5) * noise;
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

/// 밝기 (0~1)
double _luma(double r, double g, double b) => 0.299 * r + 0.587 * g + 0.114 * b;

double _unit(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

img.Image _fromRgb(int w, int h, Uint8List rgb) =>
    img.Image.fromBytes(width: w, height: h, bytes: rgb.buffer, numChannels: 3);

/// 흐리게 뭉갠 사진 (빛 번짐용). 작게 줄여 흐린 뒤 다시 키운다.
Uint8List _blurred(img.Image base, {int radius = 3}) {
  final w = base.width, h = base.height;
  var small = img.copyResize(base, width: _maxi(8, w ~/ 8), height: _maxi(6, h ~/ 8), interpolation: img.Interpolation.average);
  small = img.gaussianBlur(small, radius: radius);
  final big = img.copyResize(small, width: w, height: h, interpolation: img.Interpolation.linear);
  return big.getBytes(order: img.ChannelOrder.rgb);
}

/// BUTTER: 요즘 유행하는 뽀샤시 버터 느낌. 안개가 낀 듯 뽀얗게.
/// 흐리게 → 밝은 곳이 빛처럼 번지고 → 밝게 → 우윳빛 안개 → 채도 낮춤 → 크림색.
img.Image butterFilter(img.Image base) {
  final w = base.width, h = base.height;
  final src = base.getBytes(order: img.ChannelOrder.rgb);
  final blur = _blurred(base, radius: 4);
  final out = Uint8List(w * h * 3);
  for (var i = 0; i < w * h * 3; i += 3) {
    var r = src[i] / 255, g = src[i + 1] / 255, b = src[i + 2] / 255;
    final br = blur[i] / 255, bg = blur[i + 1] / 255, bb = blur[i + 2] / 255;
    // 1) 흐리게 (soft focus)
    r = r * 0.65 + br * 0.35;
    g = g * 0.65 + bg * 0.35;
    b = b * 0.65 + bb * 0.35;
    // 2) 밝은 곳이 번지는 빛 (흐린 그림의 밝은 부분을 screen 으로 더한다)
    final hl = _unit((_luma(br, bg, bb) - 0.35) / 0.65) * 0.85;
    r = 1 - (1 - r) * (1 - br * hl);
    g = 1 - (1 - g) * (1 - bg * hl);
    b = 1 - (1 - b) * (1 - bb * hl);
    // 3) 밝게 (어두운 곳 · 밝은 끝은 덜, 가운데를 많이)
    r += (1 - r) * r * 0.45;
    g += (1 - g) * g * 0.45;
    b += (1 - b) * b * 0.45;
    // 4) 안개: 전체를 우윳빛 쪽으로 (검정이 뜨고 대비가 낮아진다)
    r = r * 0.80 + 1.00 * 0.20;
    g = g * 0.80 + 0.97 * 0.20;
    b = b * 0.80 + 0.93 * 0.20;
    // 5) 채도 85%
    final l = _luma(r, g, b);
    r = l + (r - l) * 0.85;
    g = l + (g - l) * 0.85;
    b = l + (b - l) * 0.85;
    // 6) 버터 색: 밝을수록 크림색 쪽으로
    final k = l * 0.22;
    r = (r * (1 - k) + 1.00 * k) * 1.02;
    g = (g * (1 - k) + 0.95 * k) * 1.00;
    b = (b * (1 - k) + 0.80 * k) * 0.94;
    out[i] = _clamp(r * 255);
    out[i + 1] = _clamp(g * 255);
    out[i + 2] = _clamp(b * 255);
  }
  return _fromRgb(w, h, out);
}

/// TRIP: 여행을 추억하는 필름 느낌.
/// 바랜 색 · 어두운 곳은 청록, 밝은 곳은 금빛 · 오른쪽 위에서 새어 드는 주황빛 · 필름 입자 · 가장자리 어둠.
/// [seed] 를 바꾸면 필름 입자가 바뀐다 (클립에서 프레임마다 움직이게).
img.Image tripFilter(img.Image base, {int seed = 0}) {
  final w = base.width, h = base.height;
  final src = base.getBytes(order: img.ChannelOrder.rgb);
  final out = Uint8List(w * h * 3);
  // 입자 크기: 사진이 크면 입자도 조금 크게 (MAX 는 2px)
  final grainShift = w >= 1000 ? 1 : 0;
  final leakX = w * 1.04, leakY = h * 0.12;
  for (var y = 0; y < h; y++) {
    final dy = (y - h / 2) / (h / 2);
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 3;
      var r = src[i] / 255, g = src[i + 1] / 255, b = src[i + 2] / 255;
      // 1) 채도 82%
      var l = _luma(r, g, b);
      r = l + (r - l) * 0.82;
      g = l + (g - l) * 0.82;
      b = l + (b - l) * 0.82;
      // 2) 부드러운 S 곡선 (대비 살짝)
      r += (r - 0.5) * (1 - (r - 0.5).abs() * 2) * 0.18;
      g += (g - 0.5) * (1 - (g - 0.5).abs() * 2) * 0.18;
      b += (b - 0.5) * (1 - (b - 0.5).abs() * 2) * 0.18;
      // 3) 어두운 곳은 청록, 밝은 곳은 금빛
      l = _luma(r, g, b);
      final sh = (1 - l) * (1 - l), hi = l * l;
      r += sh * -0.06 + hi * 0.10;
      g += sh * 0.02 + hi * 0.05;
      b += sh * 0.05 + hi * -0.08;
      // 4) 바랜 검정 + 따뜻하게
      r = (0.08 + r * 0.86) * 1.04;
      g = (0.08 + g * 0.86) * 1.00;
      b = (0.08 + b * 0.86) * 0.90;
      // 5) 빛 샘 (light leak)
      final ldx = (x - leakX) / w, ldy = (y - leakY) / w;
      final t = 1 - math.sqrt(ldx * ldx + ldy * ldy) / 0.7;
      if (t > 0) {
        final leak = t * t * 0.85;
        r = 1 - (1 - r) * (1 - leak * 1.0);
        g = 1 - (1 - g) * (1 - leak * 0.5);
        b = 1 - (1 - b) * (1 - leak * 0.18);
      }
      // 6) 가장자리 어둠
      final dx = (x - w / 2) / (w / 2);
      final v = 1 - 0.22 * (dx * dx + dy * dy);
      // 7) 필름 입자
      final n = (_hash((x >> grainShift) + seed * 7919, (y >> grainShift) + seed * 104729) / 255 - 0.5) * 0.09;
      out[i] = _clamp((r * v + n) * 255);
      out[i + 1] = _clamp((g * v + n) * 255);
      out[i + 2] = _clamp((b * v + n) * 255);
    }
  }
  return _fromRgb(w, h, out);
}
