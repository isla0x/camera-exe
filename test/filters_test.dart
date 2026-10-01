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
  test('2X: 가운데를 4:3 가로로 잘라 640x480 이 된다', () {
    final base = prepareBase(_portraitJpeg());
    expect(base.width, 640);
    expect(base.height, 480);
  });

  test('MAX: 사진보다 크게 키우지 않는다 (300x400 → 가운데 300x225 근처, 짝수)', () {
    final base = prepareBase(_portraitJpeg(), quality: CaptureQuality.max);
    expect(base.width, lessThanOrEqualTo(300));
    expect(base.width.isEven && base.height.isEven, isTrue);
    expect((base.width / base.height - 4 / 3).abs(), lessThan(0.02));
  });

  test('2X: WEBCAM 은 320x240 픽셀을 4배로 키운 1280x960', () {
    final shot = processShot(_portraitJpeg(), CaptureMode.webcam);
    final decoded = img.decodePng(shot.png!)!;
    expect(decoded.width, 1280);
    expect(decoded.height, 960);
    expect(shot.resWidth, 640);
    expect(shot.resHeight, 480);
    expect(shot.exportPixelRatio, greaterThan(3));
  });

  test('2X: BUTTER, TRIP 은 기준 크기 640x480 그대로', () {
    for (final mode in [CaptureMode.butter, CaptureMode.trip]) {
      final decoded = img.decodePng(processShot(_portraitJpeg(), mode).png!)!;
      expect([decoded.width, decoded.height], [640, 480]);
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
    final darkest = out.getPixel(320, 0); // 맨 위 = 원본에서 가장 어두운 줄
    expect(darkest.r, greaterThan(10));
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

/// 폰 카메라(veryHigh)처럼 1920x1080 가로 사진.
Uint8List _bigJpeg() {
  final src = img.Image(width: 1920, height: 1080);
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      src.setPixelRgb(x, y, x * 255 ~/ 1919, y * 255 ~/ 1079, 128);
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
