import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../logic/capture_mode.dart';
import '../logic/clip_recorder.dart';
import '../theme/palette.dart';
import '../widgets/retro.dart';

/// 찍은 클립을 옛 미디어 플레이어 창에서 반복 재생하고, 저장 · 공유한다.
class ClipScreen extends StatefulWidget {
  const ClipScreen({super.key, required this.path, required this.fileName, required this.mode, required this.seconds});

  /// 임시 폴더의 .mp4 (이 화면을 나가면 지운다)
  final String path;

  /// 보여줄 이름 (CLIP_1001_110500.MP4)
  final String fileName;
  final CaptureMode mode;
  final double seconds;

  @override
  State<ClipScreen> createState() => _ClipScreenState();
}

class _ClipScreenState extends State<ClipScreen> {
  late final VideoPlayerController _video = VideoPlayerController.file(File(widget.path));
  bool _ready = false;
  String? _error;
  bool _saving = false;
  String? _msg;
  bool _msgError = false;

  @override
  void initState() {
    super.initState();
    _video.initialize().then((_) async {
      await _video.setLooping(true);
      await _video.setVolume(0);
      await _video.play();
      if (mounted) setState(() => _ready = true);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = '$e'.split('\n').first);
    });
  }

  @override
  void dispose() {
    _video.dispose();
    // 저장했으면 사진 앱에 복사본이 있다. 임시 파일은 지운다.
    File(widget.path).delete().catchError((_) => File(widget.path));
    super.dispose();
  }

  void _say(String m, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _msg = m;
      _msgError = error;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      if (!await Gal.hasAccess()) {
        if (!await Gal.requestAccess()) {
          _say('access denied: photos\n설정 > camera.exe 에서 사진 추가를 허용해 주세요.', error: true);
          return;
        }
      }
      await Gal.putVideo(widget.path);
      HapticFeedback.mediumImpact();
      _say(r'saved to C:\VIDS\' + widget.fileName);
    } on GalException catch (e) {
      _say('save failed: ${e.type.message}', error: true);
    } catch (e) {
      _say('save failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _share() async {
    try {
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(widget.path, mimeType: 'video/mp4')],
          sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (e) {
      _say('share failed: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final secs = widget.seconds.toStringAsFixed(1);
    return Scaffold(
      backgroundColor: Palette.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LogLine('C:\\> record --mode=${widget.mode.flag} --fps=$clipFps'),
              LogLine('captured $secs s ........', ok: true),
              LogLine('writing ${widget.fileName}', ok: true),
              const SizedBox(height: 16),
              Expanded(child: Center(child: _player())),
              const SizedBox(height: 16),
              SizedBox(
                height: 36,
                child: Center(
                  child: Text(
                    _msg ?? '',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: TextStyle(fontSize: 11, height: 1.4, color: _msgError ? Palette.rec : Palette.accent),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: TermButton(label: 'RETAKE', onPressed: () => Navigator.of(context).pop())),
                  const SizedBox(width: 8),
                  Expanded(child: TermButton(label: _saving ? 'SAVING' : 'SAVE .MP4', onPressed: _saving ? null : _save)),
                  const SizedBox(width: 8),
                  Expanded(child: TermButton(label: 'SHARE', filled: true, onPressed: _share)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 옛 OS 느낌의 미디어 플레이어 창
  Widget _player() {
    final secs = widget.seconds.toStringAsFixed(1);
    final aspect = _ready ? _video.value.aspectRatio : 3 / 4;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: SizedBox(
        width: 340,
        child: Container(
          decoration: const BoxDecoration(
            color: Palette.winFace,
            boxShadow: [BoxShadow(color: Colors.black, offset: Offset(6, 6))],
          ),
          padding: const EdgeInsets.all(2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 28,
                color: Palette.winTitle,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.centerLeft,
                child: Text(
                  '${widget.fileName} - Media Player',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
              Container(
                margin: const EdgeInsets.all(4),
                color: Palette.deep,
                child: AspectRatio(
                  aspectRatio: aspect,
                  child: _error != null
                      ? Center(
                          child: Text('ERROR: $_error',
                              textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Palette.rec)),
                        )
                      : _ready
                          ? VideoPlayer(_video)
                          : const Center(child: Text('loading...', style: TextStyle(fontSize: 11, color: Palette.dim))),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 1, 8, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('$clipFps fps · ${widget.mode.label}', style: const TextStyle(fontSize: 11, color: Palette.winText)),
                    Text('$secs s ↻', style: const TextStyle(fontSize: 11, color: Palette.winText)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
