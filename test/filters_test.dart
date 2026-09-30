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
  test('기준 사진은 가운데를 4:3 가로로 잘라 320x240 이 된다', () {
    final base = prepareBase(_portraitJpeg());
    expect(base.width, baseWidth);
    expect(base.height, baseHeight);
  });

  test('WEBCAM, CRT 는 960x720 PNG 를 만든다', () {
    for (final mode in [CaptureMode.webcam, CaptureMode.crt]) {
      final shot = processShot(_portraitJpeg(), mode);
      expect(shot.png, isNotNull);
      final decoded = img.decodePng(shot.png!)!;
      expect(decoded.width, outWidth);
      expect(decoded.height, outHeight);
      expect(shot.asciiLines, isNull);
    }
  });

  test('CRT 는 둥근 모서리 바깥이 검정이다', () {
    final out = crtFilter(prepareBase(_portraitJpeg()));
    final corner = out.getPixel(0, outHeight - 1);
    expect([corner.r, corner.g, corner.b], [0, 0, 0]);
  });

  test('ASCII 는 정해진 크기의 글자 그림이고, 어두운 위쪽은 빈칸, 밝은 아래쪽은 @ 다', () {
    final shot = processShot(_portraitJpeg(), CaptureMode.ascii);
    final lines = shot.asciiLines!;
    expect(lines, hasLength(asciiRows));
    for (final l in lines) {
      expect(l, hasLength(asciiCols));
      expect(l.split('').every(asciiRamp.contains), isTrue);
    }
    expect(lines.first.trim(), isEmpty);
    expect(lines.last, '@' * asciiCols);
    expect(shot.printRows, asciiRows);
  });

  test('결과 PNG 에는 EXIF(위치정보 등)가 없다', () {
    final shot = processShot(_portraitJpeg(), CaptureMode.webcam);
    final decoded = img.decodePng(shot.png!)!;
    expect(decoded.exif.isEmpty, isTrue);
  });

  test('다른 Isolate 에서 처리해도 된다 (object is unsendable 오류가 없어야 한다)', () async {
    for (final mode in CaptureMode.values) {
      final shot = await processShotInBackground(_portraitJpeg(), mode, mirror: true);
      expect(shot.mode, mode);
    }
  });

  test('ramp 앞뒤는 빈칸과 @', () {
    expect(asciiRamp[0], ' ');
    expect(asciiRamp[asciiRamp.length - 1], '@');
  });
}
