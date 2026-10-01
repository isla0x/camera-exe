import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logic/capture_mode.dart';
import '../logic/clip_recorder.dart';
import '../logic/frame_convert.dart';
import '../theme/palette.dart';
import '../widgets/retro.dart';
import 'clip_screen.dart';
import 'print_screen.dart';

/// 촬영 화면: 부팅 로그, 4:3 뷰파인더, 모드 선택, 셔터.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  int _camIndex = 0;
  String? _error;
  bool _busy = false;
  CaptureMode _mode = CaptureMode.webcam;

  /// 화질 (2X / MAX). 앱을 다시 켜도 기억한다.
  CaptureQuality _quality = CaptureQuality.x2;
  static const _qualityKey = 'quality';

  /// 마지막으로 찍은 사진 (왼쪽 아래 버튼으로 다시 본다).
  PrintedPhoto? _last;

  bool _cursorOn = true;
  Timer? _blink;

  // ── 클립 (셔터를 꾹 누르는 동안 녹화) ──
  ClipRecorder? _rec;
  bool _recording = false;
  bool _stopAsked = false;
  DateTime? _recStart;
  DateTime? _lastFrameAt;
  Timer? _recTimer;
  int _recRotation = 0;
  bool _recMirror = false;
  String _recName = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _blink = Timer.periodic(const Duration(milliseconds: 530), (_) {
      if (mounted) setState(() => _cursorOn = !_cursorOn);
    });
    _start();
    _loadQuality();
  }

  Future<void> _loadQuality() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_qualityKey);
      final q = CaptureQuality.values.where((q) => q.name == saved).firstOrNull;
      if (q != null && mounted) setState(() => _quality = q);
    } catch (_) {}
  }

  void _pickQuality(CaptureQuality q) {
    if (q == _quality) return;
    HapticFeedback.selectionClick();
    setState(() => _quality = q);
    SharedPreferences.getInstance().then((p) => p.setString(_qualityKey, q.name)).catchError((_) => false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _blink?.cancel();
    _recTimer?.cancel();
    _rec?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  /// 앱이 뒤로 가면 카메라를 놓고, 돌아오면 다시 켠다.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (state == AppLifecycleState.inactive) {
      if (_recording) _cancelClip();
      if (c == null || !c.value.isInitialized) return;
      _controller = null;
      c.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed) {
      if (_controller == null && _cameras.isNotEmpty) _open(_cameras[_camIndex]);
    }
  }

  Future<void> _start() async {
    try {
      _cameras = await availableCameras();
    } on CameraException catch (e) {
      setState(() => _error = e.description ?? e.code);
      return;
    }
    if (_cameras.isEmpty) {
      setState(() => _error = 'no camera found');
      return;
    }
    final back = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
    _camIndex = back < 0 ? 0 : back;
    await _open(_cameras[_camIndex]);
  }

  /// 카메라를 켜는 중인지. 처음 실행 때 권한 창이 떴다 닫히면 앱이 inactive → resumed 가 되는데,
  /// 그때 켜는 중인 카메라를 하나 더 켜지 않게 막는다 (두 개가 겹치면 화면이 까맣게 된다).
  bool _opening = false;

  Future<void> _open(CameraDescription cam) async {
    if (_opening) return;
    _opening = true;
    try {
      final old = _controller;
      _controller = null;
      if (mounted) setState(() => _error = null);
      await old?.dispose();

      // veryHigh = 1920x1080. 가운데 4:3 을 자르면 1440x1080 (MAX 화질).
      // 클립용 미리보기 프레임: iOS 는 BGRA, Android 는 YUV420
      final c = CameraController(
        cam,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.yuv420,
      );
      try {
        await c.initialize();
      } on CameraException catch (e) {
        await c.dispose();
        if (!mounted) return;
        setState(() {
          _error = switch (e.code) {
            'CameraAccessDenied' || 'CameraAccessDeniedWithoutPrompt' || 'CameraAccessRestricted' =>
              'access denied: camera\n설정 > camera.exe 에서 카메라를 허용해 주세요.',
            _ => e.description ?? e.code,
          };
        });
        return;
      }
      // 켜는 사이 앱이 닫혔거나(화면 없음) 뒤로 갔으면 바로 놓는다. 돌아오면 resumed 에서 다시 켠다.
      final life = WidgetsBinding.instance.lifecycleState;
      if (!mounted || (life != null && life != AppLifecycleState.resumed && life != AppLifecycleState.inactive)) {
        await c.dispose();
        return;
      }
      setState(() => _controller = c);
    } finally {
      _opening = false;
    }
  }

  Future<void> _flip() async {
    if (_cameras.length < 2 || _busy) return;
    HapticFeedback.selectionClick();
    _camIndex = (_camIndex + 1) % _cameras.length;
    await _open(_cameras[_camIndex]);
  }

  Future<void> _shoot() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _busy || c.value.isTakingPicture) return;
    HapticFeedback.mediumImpact();
    setState(() => _busy = true);
    try {
      final file = await c.takePicture();
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      final mirror = c.description.lensDirection == CameraLensDirection.front;
      final result = await Navigator.of(context).push<PrintedPhoto>(
        MaterialPageRoute(
          builder: (_) => PrintScreen(jpeg: bytes, mode: _mode, mirror: mirror, takenAt: DateTime.now(), quality: _quality),
        ),
      );
      if (result != null && mounted) setState(() => _last = result);
    } on CameraException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('capture failed: ${e.description ?? e.code}')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openLast() {
    final last = _last;
    if (last == null) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PrintScreen.done(photo: last)));
  }

  // ─────────────── 클립 ───────────────

  static int _deviceDegrees(DeviceOrientation o) => switch (o) {
        DeviceOrientation.portraitUp => 0,
        DeviceOrientation.landscapeLeft => 90,
        DeviceOrientation.portraitDown => 180,
        DeviceOrientation.landscapeRight => 270,
      };

  Future<void> _startClip() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _busy || _recording || c.value.isStreamingImages) return;
    HapticFeedback.heavyImpact();
    _stopAsked = false;
    setState(() {
      _busy = true;
      _recording = true;
      _recStart = DateTime.now();
    });
    try {
      final o = c.value.deviceOrientation;
      final portrait = o == DeviceOrientation.portraitUp || o == DeviceOrientation.portraitDown;
      final front = c.description.lensDirection == CameraLensDirection.front;
      _recRotation = frameRotation(sensorOrientation: c.description.sensorOrientation, deviceDegrees: _deviceDegrees(o), front: front);
      _recMirror = front;
      final (w, h) = clipSize(_quality, portrait: portrait);
      final now = DateTime.now();
      _recName = 'CLIP_${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}.MP4';
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/${_recName.replaceAll('.MP4', '.mp4')}';
      final f = File(path);
      if (await f.exists()) await f.delete();
      _rec = await ClipRecorder.start(
        path: path,
        mode: _mode,
        width: w,
        height: h,
        bitrate: clipBitrate(_quality),
        stamp: "'${two(now.year % 100)} ${two(now.month)} ${two(now.day)}",
      );
      _lastFrameAt = null;
      await c.startImageStream(_onFrame);
      _recTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted) return;
        setState(() {});
        final start = _recStart;
        if (start != null && DateTime.now().difference(start).inMilliseconds >= clipMaxSeconds * 1000) _stopClip();
      });
      // 시작하는 사이 손을 뗐으면 바로 멈춘다
      if (_stopAsked) await _stopClip();
    } catch (e) {
      debugPrint('camera.exe: 클립 시작 실패 $e');
      await _cancelClip(message: 'record failed: $e');
    }
  }

  void _onFrame(CameraImage im) {
    final rec = _rec;
    if (rec == null || !_recording) return;
    final now = DateTime.now();
    final last = _lastFrameAt;
    // 12fps: 약 83ms 마다 한 장
    if (last != null && now.difference(last).inMicroseconds < 1000000 ~/ clipFps - 4000) return;
    _lastFrameAt = last == null ? now : last.add(Duration(microseconds: 1000000 ~/ clipFps));
    if (now.difference(_lastFrameAt!).inMilliseconds > 200) _lastFrameAt = now; // 많이 밀렸으면 다시 맞춘다
    final raw = RawFrame(
      width: im.width,
      height: im.height,
      planes: [for (final p in im.planes) p.bytes],
      rowStrides: [for (final p in im.planes) p.bytesPerRow],
      pixelStrides: [for (final p in im.planes) p.bytesPerPixel ?? 1],
      bgra: im.format.group == ImageFormatGroup.bgra8888,
    );
    rec.add(frameToRgb(raw, rotation: _recRotation, mirror: _recMirror, outW: rec.width, outH: rec.height));
  }

  Future<void> _stopClip() async {
    if (!_recording) return;
    final rec = _rec;
    if (rec == null) {
      _stopAsked = true; // 아직 시작하는 중
      return;
    }
    _recording = false;
    _rec = null;
    _recTimer?.cancel();
    final c = _controller;
    try {
      if (c != null && c.value.isStreamingImages) await c.stopImageStream();
    } catch (_) {}
    final secs = rec.frames / clipFps;
    try {
      final frames = await rec.finish();
      if (frames < clipFps ~/ 2) {
        // 0.5초도 안 되면 실수로 누른 것: 버린다
        File(rec.path).delete().catchError((_) => File(rec.path));
        _toast('too short: 셔터를 꾹 누르고 있는 동안 녹화돼요');
      } else if (mounted) {
        HapticFeedback.mediumImpact();
        setState(() => _busy = false);
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ClipScreen(path: rec.path, fileName: _recName, mode: _mode, seconds: frames / clipFps),
        ));
      }
    } catch (e) {
      debugPrint('camera.exe: 클립 저장 실패 $e (${secs.toStringAsFixed(1)}s)');
      _toast('record failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelClip({String? message}) async {
    final rec = _rec;
    _rec = null;
    _recording = false;
    _recTimer?.cancel();
    try {
      final c = _controller;
      if (c != null && c.value.isStreamingImages) await c.stopImageStream();
    } catch (_) {}
    if (rec != null) {
      await rec.cancel();
      File(rec.path).delete().catchError((_) => File(rec.path));
    }
    if (mounted) setState(() => _busy = false);
    if (message != null) _toast(message);
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m.split('\n').first)));
  }

  String get _recClock {
    final start = _recStart;
    final ms = start == null ? 0 : DateTime.now().difference(start).inMilliseconds;
    final s = (ms / 1000).clamp(0, clipMaxSeconds).floor();
    return '00:${two(s)} / 00:${two(clipMaxSeconds)}';
  }

  void _pick(CaptureMode m) {
    if (m == _mode) return;
    HapticFeedback.selectionClick();
    setState(() => _mode = m);
  }

  @override
  Widget build(BuildContext context) {
    final ready = _controller?.value.isInitialized ?? false;
    return Scaffold(
      backgroundColor: Palette.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const LogLine(r'C:\> camera.exe'),
              LogLine('init sensor ........', ok: ready, pending: !ready && _error == null),
              LogLine('load mode ${_mode.label.padRight(6)} ...', ok: true),
              const SizedBox(height: 16),
              Expanded(child: Center(child: _viewfinder())),
              const SizedBox(height: 16),
              Row(
                children: [
                  for (final m in CaptureMode.values) ...[
                    if (m != CaptureMode.values.first) const SizedBox(width: 8),
                    Expanded(
                      child: TermButton(
                        label: m.label,
                        filled: m == _mode,
                        height: 44,
                        onPressed: () => _pick(m),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const SizedBox(
                    width: 44,
                    child: Text('RES', style: TextStyle(fontFamily: Palette.mono, fontSize: 11, color: Palette.dim)),
                  ),
                  for (final q in CaptureQuality.values) ...[
                    if (q != CaptureQuality.values.first) const SizedBox(width: 8),
                    Expanded(
                      child: TermButton(
                        label: '${q.label} · ${q.res}',
                        filled: q == _quality,
                        height: 34,
                        onPressed: () => _pickQuality(q),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _SquareButton(
                    label: 'Last photo',
                    onPressed: _last == null ? null : _openLast,
                    child: const Text(r'C:\PICS', style: TextStyle(fontFamily: Palette.mono, fontSize: 10, color: Palette.dim)),
                  ),
                  _Shutter(
                    onPressed: ready && !_busy ? _shoot : null,
                    onHoldStart: ready && !_busy ? _startClip : null,
                    onHoldEnd: _stopClip,
                    busy: _busy && !_recording,
                    recording: _recording,
                  ),
                  _SquareButton(
                    label: 'Flip camera',
                    onPressed: _cameras.length > 1 && !_busy ? _flip : null,
                    child: const Icon(Icons.cameraswitch_outlined, size: 22, color: Palette.fg),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '탭 = 사진  ·  꾹 누르고 있기 = 클립 (최대 10초)',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Palette.dim),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _viewfinder() {
    final c = _controller;
    final now = DateTime.now();
    // 세로 3:4. 폰을 눕혀 찍으면 사람이 보기엔 그대로 가로 4:3 이 되고, 사진도 가로로 나온다.
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: Container(
        decoration: BoxDecoration(
          color: Palette.panel,
          border: Border.all(color: Palette.line),
          borderRadius: BorderRadius.circular(6),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (c != null && c.value.isInitialized)
              ColorFiltered(colorFilter: previewFilter(_mode), child: _CoverPreview(controller: c))
            else
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _error ?? '[ LOADING CAMERA ]',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: Palette.mono, fontSize: 12, height: 1.5, color: _error == null ? Palette.dim : Palette.rec),
                  ),
                ),
              ),
            if (_mode == CaptureMode.webcam) const Scanlines(opacity: 0.18),
            Positioned(
              top: 10,
              left: 10,
              child: Row(
                children: [
                  Opacity(
                    opacity: _recording && !_cursorOn ? 0.15 : 1,
                    child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: Palette.rec, shape: BoxShape.circle)),
                  ),
                  const SizedBox(width: 6),
                  Text(_recording ? 'REC $_recClock' : 'REC ${_quality.res}', style: _overlay),
                ],
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: Text('${two(now.month)}/${two(now.day)}/${now.year}', style: _overlay),
            ),
            Positioned(
              bottom: 8,
              left: 10,
              child: Text(
                '${_mode.label}${_cursorOn ? '_' : ' '}',
                style: const TextStyle(fontFamily: Palette.mono, fontSize: 18, fontWeight: FontWeight.w700, color: Palette.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _overlay = TextStyle(
    fontFamily: Palette.mono,
    fontSize: 11,
    color: Palette.fg,
    shadows: [Shadow(color: Colors.black, blurRadius: 3)],
  );
}

/// 미리보기를 4:3 칸에 꽉 채워 가운데를 보여준다 (결과도 가운데 4:3 을 자른다).
class _CoverPreview extends StatelessWidget {
  const _CoverPreview({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final size = controller.value.previewSize;
    if (size == null) return CameraPreview(controller);
    // previewSize 는 가로 기준이라, 세로 화면에서는 뒤집어서 쓴다.
    final portraitW = size.shortestSide;
    final portraitH = size.longestSide;
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(width: portraitW, height: portraitH, child: CameraPreview(controller)),
      ),
    );
  }
}

class _SquareButton extends StatelessWidget {
  const _SquareButton({required this.label, required this.onPressed, required this.child});

  final String label;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Palette.panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: const BorderSide(color: Palette.border)),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 56,
            height: 56,
            child: Opacity(opacity: onPressed == null ? 0.4 : 1, child: Center(child: child)),
          ),
        ),
      ),
    );
  }
}

class _Shutter extends StatelessWidget {
  const _Shutter({
    required this.onPressed,
    required this.onHoldStart,
    required this.onHoldEnd,
    required this.busy,
    required this.recording,
  });

  final VoidCallback? onPressed;
  final VoidCallback? onHoldStart;
  final VoidCallback onHoldEnd;
  final bool busy;
  final bool recording;

  @override
  Widget build(BuildContext context) {
    final on = onPressed != null || recording;
    final ring = recording ? Palette.rec : (on || busy ? Palette.accent : Palette.border);
    return Semantics(
      button: true,
      label: recording ? 'Recording clip' : 'Take photo, hold to record a clip',
      child: GestureDetector(
        onTap: onPressed,
        onLongPressStart: onHoldStart == null ? null : (_) => onHoldStart!(),
        onLongPressEnd: (_) => onHoldEnd(),
        onLongPressCancel: onHoldEnd,
        child: Container(
          width: 78,
          height: 78,
          padding: EdgeInsets.all(recording ? 18 : 7),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: ring, width: 3),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              // 녹화 중에는 빨간 네모 (정지 버튼처럼)
              shape: recording ? BoxShape.rectangle : BoxShape.circle,
              borderRadius: recording ? BorderRadius.circular(4) : null,
              color: recording
                  ? Palette.rec
                  : (busy ? Palette.accent.withValues(alpha: 0.4) : (on ? Palette.accent : Palette.border)),
            ),
          ),
        ),
      ),
    );
  }
}
