# 스토어 그림

- `screenshots/` App Store: `iphone-0N` (6.9형 1320x2868) · `iphone65-0N` (6.5형 1284x2778) · `ipad-0N` (13형 2064x2752)
- `../play/` Google Play: `play-0N` (폰 1080x1920) · `feature-1024x500` (대표 이미지) · `icon-512`

다시 만들기 (playwright 필요):

```bash
mkdir -p fonts   # JetBrainsMono · NanumGothicCoding (assets/fonts) + NotoSansKR.ttf 를 넣는다
node render.js   # → out/ 스크린샷
node feature.js  # → out/feature-1024x500.png
```

`img/` 의 예시 사진은 scikit-image 예제 사진(CC0 · 공공 저작물: 고양이 · 커피 · 로켓)에
앱과 같은 필터 계산을 입힌 것.
