import 'dart:typed_data';

import 'package:camera_exe/logic/capture_mode.dart';
import 'package:camera_exe/logic/clip_recorder.dart';
import 'package:camera_exe/logic/frame_convert.dart';
import 'package:flutter_test/flutter_test.dart';

/// 가로 4 x 세로 2 BGRA 프레임. 왼쪽 위만 빨강, 나머지 검정.
RawFrame _bgraTopLeftRed() {
  final b = Uint8List(4 * 2 * 4);
  b[2] = 255; // (0,0) 의 R
  b[3] = 255;
  return RawFrame(width: 4, height: 2, planes: [b], rowStrides: [16], pixelStrides: [4], bgra: true);
}

int _r(Uint8List rgb, int w, int x, int y) => rgb[(y * w + x) * 3];

void main() {
  test('돌리지 않으면 왼쪽 위 그대로', () {
    final out = frameToRgb(_bgraTopLeftRed(), rotation: 0, mirror: false, outW: 4, outH: 2);
    expect(_r(out, 4, 0, 0), 255);
    expect(_r(out, 4, 3, 1), 0);
  });

  test('시계 방향 90도: 왼쪽 위가 오른쪽 위로 (세로 2x4)', () {
    final out = frameToRgb(_bgraTopLeftRed(), rotation: 90, mirror: false, outW: 2, outH: 4);
    expect(_r(out, 2, 1, 0), 255);
    expect(_r(out, 2, 0, 0), 0);
  });

  test('270도: 왼쪽 위가 왼쪽 아래로', () {
    final out = frameToRgb(_bgraTopLeftRed(), rotation: 270, mirror: false, outW: 2, outH: 4);
    expect(_r(out, 2, 0, 3), 255);
  });

  test('앞카메라는 좌우 반전', () {
    final out = frameToRgb(_bgraTopLeftRed(), rotation: 0, mirror: true, outW: 4, outH: 2);
    expect(_r(out, 4, 3, 0), 255);
    expect(_r(out, 4, 0, 0), 0);
  });

  test('YUV420: 회색(Y=128, U=V=128)은 회색 RGB', () {
    final y = Uint8List(4 * 2)..fillRange(0, 8, 128);
    final u = Uint8List(2)..fillRange(0, 2, 128);
    final v = Uint8List(2)..fillRange(0, 2, 128);
    final f = RawFrame(width: 4, height: 2, planes: [y, u, v], rowStrides: [4, 2, 2], pixelStrides: [1, 1, 1], bgra: false);
    final out = frameToRgb(f, rotation: 0, mirror: false, outW: 4, outH: 2);
    expect(out.toSet(), {128});
  });

  test('회전 계산: 뒤카메라 센서 90, 세로로 들면 90도', () {
    expect(frameRotation(sensorOrientation: 90, deviceDegrees: 0, front: false), 90);
    expect(frameRotation(sensorOrientation: 90, deviceDegrees: 90, front: false), 0);
    expect(frameRotation(sensorOrientation: 270, deviceDegrees: 0, front: true), 270);
  });

  test('세워 들면: iOS 는 그대로, Android 는 센서 각도만큼 돌리고 앞카메라 반전', () {
    expect(clipTransform(ios: true, sensorOrientation: 90, deviceDegrees: 0, front: false), (0, false));
    expect(clipTransform(ios: true, sensorOrientation: 90, deviceDegrees: 0, front: true), (0, false));
    expect(clipTransform(ios: false, sensorOrientation: 90, deviceDegrees: 0, front: false), (90, false));
    expect(clipTransform(ios: false, sensorOrientation: 270, deviceDegrees: 0, front: true), (270, true));
  });

  test('눕혀 들면 세상이 바로 서도록 더 돌린다 (iOS 앞카메라는 거울이라 반대로)', () {
    expect(uprightTurn(0), 0);
    expect(uprightTurn(90), 270); // 왼쪽으로 눕힘
    expect(uprightTurn(270), 90); // 오른쪽으로 눕힘
    expect(clipTransform(ios: true, sensorOrientation: 90, deviceDegrees: 90, front: false), (270, false));
    expect(clipTransform(ios: true, sensorOrientation: 90, deviceDegrees: 90, front: true), (90, false));
    expect(clipTransform(ios: false, sensorOrientation: 90, deviceDegrees: 90, front: false), (0, false));
  });

  test('뷰파인더는 폰 화면 기준: iOS 그대로, Android 센서 각도', () {
    expect(previewTransform(ios: true, sensorOrientation: 90, front: true), (0, false));
    expect(previewTransform(ios: false, sensorOrientation: 90, front: false), (90, false));
    expect(previewTransform(ios: false, sensorOrientation: 270, front: true), (270, true));
  });

  test('클립 크기: 세로 480x640 · 가로 640x480 · MAX 720x960, 모두 16의 배수', () {
    expect(clipSize(CaptureQuality.x2, portrait: true), (480, 640));
    expect(clipSize(CaptureQuality.x2, portrait: false), (640, 480));
    expect(clipSize(CaptureQuality.max, portrait: true), (720, 960));
    for (final q in CaptureQuality.values) {
      final (w, h) = clipSize(q, portrait: true);
      expect(w % 16 + h % 16, 0);
    }
  });

  test('클립 프레임: 세 모드 모두 같은 크기의 RGBA', () {
    const w = 480, h = 640;
    final rgb = Uint8List(w * h * 3)..fillRange(0, w * h * 3, 120);
    for (final mode in CaptureMode.values) {
      final rgba = clipFrame(mode, rgb, w, h, index: 3, stamp: "'26 10 01");
      expect(rgba.length, w * h * 4, reason: mode.name);
      expect(rgba[3], 255);
    }
  });
}
