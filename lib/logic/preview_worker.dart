import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'capture_mode.dart';
import 'filters.dart';

/// 뷰파인더 크기 (폰 화면 기준 세로). 저장할 때와 비슷한 크기로 필터를 입혀야 느낌이 같다.
(int, int) previewSize(CaptureQuality q) => q == CaptureQuality.max ? (540, 720) : (480, 640);

/// 뷰파인더 프레임에 필터를 입히는 다른 Isolate. 한 번에 한 장만: 바쁘면 새 프레임은 건너뛴다.
class PreviewWorker {
  PreviewWorker._(this._isolate, this._to, this._from);

  final Isolate _isolate;
  final SendPort _to;
  final ReceivePort _from;
  Completer<Uint8List?>? _job;
  int _seed = 0;

  /// 지금 한 장을 처리하는 중인지
  bool get busy => _job != null;

  static Future<PreviewWorker> spawn() async {
    final inbox = ReceivePort();
    final isolate = await Isolate.spawn(_previewWorker, inbox.sendPort, debugName: 'preview');
    final ready = Completer<SendPort>();
    late PreviewWorker w;
    inbox.listen((msg) {
      if (msg is SendPort) {
        ready.complete(msg);
      } else {
        final job = w._job;
        w._job = null;
        job?.complete(msg is TransferableTypedData ? msg.materialize().asUint8List() : null);
      }
    });
    w = PreviewWorker._(isolate, await ready.future, inbox);
    return w;
  }

  /// RGB 한 장 → 필터를 입힌 RGBA (같은 크기). 바쁘면 null.
  Future<Uint8List?> run(Uint8List rgb, int w, int h, CaptureMode mode, CaptureQuality quality) {
    if (_job != null) return Future.value(null);
    final job = _job = Completer<Uint8List?>();
    _to.send([TransferableTypedData.fromList([rgb]), w, h, mode.index, quality.index, _seed++]);
    return job.future;
  }

  void dispose() {
    _to.send(null);
    _from.close();
    _isolate.kill(priority: Isolate.beforeNextEvent);
    _job?.complete(null);
    _job = null;
  }
}

void _previewWorker(SendPort out) {
  final inbox = ReceivePort();
  out.send(inbox.sendPort);
  inbox.listen((msg) {
    if (msg == null) {
      inbox.close();
      return;
    }
    final m = msg as List;
    try {
      final rgb = (m[0] as TransferableTypedData).materialize().asUint8List();
      final rgba = previewFrame(
        CaptureMode.values[m[3] as int],
        CaptureQuality.values[m[4] as int],
        rgb,
        m[1] as int,
        m[2] as int,
        seed: m[5] as int,
      );
      out.send(TransferableTypedData.fromList([rgba]));
    } catch (e) {
      debugPrint('camera.exe preview: $e');
      out.send('$e');
    }
  });
}
