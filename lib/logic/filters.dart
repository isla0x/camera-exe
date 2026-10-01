import 'dart:isolate';
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
ProcessedShot processShot(
  Uint8List jpeg,
  CaptureMode mode, {
  bool mirror = false,
  CaptureQuality quality = CaptureQuality.x2,
  int turn = 0,
}) {
  final spec = QualitySpec.of(quality);
  final base = prepareBase(jpeg, mirror: mirror, quality: quality, turn: turn);
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
    case CaptureMode.soft:
      return image(soft35Filter(base));
    case CaptureMode.dispo:
      return image(dispoFilter(base));
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
  int turn = 0,
}) {
  return Isolate.run(() => processShot(jpeg, mode, mirror: mirror, quality: quality, turn: turn));
}

/// 방향을 바로잡고, 가운데를 4:3 (세로 사진이면 3:4) 로 잘라 화질에 맞는 크기로 줄인다.
/// (촬영 화면의 뷰파인더도 가운데 3:4 를 보여준다. 폰을 눕히면 그대로 4:3 이 된다.)
///
/// [turn]: 폰을 눕혀 찍었을 때 세상이 바로 서도록 시계 방향으로 더 돌릴 각도 (uprightTurn).
/// 카메라 방향을 세로로 고정해 두어서, 찍힌 사진은 늘 폰 기준 세로다.
img.Image prepareBase(Uint8List jpeg, {bool mirror = false, CaptureQuality quality = CaptureQuality.x2, int turn = 0}) {
  final decoded = img.decodeImage(jpeg);
  if (decoded == null) {
    throw const FormatException('사진을 읽지 못했어요.');
  }
  var src = img.bakeOrientation(decoded);
  if (turn % 360 != 0) src = img.copyRotate(src, angle: turn);
  if (mirror) src = img.flipHorizontal(src);
  final spec = QualitySpec.of(quality);
  // 폰을 세워 찍으면 세로(3:4), 눕혀 찍으면 가로(4:3). 위에서 세상이 바로 서게 돌려 놓았으니 사진 모양만 보면 된다.
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

/// SOFT35: 파스텔 필름 똑딱이.
/// 필터 앱 인기 순위 상위권 'CPM35' 류의 느낌 (90년대 캐논 필름 똑딱이):
/// 채도 낮은 파스텔 · 낮은 대비 · 살짝 몽환 · 밝은 곳 분홍빛 · 그늘 살짝 푸른빛 · 입자 적음.
/// [seed] 를 바꾸면 입자가 바뀐다 (뷰파인더 · 클립에서 프레임마다 움직이게).
img.Image soft35Filter(img.Image base, {int seed = 0}) {
  final w = base.width, h = base.height;
  final src = base.getBytes(order: img.ChannelOrder.rgb);
  final blur = _blurred(base);
  final out = Uint8List(w * h * 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 3;
      var r = src[i] / 255, g = src[i + 1] / 255, b = src[i + 2] / 255;
      final br = blur[i] / 255, bg = blur[i + 1] / 255, bb = blur[i + 2] / 255;
      // 1) 살짝 부드럽게
      r = r * 0.88 + br * 0.12;
      g = g * 0.88 + bg * 0.12;
      b = b * 0.88 + bb * 0.12;
      // 2) 밝은 곳 은은한 번짐
      final gl = _unit((_luma(br, bg, bb) - 0.6) / 0.4) * 0.25;
      r = 1 - (1 - r) * (1 - br * gl);
      g = 1 - (1 - g) * (1 - bg * gl);
      b = 1 - (1 - b) * (1 - bb * gl);
      // 3) 노출 살짝 +
      r += (1 - r) * r * 0.22;
      g += (1 - g) * g * 0.22;
      b += (1 - b) * b * 0.22;
      // 4) 채도 74% (파스텔)
      var l = _luma(r, g, b);
      r = l + (r - l) * 0.74;
      g = l + (g - l) * 0.74;
      b = l + (b - l) * 0.74;
      // 5) 대비 ↓ · 검정 살짝 띄움
      r = 0.045 + (0.5 + (r - 0.5) * 0.86) * 0.955;
      g = 0.045 + (0.5 + (g - 0.5) * 0.86) * 0.955;
      b = 0.045 + (0.5 + (b - 0.5) * 0.86) * 0.955;
      // 6) 그늘은 살짝 푸르게, 밝은 곳은 분홍빛
      l = _luma(r, g, b);
      final sh = (1 - l) * (1 - l), hi = l * l;
      r += sh * -0.015 + hi * 0.035;
      g += hi * 0.005;
      b += sh * 0.035;
      // 7) 입자 (적게)
      final n = (_hash(x + seed * 7919, y + seed * 104729) / 255 - 0.5) * 0.025;
      out[i] = _clamp((r + n) * 255);
      out[i + 1] = _clamp((g + n) * 255);
      out[i + 2] = _clamp((b + n) * 255);
    }
  }
  return _fromRgb(w, h, out);
}

