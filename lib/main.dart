import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/camera_screen.dart';
import 'theme/palette.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const CameraExeApp());
}

class CameraExeApp extends StatelessWidget {
  const CameraExeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'camera.exe',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Palette.bg,
        fontFamily: Palette.mono,
        // 영문은 JetBrains Mono, 한글은 나눔고딕코딩으로 그린다.
        fontFamilyFallback: const ['NanumGothicCoding'],
        colorScheme: const ColorScheme.dark(
          primary: Palette.accent,
          surface: Palette.bg,
          onSurface: Palette.fg,
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Palette.panel,
          contentTextStyle: TextStyle(fontFamily: Palette.mono, color: Palette.fg, fontSize: 12),
        ),
      ),
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Palette.bg,
        ),
        child: child ?? const SizedBox.shrink(),
      ),
      home: const CameraScreen(),
    );
  }
}
