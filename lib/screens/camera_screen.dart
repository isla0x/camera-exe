import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logic/capture_mode.dart';
import '../theme/palette.dart';
import '../widgets/retro.dart';
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
    _controller?.dispose();
    super.dispose();
  }

  /// 앱이 뒤로 가면 카메라를 놓고, 돌아오면 다시 켠다.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (state == AppLifecycleState.inactive) {
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
      final c = CameraController(cam, ResolutionPreset.veryHigh, enableAudio: false);
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
                  _Shutter(onPressed: ready && !_busy ? _shoot : null, busy: _busy),
                  _SquareButton(
                    label: 'Flip camera',
                    onPressed: _cameras.length > 1 && !_busy ? _flip : null,
                    child: const Icon(Icons.cameraswitch_outlined, size: 22, color: Palette.fg),
                  ),
                ],
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
    return AspectRatio(
      aspectRatio: 4 / 3,
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
            Scanlines(opacity: _mode == CaptureMode.webcam ? 0.18 : 0.38),
            Positioned(
              top: 10,
              left: 10,
              child: Row(
                children: [
                  Container(width: 8, height: 8, decoration: const BoxDecoration(color: Palette.rec, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text('REC ${_quality.res}', style: _overlay),
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
  const _Shutter({required this.onPressed, required this.busy});

  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final on = onPressed != null;
    return Semantics(
      button: true,
      label: 'Take photo',
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: 78,
          height: 78,
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: on || busy ? Palette.accent : Palette.border, width: 3),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: busy ? Palette.accent.withValues(alpha: 0.4) : (on ? Palette.accent : Palette.border),
            ),
          ),
        ),
      ),
    );
  }
}
