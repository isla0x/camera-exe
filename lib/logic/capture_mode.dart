/// 촬영 모드. 결과 사진이 어떻게 "출력"되는지 정한다.
enum CaptureMode {
  webcam('WEBCAM', '2003 노트북 웹캠'),
  soft('SOFT35', '파스텔 필름 똑딱이'),
  dispo('DISPO', '일회용 필름카메라');

  const CaptureMode(this.label, this.subtitle);

  /// 화면에 보이는 이름 (영문 고정: 전 세계 공통 UI).
  final String label;

  /// 한 줄 설명.
  final String subtitle;

  /// 명령줄에 찍히는 이름 (`--mode=webcam`).
  String get flag => name;
}

/// 화질. 촬영 화면의 `2X` / `MAX` 스위치로 고르고, 사진과 .MP4 영상에 똑같이 쓴다.
enum CaptureQuality {
  /// 레트로 느낌을 살린 채 옛 웹캠(320x240)의 2배.
  x2('2X', '640x480'),

  /// 카메라가 주는 만큼 선명하게 (최대 1440x1080). 효과만 씌운다.
  max('MAX', 'HD');

  const CaptureQuality(this.label, this.res);

  /// 버튼 이름
  final String label;

  /// 뷰파인더 `REC ...` 에 붙는 글자
  final String res;
}
