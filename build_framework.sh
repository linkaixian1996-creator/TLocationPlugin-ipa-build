#!/usr/bin/env bash
# 手工编译并「完整组装」TLocationPlugin.framework（抖音版）
#
# 与快手版的区别：快手包内本来就带一个已注入的 framework，可以直接拷它的 nib/图片资源；
# 抖音包是干净包，什么都没有 —— 所以 nib（由 xib 用 ibtool 编）、图片 bundle、Info.plist
# 全部要在这里生成，否则运行到设置界面会崩（找不到 nib）。
#
# 用法：bash build_framework.sh [源码目录] [输出目录]
set -euo pipefail

SRC="${1:-TLocationPlugin-src/TLocationPlugin}"
OUTROOT="${2:-/tmp/newfw}"
FW="$OUTROOT/TLocationPlugin.framework"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
echo "SDK=$SDK"
echo "SRC=$SRC"
echo "FW=$FW"

OBJ=/tmp/tlobj
rm -rf "$OUTROOT" "$OBJ"
mkdir -p "$OBJ" "$FW"

INCLUDES="-I$SRC -I$SRC/License -I$SRC/Others -I$SRC/Tools -I$SRC/ViewControllerAndViews"
COMMON="-arch arm64 -isysroot $SDK -fobjc-arc -miphoneos-version-min=12.0 -w $INCLUDES"

echo "== 1/5 编译 .m =="
while IFS= read -r f; do
  echo "  cc $(basename "$f")"
  clang $COMMON -c "$f" -o "$OBJ/$(basename "$f" .m).o"
done < <(find "$SRC" -name '*.m' | sort)

echo "== 2/5 链接 dylib =="
clang -arch arm64 -isysroot "$SDK" -dynamiclib -fobjc-arc -miphoneos-version-min=12.0 -w \
  -framework UIKit -framework Foundation -framework CoreLocation -framework CoreGraphics \
  -framework AudioToolbox -framework Security -framework QuartzCore -framework MapKit \
  -Xlinker -install_name -Xlinker @rpath/TLocationPlugin.framework/TLocationPlugin \
  -Xlinker -rpath -Xlinker @loader_path/Frameworks \
  -o "$FW/TLocationPlugin" "$OBJ"/*.o

echo "== 3/5 编译 xib -> nib =="
shopt -s nullglob
for xib in "$SRC"/ViewControllerAndViews/*.xib; do
  name="$(basename "$xib" .xib)"
  echo "  ibtool $name"
  xcrun ibtool --compile "$FW/$name.nib" "$xib" \
    --minimum-deployment-target 12.0 \
    --target-device iphone --target-device ipad \
    --module TLocationPlugin \
    --errors --warnings --notices --output-format human-readable-text \
    || { echo "  !! ibtool 失败: $name"; exit 1; }
done
shopt -u nullglob

echo "== 4/5 图片资源 + Info.plist =="
cp -R "$SRC/TLocationPluginImages.bundle" "$FW/"
cat > "$FW/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>zh_CN</string>
	<key>CFBundleExecutable</key>
	<string>TLocationPlugin</string>
	<key>CFBundleIdentifier</key>
	<string>com.tlocation.plugin</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>TLocationPlugin</string>
	<key>CFBundlePackageType</key>
	<string>FMWK</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>CFBundleSupportedPlatforms</key>
	<array>
		<string>iPhoneOS</string>
	</array>
	<key>MinimumOSVersion</key>
	<string>12.0</string>
</dict>
</plist>
PLIST

echo "== 5/5 adhoc 签名 =="
codesign -f -s - "$FW/TLocationPlugin" || echo "  (framework 签名失败，交给 TrollStore/全能签 处理)"
codesign -f -s - "$FW" || true

echo "== 结果 =="
ls -la "$FW"
file "$FW/TLocationPlugin"
