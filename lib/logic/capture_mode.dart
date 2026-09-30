/// 촬영 모드. 결과 사진이 어떻게 "출력"되는지 정한다.
enum CaptureMode {
  webcam('WEBCAM', '2003 노트북 웹캠'),
  crt('CRT', '브라운관 모니터'),
  ascii('ASCII', '터미널 글자 그림');

  const CaptureMode(this.label, this.subtitle);

  /// 화면에 보이는 이름 (영문 고정: 전 세계 공통 UI).
  final String label;

  /// 한 줄 설명.
  final String subtitle;

  /// 명령줄에 찍히는 이름 (`--mode=webcam`).
  String get flag => name;
}
