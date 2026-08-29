#!/usr/bin/env bash
# 手工编译 TLocationPlugin.framework（绕开 xcodebuild 的 ScanDependencies bug）
# 用法：bash build_framework.sh <TLocationPlugin源码目录>
set -euo pipefail

SRC="${1:-TLocationPlugin-src/TLocationPlugin}"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
echo "SDK=$SDK"

OBJ=/tmp/tlobj
OUT=/tmp/newfw/TLocationPlugin.framework
rm -rf /tmp/newfw "$OBJ"
mkdir -p "$OBJ" "$OUT"

INCLUDES="-I$SRC -I$SRC/License -I$SRC/Others -I$SRC/Tools -I$SRC/ViewControllerAndViews"
COMMON="-arch arm64 -isysroot $SDK -fobjc-arc -miphoneos-version-min=12.0 -w $INCLUDES"

echo "== compile =="
while IFS= read -r f; do
  base="$(basename "$f" .m)"
  echo "cc $f"
  clang $COMMON -c "$f" -o "$OBJ/$base.o"
done < <(find "$SRC" -name '*.m' | sort)

echo "== link =="
clang -arch arm64 -isysroot "$SDK" -dynamiclib -fobjc-arc -miphoneos-version-min=12.0 -w \
  -framework UIKit -framework Foundation -framework CoreLocation -framework CoreGraphics \
  -framework AudioToolbox -framework Security -framework QuartzCore \
  -Xlinker -install_name -Xlinker @rpath/TLocationPlugin.framework/TLocationPlugin \
  -Xlinker -rpath -Xlinker @loader_path/Frameworks \
  -o "$OUT/TLocationPlugin" "$OBJ"/*.o

echo "== done =="
ls -la "$OUT/TLocationPlugin"