/// DISPO: 일회용 필름카메라.
/// 필터 앱 인기 순위 상위권 'D FunS' 류의 느낌 (코닥 일회용 카메라 · 컬러플러스 200 필름):
/// 따뜻하고 진한 색 · 대비 ↑ · 그늘에 초록빛 · 밝은 곳 금빛 · 가장자리 어둠 · 굵은 입자 · 날짜 도장.
img.Image dispoFilter(img.Image base, {int seed = 0}) {
  final w = base.width, h = base.height;
  final src = base.getBytes(order: img.ChannelOrder.rgb);
  final blur = _blurred(base);
  final out = Uint8List(w * h * 3);
  for (var y = 0; y < h; y++) {
    final dy = (y - h / 2) / (h / 2);
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 3;
      var r = src[i] / 255, g = src[i + 1] / 255, b = src[i + 2] / 255;
      // 1) 플라스틱 렌즈의 살짝 무른 느낌
      r = r * 0.92 + blur[i] / 255 * 0.08;
      g = g * 0.92 + blur[i + 1] / 255 * 0.08;
      b = b * 0.92 + blur[i + 2] / 255 * 0.08;
      // 2) 채도 ↑
      var l = _luma(r, g, b);
      r = l + (r - l) * 1.12;
      g = l + (g - l) * 1.12;
      b = l + (b - l) * 1.12;
      // 3) S 곡선 (대비 ↑)
      r += (r - 0.5) * (1 - (r - 0.5).abs() * 2) * 0.30;
      g += (g - 0.5) * (1 - (g - 0.5).abs() * 2) * 0.30;
      b += (b - 0.5) * (1 - (b - 0.5).abs() * 2) * 0.30;
      // 4) 그늘 초록빛 · 중간 따뜻하게 · 밝은 곳 금빛
      l = _unit(_luma(r, g, b));
      final sh = (1 - l) * (1 - l), mid = 4 * l * (1 - l), hi = l * l;
      r += sh * -0.03 + mid * 0.015 + hi * 0.05;
      g += sh * 0.035 + mid * 0.012 + hi * 0.03;
      b += sh * -0.01 + mid * -0.03 + hi * -0.06;
      // 5) 검정 아주 살짝 띄움
      r = 0.03 + r * 0.97;
      g = 0.03 + g * 0.97;
      b = 0.03 + b * 0.97;
      // 6) 가장자리 어둠 (값싼 렌즈)
      final dx = (x - w / 2) / (w / 2);
      final v = 1 - 0.30 * (dx * dx + dy * dy);
      // 7) 굵은 입자
      final n = (_hash(x + seed * 7919, y + seed * 104729) / 255 - 0.5) * 0.075;
      out[i] = _clamp((r * v + n) * 255);
      out[i + 1] = _clamp((g * v + n) * 255);
      out[i + 2] = _clamp((b * v + n) * 255);
    }
  }
  return _fromRgb(w, h, out);
}

/// 뷰파인더 한 장: 저장할 때와 같은 필터를 같은 비율로 입혀 RGBA 로 돌려준다 (크기는 그대로).
/// [seed] 로 노이즈 · 필름 입자가 프레임마다 움직인다.
Uint8List previewFrame(CaptureMode mode, CaptureQuality quality, Uint8List rgb, int w, int h, {int seed = 0}) {
  final base = img.Image.fromBytes(width: w, height: h, bytes: rgb.buffer, numChannels: 3);
  final q = QualitySpec.of(quality);
  // WEBCAM 픽셀 크기를 저장할 때와 같은 비율로 (2X 는 가로의 절반 칸, MAX 는 픽셀화 없음)
  final frac = q.webcamLowWidth / q.baseWidth;
  final out = switch (mode) {
    CaptureMode.webcam => webcamFilter(
        base,
        spec: QualitySpec(
          baseWidth: w,
          baseHeight: h,
          webcamLowWidth: (w * frac).round(),
          webcamScale: frac >= 1 ? 1 : (1 / frac).round(),
        ),
        seed: seed,
      ),
    CaptureMode.soft => soft35Filter(base, seed: seed),
    CaptureMode.dispo => dispoFilter(base, seed: seed),
  };
  final rgba = out.numChannels == 4 ? out : out.convert(numChannels: 4, alpha: 255);
  return rgba.getBytes(order: img.ChannelOrder.rgba);
}
