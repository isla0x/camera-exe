import 'dart:typed_data';

/// 카메라 미리보기 프레임 한 장 (camera 플러그인의 CameraImage 를 테스트하기 쉽게 옮긴 것).
class RawFrame {
  const RawFrame({
    required this.width,
    required this.height,
    required this.planes,
    required this.rowStrides,
    required this.pixelStrides,
    required this.bgra,
  });

  /// 센서 방향 그대로의 크기 (보통 가로로 길다)
  final int width;
  final int height;

  /// bgra: [BGRA] 한 장. yuv420: [Y, U, V]. nv21: [Y + VU 섞인 것] 한 장.
  final List<Uint8List> planes;
  final List<int> rowStrides;
  final List<int> pixelStrides;
  final bool bgra;
}

/// 폰 방향과 센서 방향으로 프레임을 몇 도(시계 방향) 돌려야 바로 서는지.
///   deviceDegrees: 세로 0 · 왼쪽으로 눕힘 90 · 거꾸로 180 · 오른쪽으로 눕힘 270
int frameRotation({required int sensorOrientation, required int deviceDegrees, required bool front}) {
  return front ? (sensorOrientation + deviceDegrees) % 360 : (sensorOrientation - deviceDegrees + 360) % 360;
}

int _c(double v) => v < 0 ? 0 : (v > 255 ? 255 : v.round());

/// 프레임을 [rotation] 만큼 돌리고(앞카메라면 좌우 반전), 가운데를 [outW] x [outH] 비율로 잘라
/// 그 크기의 RGB 로 만든다. 필요한 픽셀만 골라 읽어서 빠르다 (가장 가까운 픽셀).
Uint8List frameToRgb(RawFrame f, {required int rotation, required bool mirror, required int outW, required int outH}) {
  final sw = f.width, sh = f.height;
  final turned = rotation == 90 || rotation == 270;
  final rw = turned ? sh : sw, rh = turned ? sw : sh;
  // 돌린 그림에서 가운데를 out 비율로 자른다
  final aspect = outW / outH;
  var cw = rw.toDouble(), ch = rw / aspect;
  if (ch > rh) {
    ch = rh.toDouble();
    cw = rh * aspect;
  }
  final x0 = (rw - cw) / 2, y0 = (rh - ch) / 2;
  final sx = cw / outW, sy = ch / outH;

  final out = Uint8List(outW * outH * 3);
  final p0 = f.planes[0];
  final row0 = f.rowStrides[0];
  final yuv = !f.bgra && f.planes.length >= 3;
  final nv21 = !f.bgra && f.planes.length == 1;
  final pU = yuv ? f.planes[1] : p0, pV = yuv ? f.planes[2] : p0;
  final rowU = yuv ? f.rowStrides[1] : row0;
  final pixU = yuv ? f.pixelStrides[1] : 2;
  final nvBase = sw * sh; // NV21: Y 다음에 VU 가 섞여 있다

  var o = 0;
  for (var oy = 0; oy < outH; oy++) {
    final ry0 = (y0 + (oy + 0.5) * sy).floor();
    for (var ox = 0; ox < outW; ox++) {
      var rx = (x0 + (ox + 0.5) * sx).floor();
      if (mirror) rx = rw - 1 - rx;
      final ry = ry0;
      // 돌린 그림의 (rx, ry) → 원래 프레임의 (fx, fy)
      int fx, fy;
      switch (rotation) {
        case 90:
          fx = ry;
          fy = sh - 1 - rx;
        case 180:
          fx = sw - 1 - rx;
          fy = sh - 1 - ry;
        case 270:
          fx = sw - 1 - ry;
          fy = rx;
        default:
          fx = rx;
          fy = ry;
      }
      if (fx < 0) fx = 0;
      if (fy < 0) fy = 0;
      if (fx >= sw) fx = sw - 1;
      if (fy >= sh) fy = sh - 1;

      int r, g, b;
      if (f.bgra) {
        final i = fy * row0 + fx * 4;
        b = p0[i];
        g = p0[i + 1];
        r = p0[i + 2];
      } else {
        final yv = p0[fy * row0 + fx].toDouble();
        double u, v;
        if (nv21) {
          final i = nvBase + (fy >> 1) * sw + (fx >> 1) * 2;
          v = p0[i] - 128.0;
          u = p0[i + 1] - 128.0;
        } else {
          final i = (fy >> 1) * rowU + (fx >> 1) * pixU;
          u = pU[i] - 128.0;
          v = pV[i] - 128.0;
        }
        r = _c(yv + 1.402 * v);
        g = _c(yv - 0.344136 * u - 0.714136 * v);
        b = _c(yv + 1.772 * u);
      }
      out[o++] = r;
      out[o++] = g;
      out[o++] = b;
    }
  }
  return out;
}
