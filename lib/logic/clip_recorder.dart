import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'capture_mode.dart';
import 'filters.dart';
import 'video_writer.dart';

/// 클립 설정: 옛 웹캠처럼 살짝 끊기는 12fps, 최대 10초.
const clipFps = 12;
const clipMaxSeconds = 10;

/// 클립 크기 (세로 기준). 눕혀 찍으면 가로세로를 바꾼다. 둘 다 16의 배수라 인코더가 좋아한다.
(int, int) clipSize(CaptureQuality q, {required bool portrait}) {
  final (w, h) = q == CaptureQuality.max ? (720, 960) : (480, 640);
  return portrait ? (w, h) : (h, w);
}

int clipBitrate(CaptureQuality q) => q == CaptureQuality.max ? 6000000 : 3000000;

/// 클립 한 프레임에 필터를 입히고, 날짜 도장 · 워터마크를 찍어 RGBA 로 돌려준다.
/// [index] 로 노이즈 · 필름 입자가 프레임마다 움직인다.
Uint8List clipFrame(CaptureMode mode, Uint8List rgb, int w, int h, {int index = 0, String? stamp, bool watermark = true}) {
  final base = img.Image.fromBytes(width: w, height: h, bytes: rgb.buffer, numChannels: 3);
  final out = switch (mode) {
    // 옛 웹캠 영상: 4분의 1로 줄였다 키운 큼직한 픽셀
    CaptureMode.webcam => webcamFilter(
        base,
        spec: QualitySpec(baseWidth: w, baseHeight: h, webcamLowWidth: w ~/ 4, webcamScale: 4),
        seed: index,
      ),
    CaptureMode.butter => butterFilter(base),
    CaptureMode.trip => tripFilter(base, seed: index),
  };
  final font = w >= 700 ? img.arial24 : img.arial14;
  final pad = w >= 700 ? 20 : 12;
  if (stamp != null && mode != CaptureMode.butter) {
    // 오른쪽 아래 주황 날짜 도장 (사진과 같은 모양)
    final tw = _textWidth(font, stamp);
    img.drawString(out, stamp, font: font, x: w - tw - pad, y: h - font.lineHeight - pad, color: img.ColorRgb8(242, 163, 58));
  }
  if (watermark) {
    img.drawString(out, 'camera.exe', font: font, x: pad, y: h - font.lineHeight - pad, color: img.ColorRgb8(235, 235, 230));
  }
  final rgba = out.numChannels == 4 ? out : out.convert(numChannels: 4, alpha: 255);
  return rgba.getBytes(order: img.ChannelOrder.rgba);
}

int _textWidth(img.BitmapFont font, String s) {
  var w = 0;
  for (final c in s.codeUnits) {
    w += font.characters[c]?.xAdvance ?? (font.size ~/ 2);
  }
  return w;
}

/// 프레임을 받아 다른 Isolate 에서 필터를 입히고, 순서대로 MP4 에 붙인다.
/// 필터가 밀리면 새 프레임 대신 앞 장면을 한 번 더 붙여서 영상 길이(시간)는 맞춘다.
class ClipRecorder {
  ClipRecorder._(this.path, this.width, this.height, this._writer, this._isolate, this._toWorker, this._fromWorker,
      this._mode, this._stamp);

  final String path;
  final int width;
  final int height;
  final VideoWriter _writer;
  final Isolate _isolate;
  final SendPort _toWorker;
  final ReceivePort _fromWorker;
  final CaptureMode _mode;
  final String? _stamp;

  final _waiting = <int, Completer<Uint8List>>{};
  Future<void> _tail = Future.value();
  Uint8List? _last;
  int _seq = 0;
  int _pending = 0;
  int _frames = 0;
  Object? _error;
  bool _closed = false;

  /// 지금까지 붙인 프레임 수 (= 영상 길이 x fps)
  int get frames => _frames;

