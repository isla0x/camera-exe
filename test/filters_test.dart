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
  final x2 = QualitySpec.of(CaptureQuality.x2);

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

  test('2X: WEBCAM, CRT 는 1280x960 PNG', () {
    for (final mode in [CaptureMode.webcam, CaptureMode.crt]) {
      final shot = processShot(_portraitJpeg(), mode);
      expect(shot.png, isNotNull);
      final decoded = img.decodePng(shot.png!)!;
      expect(decoded.width, 1280);
      expect(decoded.height, 960);
      expect(shot.resWidth, 640);
      expect(shot.resHeight, 480);
      expect(shot.asciiLines, isNull);
      expect(shot.exportPixelRatio, greaterThan(3));
    }
  });

  test('MAX: WEBCAM, CRT 는 기준 크기 그대로 (픽셀화 없음)', () {
    final jpeg = _bigJpeg();
    for (final mode in [CaptureMode.webcam, CaptureMode.crt]) {
      final shot = processShot(jpeg, mode, quality: CaptureQuality.max);
      final decoded = img.decodePng(shot.png!)!;
      expect(decoded.width, 1440);
      expect(decoded.height, 1080);
      expect(shot.quality, CaptureQuality.max);
    }
  });

  test('CRT 는 둥근 모서리 바깥이 검정이다', () {
    final out = crtFilter(prepareBase(_portraitJpeg()), x2);
    final corner = out.getPixel(0, out.height - 1);
    expect([corner.r, corner.g, corner.b], [0, 0, 0]);
  });

  test('ASCII 는 화질에 맞는 크기, 어두운 위쪽은 빈칸, 밝은 아래쪽은 @', () {
    for (final q in CaptureQuality.values) {
      final spec = QualitySpec.of(q);
      final shot = processShot(_portraitJpeg(), CaptureMode.ascii, quality: q);
      final lines = shot.asciiLines!;
      expect(lines, hasLength(spec.asciiRows));
      for (final l in lines) {
        expect(l, hasLength(spec.asciiCols));
        expect(l.split('').every(asciiRamp.contains), isTrue);
      }
      expect(lines.first.trim(), isEmpty);
      expect(lines.last, '@' * spec.asciiCols);
      expect(shot.printRows, spec.asciiRows);
    }
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

  test('ramp 앞뒤는 빈칸과 @', () {
    expect(asciiRamp[0], ' ');
    expect(asciiRamp[asciiRamp.length - 1], '@');
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
