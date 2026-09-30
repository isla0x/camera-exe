import 'package:flutter/material.dart';

import '../logic/capture_mode.dart';
import '../theme/palette.dart';

/// 화면 위에 까는 가로 스캔라인.
class Scanlines extends StatelessWidget {
  const Scanlines({super.key, this.opacity = 0.35, this.gap = 3});

  final double opacity;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _ScanlinePainter(opacity, gap),
        size: Size.infinite,
      ),
    );
  }
}

class _ScanlinePainter extends CustomPainter {
  _ScanlinePainter(this.opacity, this.gap);

  final double opacity;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: opacity);
    for (var y = 0.0; y < size.height; y += gap) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), paint);
    }
  }

  @override
  bool shouldRepaint(_ScanlinePainter old) => old.opacity != opacity || old.gap != gap;
}

/// 뷰파인더 미리보기에 씌우는 색. 결과와 비슷한 느낌만 낸다 (정확한 효과는 촬영 후 처리).
ColorFilter previewFilter(CaptureMode mode) {
  switch (mode) {
    case CaptureMode.webcam:
      return ColorFilter.matrix(_saturation(0.65, contrast: 0.88, offset: [20, 13, 2]));
    case CaptureMode.crt:
      return ColorFilter.matrix(_saturation(1.35, contrast: 1.12, offset: [0, 0, 0]));
    case CaptureMode.ascii:
      // 흑백으로 만든 뒤 초록 형광으로 물들인다.
      const r = 0.2126, g = 0.7152, b = 0.0722;
      return const ColorFilter.matrix(<double>[
        r * 0.45, g * 0.45, b * 0.45, 0, 0, //
        r * 0.95, g * 0.95, b * 0.95, 0, 8, //
        r * 0.5, g * 0.5, b * 0.5, 0, 0, //
        0, 0, 0, 1, 0,
      ]);
  }
}

List<double> _saturation(double s, {required double contrast, required List<double> offset}) {
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  final c = contrast;
  final t = 128 * (1 - c);
  List<double> row(double wr, double wg, double wb, double off) => [wr * c, wg * c, wb * c, 0, t + off];
  return [
    ...row(lr * (1 - s) + s, lg * (1 - s), lb * (1 - s), offset[0]),
    ...row(lr * (1 - s), lg * (1 - s) + s, lb * (1 - s), offset[1]),
    ...row(lr * (1 - s), lg * (1 - s), lb * (1 - s) + s, offset[2]),
    0, 0, 0, 1, 0,
  ];
}

/// `init sensor ........ OK` 같은 로그 한 줄.
class LogLine extends StatelessWidget {
  const LogLine(this.text, {super.key, this.ok = false, this.pending = false, this.color = Palette.dim});

  final String text;
  final bool ok;
  final bool pending;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: text,
        children: [
          if (ok) const TextSpan(text: ' OK', style: TextStyle(color: Palette.accent)),
          if (pending) const TextSpan(text: ' ...', style: TextStyle(color: Palette.dim)),
        ],
      ),
      style: TextStyle(fontFamily: Palette.mono, fontSize: 12, height: 1.5, color: color),
    );
  }
}

/// 터미널 느낌의 네모 버튼. [filled] 면 형광 초록으로 채운다.
class TermButton extends StatelessWidget {
  const TermButton({super.key, required this.label, required this.onPressed, this.filled = false, this.height = 48});

  final String label;
  final VoidCallback? onPressed;
  final bool filled;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return SizedBox(
      height: height,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          backgroundColor: filled ? Palette.accent : Colors.transparent,
          foregroundColor: filled ? Palette.bg : Palette.fg,
          disabledForegroundColor: Palette.dim,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(color: filled ? Palette.accent : (enabled ? Palette.border : Palette.line)),
          ),
          textStyle: TextStyle(
            fontFamily: Palette.mono,
            fontSize: 13,
            fontWeight: filled ? FontWeight.w700 : FontWeight.w400,
            letterSpacing: 0.5,
          ),
        ),
        child: Text(label, maxLines: 1),
      ),
    );
  }
}

/// `[██████░░░░]` 진행 막대.
String progressBar(double t, {int width = 22}) {
  final filled = (t.clamp(0.0, 1.0) * width).round();
  return '[${'█' * filled}${'░' * (width - filled)}]';
}

String two(int n) => n.toString().padLeft(2, '0');
