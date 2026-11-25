#!/bin/bash
# 完整构建：aapt2 在手机端跑（x86 二进制跑不动），其余在 proot 内完成
set -e
cd "$(dirname "$0")"
ADB="adb -s 127.0.0.1:5555"
BT=sdk/android-14
PLAT=sdk/android-35/android.jar
BUILD=/data/local/tmp/gwbuild

echo "== 1/6 推送资源到手机 =="
$ADB push AndroidManifest.xml $BUILD/ >/dev/null
$ADB push res $BUILD/ >/dev/null
$ADB push assets $BUILD/ >/dev/null

echo "== 2/6 手机端 aapt2 编译链接 =="
$ADB shell "su -c 'cd $BUILD && export LD_LIBRARY_PATH=/data/local/tmp/aapt2 && A=/data/local/tmp/aapt2/aapt2 && \
  \$A compile --dir res -o res.zip && \
  \$A link -o base.apk -I android.jar --manifest AndroidManifest.xml -R res.zip -A assets \
     --min-sdk-version 24 --target-sdk-version 34 --auto-add-overlay && \
  cp base.apk /sdcard/base.apk && chmod 644 /sdcard/base.apk'" >/dev/null

echo "== 3/6 取回资源包 =="
rm -rf build && mkdir -p build/classes build/dex
$ADB pull /sdcard/base.apk build/base.apk >/dev/null

echo "== 4/6 编译 Java =="
javac -nowarn -source 8 -target 8 -bootclasspath "$PLAT" -cp "$PLAT" \
  -d build/classes src/com/dsh/gateway/MainActivity.java src/com/dsh/gateway/HeartbeatService.java

echo "== 5/6 d8 转 dex =="
java -cp $BT/lib/d8.jar com.android.tools.r8.D8 --lib "$PLAT" --min-api 24 \
  --output build/dex $(find build/classes -name '*.class')

echo "== 6/6 打包签名 =="
cp build/base.apk build/unsigned.apk
python3 - <<'PY'
import zipfile
with zipfile.ZipFile('build/unsigned.apk','a',zipfile.ZIP_DEFLATED) as z:
    z.write('build/dex/classes.dex','classes.dex')
PY
[ -f gw.keystore ] || keytool -genkeypair -keystore gw.keystore \
  -storepass android -keypass android -alias gwkey -keyalg RSA -keysize 2048 \
  -validity 10000 -dname "CN=Hotspot Gateway" >/dev/null 2>&1
java -jar $BT/lib/apksigner.jar sign --ks gw.keystore --ks-pass pass:android \
  --key-pass pass:android --out gateway.apk build/unsigned.apk

ls -lh gateway.apk
echo "构建完成"
