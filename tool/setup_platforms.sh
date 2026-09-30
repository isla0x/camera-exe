#!/usr/bin/env bash
# android/ ios/ 폴더가 없으면 만들고, 앱 이름과 카메라·사진 권한 문구를 넣는다.
# 여러 번 돌려도 안전하다. (이미 있는 설정은 건드리지 않는다)
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d android ] || [ ! -d ios ]; then
  flutter create --org com.isla0x --project-name camera_exe --platforms android,ios .
  # flutter create 가 만든 기본 테스트는 이 앱과 맞지 않아서 지운다.
  rm -f test/widget_test.dart
fi

python3 - <<'PY'
import re, pathlib

# --- iOS: 표시 이름 + 권한 문구 ---
plist = pathlib.Path("ios/Runner/Info.plist")
if plist.exists():
    s = plist.read_text()
    s = re.sub(r"(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)", r"\1camera.exe\2", s)
    keys = {
        "NSCameraUsageDescription": "Takes photos to print them in retro PC style.",
        "NSPhotoLibraryAddUsageDescription": "Saves your printed photos to your photo library.",
    }
    add = "".join(
        f"\t<key>{k}</key>\n\t<string>{v}</string>\n" for k, v in keys.items() if f"<key>{k}</key>" not in s
    )
    if add:
        i = s.rfind("</dict>")
        s = s[:i] + add + s[i:]
    plist.write_text(s)

# --- Android: 표시 이름 + 옛 기기(Android 10 이하) 저장 권한 ---
manifest = pathlib.Path("android/app/src/main/AndroidManifest.xml")
if manifest.exists():
    s = manifest.read_text()
    s = re.sub(r'android:label="[^"]*"', 'android:label="camera.exe"', s, count=1)
    # camera 플러그인도 같은 권한을 maxSdkVersion 28 로 넣어서, 우리 값(29)으로 덮어쓴다고 알려 준다.
    if "xmlns:tools=" not in s:
        s = s.replace("<manifest ", '<manifest xmlns:tools="http://schemas.android.com/tools" ', 1)
    perm = ('<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" '
            'android:maxSdkVersion="29" tools:replace="android:maxSdkVersion" />')
    if "WRITE_EXTERNAL_STORAGE" not in s:
        s = s.replace("<application", perm + "\n    <application", 1)
    elif 'tools:replace="android:maxSdkVersion"' not in s:
        s = s.replace('android:maxSdkVersion="29" />', 'android:maxSdkVersion="29" tools:replace="android:maxSdkVersion" />', 1)
    manifest.write_text(s)
PY

echo "platform folders ready."
