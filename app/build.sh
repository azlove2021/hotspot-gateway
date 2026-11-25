#!/bin/bash
set -e
cd "$(dirname "$0")"
BT=sdk/android-14
PLAT=sdk/android-35/android.jar
OUT=gateway.apk

rm -rf build
mkdir -p build/res build/gen build/classes build/dex

echo "[1/5] 编译资源"
$BT/aapt2 compile --dir res -o build/res.zip

echo "[2/5] 链接资源与清单"
$BT/aapt2 link \
  -o build/base.apk \
  -I "$PLAT" \
  --manifest AndroidManifest.xml \
  -R build/res.zip \
  -A assets \
  --java build/gen \
  --min-sdk-version 24 \
  --target-sdk-version 34 \
  --auto-add-overlay

echo "[3/5] 编译 Java"
javac -nowarn -source 8 -target 8 -bootclasspath "$PLAT" -cp "$PLAT" \
  -d build/classes \
  $(find src build/gen -name '*.java')

echo "[4/5] 转 dex 并打包"
$BT/d8 --lib "$PLAT" --min-api 24 --output build/dex \
  $(find build/classes -name '*.class')

cp build/base.apk build/unsigned.apk
(cd build/dex && zip -q ../unsigned.apk classes.dex)

echo "[5/5] 签名"
if [ ! -f build/debug.keystore ]; then
  keytool -genkeypair -keystore build/debug.keystore -storepass android -keypass android \
    -alias gwkey -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Hotspot Gateway" >/dev/null 2>&1
fi
$BT/apksigner sign --ks build/debug.keystore --ks-pass pass:android --key-pass pass:android \
  --out "$OUT" build/unsigned.apk

ls -lh "$OUT"
$BT/apksigner verify --print-certs "$OUT" | head -4
echo "完成: $(pwd)/$OUT"
