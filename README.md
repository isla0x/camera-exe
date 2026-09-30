# camera.exe

찍은 사진이 레트로 PC 화면처럼 한 줄씩 "출력"되는 카메라 앱 (Flutter).

```
C:\> capture --mode=ascii
frame grabbed ...... OK
strip gps/exif ..... OK
printing IMG_0930_213300.BMP
[██████████████░░░░░░░░]
```

## 모드

| 모드 | 느낌 | 처리 |
|---|---|---|
| `WEBCAM` | 2003 노트북 웹캠 | 160x120 로 줄여 큼직한 픽셀, 채도 65%, 따뜻한 색조, 노이즈, 날짜 도장 |
| `CRT` | 브라운관 모니터 | 채도 135%, 가로 번짐, 3줄마다 스캔라인, RGB 격자, 비네팅, 둥근 모서리 |
| `ASCII` | 터미널 글자 그림 | 48 x 22 칸 밝기 → ` .:-=+*#%@` |

- 뷰파인더는 가운데 4:3 을 보여주고, 결과도 같은 부분을 320x240 기준으로 자른다.
- 뷰파인더 색은 느낌만 비슷하게 낸 것이고, 정확한 효과는 촬영 후 처리된다 (`lib/logic/filters.dart`).
- 결과는 픽셀을 새로 그린 PNG 라서 위치정보 같은 EXIF 가 남지 않는다. 서버 없음, 수집하는 데이터 없음.
- 출력 중 화면을 탭하면 바로 끝까지 출력된다.

## 처음 실행

```bash
bash tool/setup_platforms.sh   # ios/ android/ 생성 + 앱 이름·권한 문구
flutter pub get
flutter test                   # 필터 테스트
flutter run                    # 폰 연결 후 (카메라라 시뮬레이터에서는 안 보임)
```

iOS 는 처음 한 번 Xcode 에서 `ios/Runner.xcworkspace` → Runner → Signing & Capabilities → Team 을 고른다.

## 구조

```
lib/
  main.dart
  logic/capture_mode.dart   모드 3종
  logic/filters.dart        이미지 처리 (Isolate 에서 실행)
  screens/camera_screen.dart 촬영 화면
  screens/print_screen.dart  출력 애니메이션 → 결과, 저장·공유
  widgets/result_card.dart   사진 뷰어 창 (저장 이미지도 이걸 그대로 뜬다)
  widgets/retro.dart         스캔라인, 로그 줄, 버튼, 진행 막대
```

## 다음 할 일

- PRO (일회성 구매): 워터마크 제거, 추가 모드, 창 테마, 출력 과정 영상(.MP4) 저장
- 앱 아이콘
