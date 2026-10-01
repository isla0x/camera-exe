import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../logic/capture_mode.dart';
import '../logic/filters.dart';
import '../logic/print_timeline.dart';
import '../logic/video_writer.dart';
import '../theme/palette.dart';
import '../widgets/print_video_frame.dart';
import '../widgets/result_card.dart';
import '../widgets/retro.dart';

/// 찍고 처리까지 끝난 사진 한 장.
class PrintedPhoto {
  const PrintedPhoto({required this.shot, required this.fileName, required this.takenAt});

  final ProcessedShot shot;
  final String fileName;
  final DateTime takenAt;
}

/// 출력 화면 → 결과 화면. 사진을 처리한 뒤 한 줄씩 "출력"하고, 저장·공유 버튼을 보여준다.
class PrintScreen extends StatefulWidget {
  const PrintScreen({
    super.key,
    required Uint8List this.jpeg,
    required this.mode,
    required this.mirror,
    required this.takenAt,
    this.quality = CaptureQuality.x2,
    this.turn = 0,
  }) : photo = null;

  /// 이미 출력한 사진을 다시 볼 때 (애니메이션 없이 바로 결과).
  PrintScreen.done({super.key, required PrintedPhoto this.photo})
      : jpeg = null,
        mode = photo.shot.mode,
        mirror = false,
        takenAt = photo.takenAt,
        quality = photo.shot.quality,
        turn = 0;

  final Uint8List? jpeg;
  final CaptureMode mode;
  final bool mirror;
  final DateTime takenAt;
  final CaptureQuality quality;

  /// 폰을 눕혀 찍었을 때 사진을 돌릴 각도 (uprightTurn)
  final int turn;
  final PrintedPhoto? photo;

  @override
  State<PrintScreen> createState() => _PrintScreenState();
}

/// 출력 애니메이션 전체 길이. 줄 수(화질 · 모드마다 다름)로 나눠 한 줄씩.
const _printTotalMs = 2520;

class _PrintScreenState extends State<PrintScreen> {
  final _cardKey = GlobalKey();

  PrintedPhoto? _photo;
  int _rows = 0;
  String? _error;
  Timer? _timer;

  bool _saving = false;
  String? _savedMsg;
  bool _savedIsError = false;

  /// .MP4 만드는 중: 화면 밖(덮개 아래)에 영상 장면을 그려 한 장씩 뜬다.
  final _videoKey = GlobalKey();
  PrintFrame? _videoFrame;
  bool _encoding = false;
  double _encProgress = 0;

  String get _fileName {
    final d = widget.takenAt;
    return 'IMG_${two(d.month)}${two(d.day)}_${two(d.hour)}${two(d.minute)}${two(d.second)}.BMP';
  }

  bool get _processed => _photo != null;
  bool get _done => _photo != null && _rows >= _photo!.shot.printRows;