  static Future<ClipRecorder> start({
    required String path,
    required CaptureMode mode,
    required int width,
    required int height,
    required int bitrate,
    String? stamp,
  }) async {
    final writer = await VideoWriter.openSized(path, width, height, fps: clipFps, bitrate: bitrate);
    final inbox = ReceivePort();
    final isolate = await Isolate.spawn(_clipWorker, inbox.sendPort, debugName: 'clip');
    final ready = Completer<SendPort>();
    late ClipRecorder rec;
    inbox.listen((msg) {
      if (msg is SendPort) {
        ready.complete(msg);
      } else if (msg is List) {
        final c = rec._waiting.remove(msg[0] as int);
        if (msg[1] is TransferableTypedData) {
          c?.complete((msg[1] as TransferableTypedData).materialize().asUint8List());
        } else {
          c?.completeError(StateError('${msg[1]}'));
        }
      }
    });
    rec = ClipRecorder._(path, width, height, writer, isolate, await ready.future, inbox, mode, stamp);
    return rec;
  }

  /// 카메라에서 바로 바꾼 RGB 한 장 (width x height x 3). 기다리지 않고 바로 돌아온다.
  void add(Uint8List rgb) {
    if (_closed || _error != null) return;
    if (_pending > 6) {
      // 밀렸다: 이번 장면은 건너뛰고 앞 장면을 한 번 더 (시간은 그대로 흐르게)
      _chain(() async {
        final last = _last;
        if (last != null) {
          await _writer.add(last);
          _frames++;
        }
      });
      return;
    }
    final seq = _seq++;
    final c = Completer<Uint8List>();
    _waiting[seq] = c;
    _pending++;
    _toWorker.send([seq, TransferableTypedData.fromList([rgb]), width, height, _mode.index, seq, _stamp]);
    _chain(() async {
      try {
        final rgba = await c.future;
        await _writer.add(rgba);
        _last = rgba;
        _frames++;
      } finally {
        _pending--;
      }
    });
  }

  /// 순서대로 실행. 실패해도 줄은 끊기지 않고, 첫 오류만 기억한다.
  void _chain(Future<void> Function() step) {
    _tail = _tail.then((_) async {
      if (_error != null) return;
      try {
        await step();
      } catch (e) {
        _error ??= e;
      }
    });
  }

  /// 남은 프레임을 다 붙이고 파일을 닫는다. 붙인 프레임 수를 돌려준다.
  Future<int> finish() async {
    _closed = true;
    await _tail;
    _stop();
    if (_error != null) {
      await _writer.abort();
      throw StateError('clip: $_error');
    }
    await _writer.close();
    return _frames;
  }

  /// 버린다 (파일은 부른 쪽에서 지운다).
  Future<void> cancel() async {
    _closed = true;
    _stop();
    for (final c in _waiting.values) {
      if (!c.isCompleted) c.completeError(StateError('canceled'));
    }
    _waiting.clear();
    await _tail;
    await _writer.abort();
  }

  void _stop() {
    _toWorker.send(null);
    _fromWorker.close();
    _isolate.kill(priority: Isolate.beforeNextEvent);
  }
}

/// 다른 Isolate: [seq, rgb, w, h, modeIndex, frameIndex, stamp] → [seq, rgba]
void _clipWorker(SendPort out) {
  final inbox = ReceivePort();
  out.send(inbox.sendPort);
  inbox.listen((msg) {
    if (msg == null) {
      inbox.close();
      return;
    }
    final m = msg as List;
    final seq = m[0] as int;
    try {
      final rgb = (m[1] as TransferableTypedData).materialize().asUint8List();
      final rgba = clipFrame(
        CaptureMode.values[m[4] as int],
        rgb,
        m[2] as int,
        m[3] as int,
        index: m[5] as int,
        stamp: m[6] as String?,
      );
      out.send([seq, TransferableTypedData.fromList([rgba])]);
    } catch (e) {
      debugPrint('camera.exe clip: $e');
      out.send([seq, '$e']);
    }
  });
}
