import 'package:flutter/material.dart';

import '../logic/capture_mode.dart';
import '../logic/filters.dart';
import '../theme/palette.dart';
import 'retro.dart';

/// 옛 OS 느낌의 사진 뷰어 창. 출력 중에는 [revealedRows] 줄까지만 보여준다.
///
/// 저장·공유할 때는 이 위젯을 그대로 이미지로 떠서 쓴다.
class ResultCard extends StatelessWidget {
  const ResultCard({
    super.key,
    required this.shot,
    required this.revealedRows,
    required this.fileName,
    required this.takenAt,
  });

  final ProcessedShot shot;
  final int revealedRows;
  final String fileName;
  final DateTime takenAt;

  bool get done => revealedRows >= shot.printRows;

  @override
  Widget build(BuildContext context) {
    final d = takenAt;
    final stamp = '${two(d.month)}.${two(d.day)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
    return Container(
      decoration: const BoxDecoration(
        color: Palette.winFace,
        border: Border.fromBorderSide(BorderSide(color: Palette.winFace, width: 2)),
        boxShadow: [BoxShadow(color: Colors.black, offset: Offset(6, 6))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 제목 표시줄
          Container(
            height: 28,
            color: Palette.winTitle,
            padding: const EdgeInsets.only(left: 8, right: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$fileName - Picture Viewer',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: Palette.mono,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                const _WinBox('_'),
                const SizedBox(width: 3),
                const _WinBox('x'),
              ],
            ),
          ),
          // 사진 영역
          Container(
            margin: const EdgeInsets.all(4),
            color: Palette.deep,
            padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(aspectRatio: 4 / 3, child: _ShotView(shot: shot, revealedRows: revealedRows, takenAt: takenAt)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(stamp, style: _small(Palette.dim)),
                    Text('camera.exe', style: _small(Palette.dim)),
                  ],
                ),
              ],
            ),
          ),
          // 상태 표시줄
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 1, 8, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${shot.resWidth} x ${shot.resHeight} · ${shot.mode.label}', style: _small(Palette.winText)),
                Text(done ? 'done' : 'printing…', style: _small(Palette.winText)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static TextStyle _small(Color c) => TextStyle(fontFamily: Palette.mono, fontSize: 11, color: c);
}

class _WinBox extends StatelessWidget {
  const _WinBox(this.glyph);

  final String glyph;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 16,
      alignment: Alignment.center,
      color: Palette.winFace,
      child: Text(glyph, style: const TextStyle(fontFamily: Palette.mono, fontSize: 11, height: 1, color: Palette.winText)),
    );
  }
}

class _ShotView extends StatelessWidget {
  const _ShotView({required this.shot, required this.revealedRows, required this.takenAt});

  final ProcessedShot shot;
  final int revealedRows;
  final DateTime takenAt;

  @override
  Widget build(BuildContext context) {
    final lines = shot.asciiLines;
    if (lines != null) return _AsciiView(lines: lines, revealedRows: revealedRows);

    final total = shot.printRows;
    final t = (revealedRows / total).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, box) {
        final shown = box.maxHeight * t;
        return Stack(
          fit: StackFit.expand,
          children: [
            // 사진이 화면보다 커서 줄여 그린다: 부드럽게 줄여야 계단 · 반짝임이 안 생긴다.
            Image.memory(shot.png!, fit: BoxFit.cover, filterQuality: FilterQuality.medium, gaplessPlayback: true),
            // 아직 출력 안 된 아래쪽은 까맣게
            if (t < 1)
              Positioned(
                left: 0,
                right: 0,
                top: shown,
                bottom: 0,
                child: const ColoredBox(color: Palette.deep),
              ),
            // 출력 헤드
            if (t < 1)
              Positioned(
                left: 0,
                right: 0,
                top: shown,
                height: 2,
                child: const ColoredBox(color: Palette.accent),
              ),
            if (t >= 1 && shot.mode == CaptureMode.webcam)
              Positioned(
                right: 8,
                bottom: 6,
                child: Text(
                  _webcamStamp(),
                  style: const TextStyle(
                    fontFamily: Palette.mono,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Palette.stamp,
                    shadows: [Shadow(color: Colors.black54, offset: Offset(1, 1))],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  String _webcamStamp() {
    final d = takenAt;
    return "'${two(d.year % 100)} ${two(d.month)} ${two(d.day)}";
  }
}

class _AsciiView extends StatelessWidget {
  const _AsciiView({required this.lines, required this.revealedRows});

  final List<String> lines;
  final int revealedRows;

  @override
  Widget build(BuildContext context) {
    final width = lines.isEmpty ? 0 : lines.first.length;
    final printing = revealedRows < lines.length;
    final shown = <String>[];
    for (var i = 0; i < lines.length; i++) {
      if (i < revealedRows) {
        shown.add(lines[i]);
      } else if (i == revealedRows && printing) {
        shown.add('█'.padRight(width));
      } else {
        shown.add(' ' * width);
      }
    }
    return FittedBox(
      fit: BoxFit.contain,
      child: Text(
        shown.join('\n'),
        softWrap: false,
        style: const TextStyle(
          fontFamily: Palette.mono,
          fontSize: 14,
          height: 1.2,
          color: Palette.accent,
        ),
      ),
    );
  }
}