  @override
  void initState() {
    super.initState();
    final ready = widget.photo;
    if (ready != null) {
      _photo = ready;
      _rows = ready.shot.printRows;
    } else {
      _process();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _process() async {
    try {
      final shot = await processShotInBackground(widget.jpeg!, widget.mode, mirror: widget.mirror, quality: widget.quality, turn: widget.turn);
      if (!mounted) return;
      setState(() => _photo = PrintedPhoto(shot: shot, fileName: _fileName, takenAt: widget.takenAt));
      _startPrinting();
    } catch (e) {
      debugPrint('camera.exe: 처리 실패 $e');
      // 긴 오류는 첫 줄만 보여준다.
      final msg = '$e'.split('\n').first;
      if (mounted) setState(() => _error = msg.length > 160 ? '${msg.substring(0, 160)}…' : msg);
    }
  }

  void _startPrinting() {
    final total = _photo!.shot.printRows;
    final rowDelay = Duration(milliseconds: (_printTotalMs / total).round().clamp(20, 200).toInt());
    // 줄이 많으면(ASCII MAX 58줄) 진동을 몇 줄에 한 번만.
    final buzzEvery = (total / 24).ceil();
    _timer = Timer.periodic(rowDelay, (t) {
      if (!mounted) return;
      setState(() => _rows++);
      if (_rows % buzzEvery == 0) HapticFeedback.selectionClick();
      if (_rows >= total) {
        t.cancel();
        HapticFeedback.lightImpact();
      }
    });
  }

  /// 출력 중에 화면을 탭하면 바로 끝까지 출력한다.
  void _skip() {
    if (!_processed || _done) return;
    _timer?.cancel();
    setState(() => _rows = _photo!.shot.printRows);
  }

  /// 화면의 뷰어 창을 그대로 PNG 로 뜬다.
  Future<Uint8List> _renderCard() async {
    final boundary = _cardKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    // 사진 해상도만큼 크게 뜬다 (2X 약 4배, MAX 약 5배).
    final image = await boundary.toImage(pixelRatio: _photo?.shot.exportPixelRatio ?? 3);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  Future<void> _save() async {
    if (!_done || _saving) return;
    setState(() {
      _saving = true;
      _savedMsg = null;
    });
    try {
      if (!await Gal.hasAccess()) {
        final ok = await Gal.requestAccess();
        if (!ok) throw const _UserError('access denied: photos\n설정 > camera.exe 에서 사진 추가를 허용해 주세요.');
      }
      final png = await _renderCard();
      await Gal.putImageBytes(png, name: _photo!.fileName.replaceAll('.BMP', ''));
      _setSaved(r'saved to C:\PICS\' + _photo!.fileName);
      HapticFeedback.mediumImpact();
    } on _UserError catch (e) {
      _setSaved(e.message, error: true);
    } on GalException catch (e) {
      _setSaved('save failed: ${e.type.message}', error: true);
    } catch (e) {
      _setSaved('save failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 출력 과정을 세로 영상(.MP4)으로 만들어 사진 앱에 저장한다.
  Future<void> _saveVideo() async {
    final photo = _photo;
    if (!_done || photo == null || _encoding || _saving) return;
    final timeline = timelineFor(photo.shot);
    setState(() {
      _encoding = true;
      _encProgress = 0;
      _savedMsg = null;
      _videoFrame = timeline.frameAt(0);
    });
    File? file;
    VideoWriter? writer;
    try {
      if (!await Gal.hasAccess()) {
        final ok = await Gal.requestAccess();
        if (!ok) throw const _UserError('access denied: photos\n설정 > camera.exe 에서 사진 추가를 허용해 주세요.');
      }
      final dir = await getTemporaryDirectory();
      final name = videoName(photo.fileName);
      file = File('${dir.path}/${name.replaceAll('.MP4', '.mp4')}');
      if (await file.exists()) await file.delete();

      writer = await VideoWriter.open(file.path, fps: timeline.fps);
      final scale = writer.width / PrintVideoFrame.size.width;
      Uint8List? rgba;
      String? shownKey;
      final count = timeline.frameCount;
      for (var i = 0; i < count; i++) {
        if (!mounted) throw const _UserError('canceled');
        final f = timeline.frameAt(i);
        // 화면이 바뀐 프레임만 새로 그린다. 나머지는 앞 그림을 그대로 쓴다.
        if (f.key != shownKey || rgba == null) {
          setState(() => _videoFrame = f);
          await WidgetsBinding.instance.endOfFrame;
          rgba = await _grabVideoFrame(scale, writer.width, writer.height);
          shownKey = f.key;
        }
        await writer.add(rgba);
        if (i % 6 == 0 && mounted) setState(() => _encProgress = i / count);
      }
      await writer.close();
      writer = null;
      await Gal.putVideo(file.path);
      _setSaved(r'saved to C:\PICS\' + name);
      HapticFeedback.mediumImpact();
    } on _UserError catch (e) {
      _setSaved(e.message, error: true);
    } on GalException catch (e) {
      _setSaved('save failed: ${e.type.message}', error: true);
    } catch (e) {
      _setSaved('.mp4 failed: $e', error: true);
    } finally {
      await writer?.abort();
      if (file != null) {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _encoding = false;
          _videoFrame = null;
        });
      }
    }
  }

  /// 덮개 아래에 그려 둔 영상 장면을 RGBA 로 뜬다.
  Future<Uint8List> _grabVideoFrame(double scale, int width, int height) async {
    final boundary = _videoKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: scale);
    try {
      if (image.width != width || image.height != height) {
        throw StateError('frame ${image.width}x${image.height} != ${width}x$height');
      }
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  Future<void> _share() async {
    if (!_done) return;
    try {
      final png = await _renderCard();
      final dir = await getTemporaryDirectory();
      final name = _photo!.fileName.replaceAll('.BMP', '.png');
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(png, flush: true);
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (e) {
      _setSaved('share failed: $e', error: true);
    }
  }

  void _setSaved(String msg, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _savedMsg = msg;
      _savedIsError = error;
    });
  }

  void _close() {
    if (_encoding) return; // 영상 만드는 중에는 나가지 않는다.
    Navigator.of(context).pop(_photo);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: Palette.bg,
        body: Stack(
          clipBehavior: Clip.none,
          children: [
            // 영상 장면: 만드는 동안만 그리고, 아래 덮개가 가린다.
            if (_videoFrame != null && _photo != null)
              Positioned(
                left: 0,
                top: 0,
                width: PrintVideoFrame.size.width,
                height: PrintVideoFrame.size.height,
                child: IgnorePointer(
                  child: RepaintBoundary(
                    key: _videoKey,
                    child: PrintVideoFrame(
                      shot: _photo!.shot,
                      fileName: _photo!.fileName,
                      takenAt: _photo!.takenAt,
                      frame: _videoFrame!,
                    ),
                  ),
                ),
              ),
            Positioned.fill(child: ColoredBox(color: Palette.bg, child: SafeArea(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _skip,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ..._log(),
                  const SizedBox(height: 16),
                  Expanded(child: Center(child: _body())),
                  const SizedBox(height: 16),
                  _bottom(),
                ],
              ),
            ),
          ),
        ))),
            if (_encoding) Positioned.fill(child: _encodingCover()),
          ],
        ),
      ),
    );
  }

