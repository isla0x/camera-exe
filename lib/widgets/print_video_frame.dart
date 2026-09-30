import 'package:flutter/material.dart';

import '../logic/filters.dart';
import '../logic/print_timeline.dart';
import '../theme/palette.dart';
import 'result_card.dart';
import 'retro.dart';

/// 출력 과정 영상(.MP4)의 한 장면. 세로 9:16 (릴스 · 쇼츠 · 스레드 크기).
///
/// 항상 [size] (360 x 640) 로 그리고, 영상으로 뜰 때 3배(1080 x 1920)로 키운다.
class PrintVideoFrame extends StatelessWidget {
  const PrintVideoFrame({
    super.key,
    required this.shot,
    required this.fileName,
    required this.takenAt,
    required this.frame,
    this.watermark = true,
  });

  static const size = Size(360, 640);

  final ProcessedShot shot;
  final String fileName;
  final DateTime takenAt;
  final PrintFrame frame;

  /// 아래쪽 `C:\> camera.exe` 표시. 나중에 PRO 에서 끌 수 있게 남겨 둔다.
  final bool watermark;

  @override
  Widget build(BuildContext context) {
    final total = shot.printRows;
    final t = total == 0 ? 1.0 : frame.rows / total;
    final printing = frame.rows > 0 || frame.saved;
    const small = TextStyle(fontFamily: Palette.mono, fontSize: 11, color: Palette.dim);

    return SizedBox.fromSize(
      size: size,
      child: ColoredBox(
        color: Palette.bg,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 44, 22, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (frame.logLines >= 1) LogLine(r'C:\> capture --mode=' + shot.mode.flag),
                  if (frame.logLines >= 2) const LogLine('frame grabbed ......', ok: true),
                  if (frame.logLines >= 3) const LogLine('strip gps/exif .....', ok: true),
                  if (printing) LogLine('printing $fileName', ok: frame.saved),
                  const SizedBox(height: 18),
                  ResultCard(shot: shot, revealedRows: frame.rows, fileName: fileName, takenAt: takenAt),
                  const SizedBox(height: 22),
                  if (!frame.saved) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(printing ? 'rendering line ${two(frame.rows)}/${two(total)}' : 'rendering ...', style: small),
                        Text('${(t * 100).round()}%', style: small.copyWith(color: Palette.accent)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        progressBar(t),
                        style: const TextStyle(fontFamily: Palette.mono, fontSize: 20, height: 1.1, color: Palette.accent),
                      ),
                    ),
                  ] else
                    Text.rich(
                      TextSpan(
                        text: r'saved to C:\PICS\' + fileName,
                        children: const [TextSpan(text: ' OK', style: TextStyle(color: Palette.accent))],
                      ),
                      style: small.copyWith(color: Palette.fg),
                    ),
                ],
              ),
            ),
            if (watermark)
              Positioned(
                left: 0,
                right: 0,
                bottom: 30,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      r'C:\> camera.exe',
                      style: TextStyle(fontFamily: Palette.mono, fontSize: 15, fontWeight: FontWeight.w700, color: Palette.fg),
                    ),
                    const SizedBox(width: 3),
                    Container(width: 9, height: 16, color: frame.cursor ? Palette.accent : Colors.transparent),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 영상 파일 이름: IMG_0930_213300.BMP → IMG_0930_213300.MP4
String videoName(String bmpName) => bmpName.replaceAll('.BMP', '.MP4');

/// 모드별로 출력 줄 수가 달라서 영상 길이도 조금씩 다르다 (ASCII 22줄, 나머지 24줄).
PrintTimeline timelineFor(ProcessedShot shot) => PrintTimeline(totalRows: shot.printRows);
