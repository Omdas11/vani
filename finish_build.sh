#!/bin/bash
# OpenTune: install staged source into the flutter project, patch Android
# config, fetch packages, and build the release APK.
set -e
source ~/workspace/opentune/ENV.sh
cd ~/workspace/opentune/app

echo "=== installing staged source ==="
cp ~/workspace/opentune/staging/pubspec.yaml pubspec.yaml
rm -rf lib
cp -r ~/workspace/opentune/staging/lib lib

echo "=== patching AndroidManifest.xml (permissions) ==="
MANIFEST=android/app/src/main/AndroidManifest.xml
python3 - "$MANIFEST" <<'EOF'
import sys
p = sys.argv[1]
s = open(p).read()
perms = """    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
"""
if 'FOREGROUND_SERVICE_MEDIA_PLAYBACK' not in s:
    s = s.replace('    <application', perms + '    <application', 1)
    open(p, 'w').write(s)
    print('permissions added')
else:
    print('permissions already present')
EOF

echo "=== patching app/build.gradle.kts (minSdk 29, app id) ==="
GRADLE=android/app/build.gradle.kts
if [ -f "$GRADLE" ]; then
  # Task spec: minSdk 29 (Android 10+), applicationId com.opentune.app
  sed -i -E 's/minSdk\s*=\s*flutter\.minSdkVersion/minSdk = 29/; s/minSdkVersion\s+[0-9]+/minSdkVersion 29/; s/minSdk = 23/minSdk = 29/; s/minSdk = 26/minSdk = 29/' "$GRADLE"
  grep -n "minSdk" "$GRADLE" | head -3
else
  echo "NOTE: $GRADLE not found (Groovy build.gradle?)"
  ls android/app/
fi

echo "=== flutter pub get ==="
flutter pub get

echo "=== building release APK ==="
flutter build apk --release --split-per-abi

echo "=== done ==="
ls -la build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
