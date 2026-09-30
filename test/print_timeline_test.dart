import 'package:camera_exe/logic/print_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const tl = PrintTimeline(totalRows: 24);

  test('영상은 5초 안팎, 30fps', () {
    expect(tl.fps, 30);
    expect(tl.seconds, greaterThan(4));
    expect(tl.seconds, lessThan(6));
    expect(tl.frameCount, (tl.seconds * 30).ceil());
  });

  test('처음엔 로그 한 줄, 아직 출력 전', () {
    final f = tl.frameAt(0);
    expect(f.logLines, 1);
    expect(f.rows, 0);
    expect(f.saved, isFalse);
  });

  test('줄 수는 줄지 않고, 마지막엔 다 출력되고 saved', () {
    var prev = 0;
    for (var i = 0; i < tl.frameCount; i++) {
      final f = tl.frameAt(i);
      expect(f.rows, greaterThanOrEqualTo(prev));
      expect(f.rows, lessThanOrEqualTo(24));
      expect(f.logLines, inInclusiveRange(1, 3));
      prev = f.rows;
    }
    final last = tl.frameAt(tl.frameCount - 1);
    expect(last.rows, 24);
    expect(last.logLines, 3);
    expect(last.saved, isTrue);
  });

  test('다시 그려야 하는 장면은 프레임 수보다 훨씬 적다', () {
    final keys = {for (var i = 0; i < tl.frameCount; i++) tl.frameAt(i).key};
    expect(keys.length, lessThan(tl.frameCount ~/ 2));
  });

  test('ASCII (22줄) 도 끝까지 출력된다', () {
    const a = PrintTimeline(totalRows: 22);
    expect(a.frameAt(a.frameCount - 1).rows, 22);
  });
}
