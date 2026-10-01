import 'dart:typed_data';

import 'package:camera_exe/logic/capture_mode.dart';
import 'package:camera_exe/logic/filters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// 위는 어둡고 아래로 갈수록 밝아지는 세로 사진 (폰으로 찍은 것처럼).
Uint8List _portraitJpeg() {
  final src = img.Image(width: 300, height: 400);
  for (var y = 0; y < src.height; y++) {
    final v = (y / (src.height - 1) * 255).round();
    for (var x = 0; x < src.width; x++) {
      src.setPixelRgb(x, y, v, v, v);
    }
  }
  return img.encodeJpg(src, quality: 95);
}

void main() {
  test('2X: 세워 찍은 사진은 세로 480x640, 눕혀 찍은 사진은 가로 640x480', () {
    final p = prepareBase(_portraitJpeg());
    expect([p.width, p.height], [480, 640]);
    final l = prepareBase(_flatJpeg(100));
    expect([l.width, l.height], [640, 480]);
  });

  test('MAX: 사진보다 크게 키우지 않는다 (300x400 세로 → 그대로 3:4, 짝수)', () {
    final base = prepareBase(_portraitJpeg(), quality: CaptureQuality.max);
    expect(base.width, lessThanOrEqualTo(300));
    expect(base.width.isEven && base.height.isEven, isTrue);
    expect((base.width / base.height - 3 / 4).abs(), lessThan(0.02));
  });

  test('눕혀 찍으면(turn 270) 세로로 찍힌 사진을 돌려 가로 640x480', () {
    final b = prepareBase(_portraitJpeg(), turn: 270);
    expect([b.width, b.height], [640, 480]);
  });

  test('뷰파인더 프레임: 세 모드 · 두 화질 모두 같은 크기의 RGBA', () {
    const w = 480, h = 640;
    final rgb = Uint8List(w * h * 3)..fillRange(0, w * h * 3, 120);
    for (final mode in CaptureMode.values) {
      for (final q in CaptureQuality.values) {
        expect(previewFrame(mode, q, rgb, w, h, seed: 2).length, w * h * 4, reason: '${mode.name} ${q.name}');
      }
    }
  });

  test('MAX: 폰 카메라 세로 1080x1920 → 1080x1440', () {
    final base = prepareBase(_bigJpeg(portrait: true), quality: CaptureQuality.max);
    expect([base.width, base.height], [1080, 1440]);
  });

  test('2X: WEBCAM 은 절반으로 줄인 픽셀을 4배로 키운다 (세로 960x1280)', () {
    final shot = processShot(_portraitJpeg(), CaptureMode.webcam);
    final decoded = img.decodePng(shot.png!)!;
    expect(decoded.width, 960);
    expect(decoded.height, 1280);
    expect(shot.resWidth, 480);
    expect(shot.resHeight, 640);
    expect(shot.aspect, closeTo(3 / 4, 0.001));
    expect(shot.exportPixelRatio, greaterThan(3));
  });

  test('2X: BUTTER, TRIP 은 기준 크기 그대로 (세로 480x640)', () {
    for (final mode in [CaptureMode.butter, CaptureMode.trip]) {
      final decoded = img.decodePng(processShot(_portraitJpeg(), mode).png!)!;
      expect([decoded.width, decoded.height], [480, 640]);
    }
  });

  test('MAX: 세 모드 모두 1440x1080 (픽셀화 없음)', () {
    final jpeg = _bigJpeg();
    for (final mode in CaptureMode.values) {
      final shot = processShot(jpeg, mode, quality: CaptureQuality.max);
      final decoded = img.decodePng(shot.png!)!;
      expect([decoded.width, decoded.height], [1440, 1080]);
      expect(shot.quality, CaptureQuality.max);
    }
  });

  test('BUTTER 는 밝고 부드럽다: 평균이 원본보다 밝고, 검정이 떠 있다', () {
    final base = prepareBase(_portraitJpeg());
    final out = butterFilter(base);
    expect(_mean(out), greaterThan(_mean(base)));
    final darkest = out.getPixel(240, 0); // 맨 위 = 원본에서 가장 어두운 줄
    expect(darkest.r, greaterThan(10));
  });

  test('BUTTER 는 피부색을 더 밝게 · 덜 노랗게 한다', () {
    // 전형적인 피부색 (220, 170, 140) 과, 비슷한 밝기의 회색
    final skin = butterFilter(prepareBase(_colorJpeg(220, 170, 140))).getPixel(320, 240);
    final plain = butterFilter(prepareBase(_colorJpeg(184, 184, 184))).getPixel(320, 240);
    expect(skin.r + skin.g + skin.b, greaterThan(plain.r + plain.g + plain.b));
    // 피부: 노란기(빨강+초록 - 파랑 쪽)가 원본보다 줄었다
    expect((skin.r + skin.g) / 2 - skin.b, lessThan((220 + 170) / 2 - 140));
  });

  test('TRIP 은 따뜻하고 바랬다: 가운데 회색이 붉은 쪽, 검정이 떠 있다', () {
    final out = tripFilter(prepareBase(_flatJpeg(128)));
    final mid = out.getPixel(200, 300);
    expect(mid.r, greaterThan(mid.b));
    final dark = tripFilter(prepareBase(_flatJpeg(0))).getPixel(320, 240);
    expect(dark.r + dark.g + dark.b, greaterThan(30));
  });

  test('TRIP 은 오른쪽 위에 빛이 샌다', () {
    final out = tripFilter(prepareBase(_flatJpeg(60)));
    final leak = out.getPixel(635, 40), left = out.getPixel(5, 40);
    expect(leak.r, greaterThan(left.r + 30));
  });

  test('결과 PNG 에는 EXIF(위치정보 등)가 없다', () {
    final shot = processShot(_portraitJpeg(), CaptureMode.webcam);
    final decoded = img.decodePng(shot.png!)!;
    expect(decoded.exif.isEmpty, isTrue);
  });

  test('다른 Isolate 에서 처리해도 된다 (object is unsendable 오류가 없어야 한다)', () async {
    for (final mode in CaptureMode.values) {
      for (final q in CaptureQuality.values) {
        final shot = await processShotInBackground(_portraitJpeg(), mode, mirror: true, quality: q);
        expect(shot.mode, mode);
        expect(shot.quality, q);
      }
    }
  });
}

/// 폰 카메라(veryHigh)처럼 1920x1080 가로 (또는 1080x1920 세로) 사진.
Uint8List _bigJpeg({bool portrait = false}) {
  final src = portrait ? img.Image(width: 1080, height: 1920) : img.Image(width: 1920, height: 1080);
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      src.setPixelRgb(x, y, x * 255 ~/ (src.width - 1), y * 255 ~/ (src.height - 1), 128);
    }
  }
  return img.encodeJpg(src, quality: 90);
}

/// 한 가지 밝기로 채운 사진.
Uint8List _flatJpeg(int v) {
  final src = img.Image(width: 400, height: 300);
  img.fill(src, color: img.ColorRgb8(v, v, v));
  return img.encodeJpg(src, quality: 95);
}

double _mean(img.Image im) {
  var sum = 0.0;
  for (final p in im) {
    sum += p.r + p.g + p.b;
  }
  return sum / (im.width * im.height * 3);
}

Uint8List _colorJpeg(int r, int g, int b) {
  final src = img.Image(width: 400, height: 300);
  img.fill(src, color: img.ColorRgb8(r, g, b));
  return img.encodeJpg(src, quality: 98);
}