  /// .MP4 만드는 동안 덮는 화면.
  Widget _encodingCover() {
    final name = _photo == null ? '' : videoName(_photo!.fileName);
    return AbsorbPointer(
      child: ColoredBox(
        color: Palette.bg,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const LogLine(r'C:\> encode --format=mp4 --size=1080x1920'),
                LogLine('writing $name', pending: true),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('encoding ...', style: TextStyle(fontFamily: Palette.mono, fontSize: 12, color: Palette.dim)),
                    Text(
                      '${(_encProgress * 100).round()}%',
                      style: const TextStyle(fontFamily: Palette.mono, fontSize: 12, color: Palette.accent),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    progressBar(_encProgress),
                    style: const TextStyle(fontFamily: Palette.mono, fontSize: 20, color: Palette.accent, height: 1.1),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  "don't turn off your computer_",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: Palette.mono, fontSize: 11, color: Palette.dim),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _log() {
    if (widget.photo != null) {
      return [LogLine(r'C:\PICS> open ' + widget.photo!.fileName, ok: true)];
    }
    return [
      LogLine(r'C:\> capture --mode=' + widget.mode.flag),
      const LogLine('frame grabbed ......', ok: true),
      LogLine('strip gps/exif .....', ok: _processed, pending: !_processed && _error == null),
      if (_processed) LogLine('printing $_fileName', ok: _done),
    ];
  }

  Widget _body() {
    if (_error != null) {
      return Text(
        'ERROR: $_error',
        textAlign: TextAlign.center,
        style: const TextStyle(fontFamily: Palette.mono, fontSize: 12, height: 1.5, color: Palette.rec),
      );
    }
    final photo = _photo;
    if (photo == null) {
      return const Text('processing...', style: TextStyle(fontFamily: Palette.mono, fontSize: 12, color: Palette.dim));
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: SizedBox(
        width: 350,
        child: Padding(
          // 창 그림자(6px)까지 이미지에 담기게 여백을 둔다.
          padding: const EdgeInsets.only(right: 6, bottom: 6),
          child: RepaintBoundary(
            key: _cardKey,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 10, 10),
              child: ColoredBox(
                color: Colors.transparent,
                child: ResultCard(
                  shot: photo.shot,
                  revealedRows: _rows,
                  fileName: photo.fileName,
                  takenAt: photo.takenAt,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottom() {
    final photo = _photo;
    if (_error != null) {
      return TermButton(label: 'BACK', onPressed: _close);
    }
    if (photo == null || !_done) {
      final total = photo?.shot.printRows ?? 1;
      final t = photo == null ? 0.0 : _rows / total;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                photo == null ? 'rendering ...' : 'rendering line ${two(_rows)}/${two(total)}',
                style: const TextStyle(fontFamily: Palette.mono, fontSize: 12, color: Palette.dim),
              ),
              Text('${(t * 100).round()}%', style: const TextStyle(fontFamily: Palette.mono, fontSize: 12, color: Palette.accent)),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              progressBar(t),
              style: const TextStyle(fontFamily: Palette.mono, fontSize: 20, color: Palette.accent, height: 1.1),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            "don't turn off your computer_  (tap to skip)",
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: Palette.mono, fontSize: 11, color: Palette.dim),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 36,
          child: Center(
            child: Text(
              _savedMsg ?? '',
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(fontFamily: Palette.mono, fontSize: 11, height: 1.4, color: _savedIsError ? Palette.rec : Palette.accent),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: TermButton(label: _saving ? 'SAVING' : 'SAVE .PNG', onPressed: _saving || _encoding ? null : _save)),
            const SizedBox(width: 8),
            Expanded(child: TermButton(label: 'SAVE .MP4', onPressed: _saving || _encoding ? null : _saveVideo)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: TermButton(label: widget.photo == null ? 'RETAKE' : 'BACK', onPressed: _close)),
            const SizedBox(width: 8),
            Expanded(child: TermButton(label: 'SHARE', filled: true, onPressed: _share)),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          '.MP4 = 출력되는 과정을 세로 영상으로 저장',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: Palette.dim),
        ),
      ],
    );
  }
}

class _UserError implements Exception {
  const _UserError(this.message);

  final String message;
}
