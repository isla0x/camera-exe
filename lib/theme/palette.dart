import 'package:flutter/widgets.dart';

/// camera.exe 색. 목업(검은 배경 + 형광 초록)과 같은 값.
class Palette {
  Palette._();

  static const bg = Color(0xFF0C0D0B);
  static const panel = Color(0xFF1A1D18);
  static const deep = Color(0xFF080907);
  static const line = Color(0xFF2B2F29);
  static const border = Color(0xFF3A3F37);

  /// 기본 글자
  static const fg = Color(0xFFD9E0D6);

  /// 보조 글자 (bg 대비 4.5:1 이상)
  static const dim = Color(0xFF8A9587);

  /// 형광 초록: 셔터, 진행 막대, OK
  static const accent = Color(0xFF8BE38B);

  static const rec = Color(0xFFE5534B);

  /// 결과 창 (옛 OS 느낌의 자체 디자인)
  static const winFace = Color(0xFFC9CCC4);
  static const winTitle = Color(0xFF1F3D7A);
  static const winText = Color(0xFF111111);

  /// WEBCAM 날짜 도장
  static const stamp = Color(0xFFF2A33A);

  static const mono = 'JetBrainsMono';
}
