import 'package:flutter/foundation.dart';
import 'package:flutter_quick_video_encoder/flutter_quick_video_encoder.dart';

/// 그림(RGBA)을 한 장씩 받아 MP4(H.264)로 만든다. 폰의 하드웨어 인코더를 쓴다.
class VideoWriter {
  VideoWriter._(this.width, this.height);

  final int width;
  final int height;

  /// 1080 x 1920 으로 열어 보고, 폰이 못 하면 720 x 1280 으로.
  static Future<VideoWriter> open(String path, {int fps = 30}) =>
      _openFirst(path, fps, const [(1080, 1920, 14000000), (720, 1280, 8000000)]);

  /// 정해진 크기로 연다 (클립).
  static Future<VideoWriter> openSized(String path, int width, int height, {required int fps, required int bitrate}) =>
      _openFirst(path, fps, [(width, height, bitrate)]);

  static Future<VideoWriter> _openFirst(String path, int fps, List<(int, int, int)> sizes) async {
    Object? last;
    for (final (w, h, bitrate) in sizes) {
      try {
        await FlutterQuickVideoEncoder.setup(
          width: w,
          height: h,
          fps: fps,
          videoBitrate: bitrate,
          profileLevel: ProfileLevel.highAutoLevel,
          audioChannels: 0,
          audioBitrate: 0,
          sampleRate: 44100,
          filepath: path,
        );
        return VideoWriter._(w, h);
      } catch (e) {
        debugPrint('camera.exe: 영상 $w x $h 준비 실패 ($e)');
        last = e;
        try {
          await FlutterQuickVideoEncoder.finish();
        } catch (_) {}
      }
    }
    throw StateError('video encoder: $last');
  }

  /// [rgba] 는 width x height x 4 바이트.
  Future<void> add(Uint8List rgba) => FlutterQuickVideoEncoder.appendVideoFrame(rgba);

  Future<void> close() => FlutterQuickVideoEncoder.finish();

  /// 도중에 멈출 때. 실패해도 조용히 넘어간다.
  Future<void> abort() async {
    try {
      await FlutterQuickVideoEncoder.finish();
    } catch (_) {}
  }
}
