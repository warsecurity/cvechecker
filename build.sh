#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [ -z "$SDK" ] || [ ! -d "$SDK" ]; then
  echo "Set ANDROID_HOME to your Android SDK directory first." >&2
  exit 1
fi

BT="${ANDROID_BUILD_TOOLS:-}"
if [ -z "$BT" ]; then
  for d in $(ls -d "$SDK"/build-tools/*/ 2>/dev/null | sed 's:/*$::' | sort -V -r); do
    if [ -x "$d/aapt2" ]; then BT="$d"; break; fi
  done
fi
[ -n "$BT" ] || { echo "No build-tools with aapt2 found under $SDK/build-tools" >&2; exit 1; }

AJ="${ANDROID_JAR:-}"
if [ -z "$AJ" ] || [ ! -f "$AJ" ]; then
  AJ=$(ls "$SDK"/platforms/android-*/android.jar 2>/dev/null | sort -V | tail -1)
fi
[ -f "$AJ" ] || { echo "No android.jar found. Install Android SDK platform 33 or newer." >&2; exit 1; }

if [ -x "$BT/d8" ]; then
  D8=("$BT/d8")
elif [ -f "$BT/lib/d8.jar" ]; then
  D8=(java -cp "$BT/lib/d8.jar" com.android.tools.r8.D8)
elif [ -f "$BT/d8.jar" ]; then
  D8=(java -cp "$BT/d8.jar" com.android.tools.r8.D8)
else
  echo "d8 is missing from $BT. Install/reinstall Android SDK Build-Tools." >&2
  exit 1
fi

for t in javac java keytool zip; do
  command -v "$t" >/dev/null || { echo "Missing tool: $t" >&2; exit 1; }
done
for t in aapt2 zipalign apksigner; do
  [ -x "$BT/$t" ] || { echo "Missing $BT/$t; reinstall Android SDK Build-Tools." >&2; exit 1; }
done

rm -rf build
mkdir -p build/stubs build/classes build/dex

javac -nowarn -source 8 -target 8 -cp "$AJ" -d build/stubs \
  $(find stubs -name '*.java')
javac -nowarn -source 8 -target 8 -cp "$AJ:build/stubs" -d build/classes \
  $(find src -name '*.java')

"${D8[@]}" --release --min-api 26 --lib "$AJ" --output build/dex \
  $(find build/classes -name '*.class')

"$BT/aapt2" compile --dir res -o build/res.zip
"$BT/aapt2" link -o build/base.apk -I "$AJ" \
  --manifest AndroidManifest.xml --min-sdk-version 26 --target-sdk-version 33 \
  -A assets build/res.zip
(cd build/dex && zip -q ../base.apk classes.dex)
"$BT/zipalign" -f -p 4 build/base.apk build/aligned.apk

[ -f debug.keystore ] || keytool -genkeypair \
  -keystore debug.keystore -storepass android -keypass android -alias k \
  -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=cvechecker"

"$BT/apksigner" sign --ks debug.keystore --ks-pass pass:android \
  --out cve-checker.apk build/aligned.apk

echo "Built cve-checker.apk"
