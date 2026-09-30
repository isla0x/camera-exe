/// 출력 과정 영상(.MP4)의 시간표. 몇 번째 프레임에 무엇이 보이는지 정한다.
///
///   0.00s  C:\> capture ...          로그가 한 줄씩
///   0.70s  한 줄씩 출력 (앱과 같은 속도)
///   끝나면  saved to C:\PICS\... OK  + 깜빡이는 커서, 잠깐 멈춤
library;

/// 영상 한 장면.
class PrintFrame {
  const PrintFrame({required this.logLines, required this.rows, required this.saved, required this.cursor});

  /// 위쪽 로그를 몇 줄 보여줄지 (0~3). 4번째 줄 `printing ...` 은 출력이 시작되면 나온다.
  final int logLines;

  /// 사진을 몇 줄까지 출력했는지.
  final int rows;

  /// 다 출력하고 `saved to ...` 줄이 나왔는지.
  final bool saved;

  /// 커서가 켜져 있는지 (0.5초마다 깜빡).
  final bool cursor;

  /// 이 값이 같으면 화면도 같다 → 다시 그리지 않고 앞 프레임을 그대로 쓴다.
  String get key => '$logLines/$rows/$saved/$cursor';
}

class PrintTimeline {
  const PrintTimeline({required this.totalRows, this.fps = 30});

  /// 사진을 몇 줄로 나눠 출력하는지 (ProcessedShot.printRows).
  final int totalRows;
  final int fps;

  static const _logStep = 0.22; // 로그 한 줄 간격 (초)
  static const _printStart = 0.7; // 출력 시작 (초)
  static const _rowSeconds = 0.105; // 한 줄 출력 (앱과 같다)
  static const _hold = 1.8; // 다 출력한 뒤 멈춰 있는 시간 (초)

  double get _printEnd => _printStart + totalRows * _rowSeconds;

  /// 영상 전체 길이 (초).
  double get seconds => _printEnd + _hold;

  int get frameCount => (seconds * fps).ceil();

  PrintFrame frameAt(int i) {
    final t = i / fps;
    final logLines = (t / _logStep).floor() + 1;
    final rows = t < _printStart ? 0 : ((t - _printStart) / _rowSeconds).floor().clamp(0, totalRows).toInt();
    return PrintFrame(
      logLines: logLines.clamp(1, 3).toInt(),
      rows: rows,
      saved: rows >= totalRows && t >= _printEnd + 0.25,
      cursor: (t * 2).floor().isEven,
    );
  }
}
