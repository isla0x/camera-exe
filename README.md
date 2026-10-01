# camera.exe

찍은 사진이 레트로 PC 화면처럼 한 줄씩 "출력"되는 카메라 앱 (Flutter).

```
C:\> capture --mode=trip
frame grabbed ...... OK
strip gps/exif ..... OK
printing IMG_0930_213300.BMP
[██████████████░░░░░░░░]
```

## 모드

| 모드 | 느낌 | 처리 |
|---|---|---|
| `WEBCAM` | 2003 노트북 웹캠 | 줄였다 키워 큼직한 픽셀, 채도 65%, 따뜻한 색조, 노이즈, 날짜 도장 |
| `BUTTER` | 뽀샤시 버터 | 많이 공유되는 버터 필터 레시피: 대비 -8 · 어두운 영역 +70 · 검정 계열 +80 · 색온도 +4 · 색조 +10 · 디헤이즈 -12 · 그레인 +20, 살짝 부드럽게, 노출 +, 밝은 곳 노란빛 |
| `TRIP` | 여행을 추억하는 필름 | 채도 82%, 부드러운 S 곡선, 어두운 곳 청록 · 밝은 곳 금빛, 바랜 검정, 오른쪽 위 주황 빛 샘, 비네팅, 필름 입자, 날짜 도장 |

- 화질은 촬영 화면의 `RES` 스위치로 고른다 (앱을 다시 켜도 기억). 사진과 .MP4 영상 둘 다에 쓴다.

  | 화질 | 기준 | WEBCAM | BUTTER · TRIP |
  |---|---|---|---|
  | `2X` | 640x480 (세로 480x640) | 절반 픽셀을 4배로 (1280x960) | 640x480 |
  | `MAX` | 최대 1440x1080 (세로 1080x1440) | 픽셀화 없이 색 · 노이즈만 | 1440x1080 |

- 사진 방향은 폰 방향을 따른다: 세워 찍으면 세로 3:4, 눕혀 찍으면 가로 4:3. 뷰파인더는 세로 3:4 (폰을 눕히면 그대로 가로 4:3 으로 보인다). 카메라는 1920x1080 으로 찍는다.
- 저장 · 공유 이미지는 사진 해상도에 맞춰 크게 뜬다 (`ProcessedShot.exportPixelRatio`).
- 뷰파인더에도 저장할 때와 **같은 필터 코드**를 실시간으로 입힌다 (카메라 미리보기 프레임 → `PreviewWorker` 다른 Isolate → `previewFrame`). 보이는 그대로 찍힌다.
- 카메라 방향은 세로(폰 기준)로 고정하고, 폰을 눕혀 찍은 사진 · 클립은 찍은 뒤 `uprightTurn` 만큼 돌린다.
- 결과는 픽셀을 새로 그린 PNG 라서 위치정보 같은 EXIF 가 남지 않는다. 서버 없음, 수집하는 데이터 없음.
- 출력 중 화면을 탭하면 바로 끝까지 출력된다.
- **SAVE .MP4**: 출력되는 과정을 세로 영상(1080x1920, 30fps, 약 5초, 14Mbps)으로 만들어 사진 앱에 저장한다. 아래에 `C:\> camera.exe` 워터마크.
  화면 밖에 영상 장면(`lib/widgets/print_video_frame.dart`)을 그려 한 장씩 뜨고, 폰의 하드웨어 H.264 인코더로 묶는다 (`lib/logic/video_writer.dart`).

## 처음 실행

```bash
bash tool/setup_platforms.sh   # ios/ android/ 생성 + 앱 이름·권한 문구 + 패키지 + 앱 아이콘
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
  logic/print_timeline.dart .MP4 시간표 (몇 번째 프레임에 무엇이 보이는지)
  logic/video_writer.dart   RGBA 프레임 → MP4
  screens/camera_screen.dart 촬영 화면
  screens/print_screen.dart  출력 애니메이션 → 결과, 저장·공유
  widgets/result_card.dart   사진 뷰어 창 (저장 이미지도 이걸 그대로 뜬다)
  widgets/print_video_frame.dart .MP4 한 장면 (9:16)
  widgets/retro.dart         스캔라인, 로그 줄, 버튼, 진행 막대
```

## 다음 할 일

- PRO (일회성 구매): .MP4 워터마크 제거, 추가 모드, 창 테마
  (.MP4 저장 자체는 무료: 영상이 퍼지는 게 광고라서)
