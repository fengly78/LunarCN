#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
    echo '当前版本需要 Apple Silicon Mac 和 Xcode 命令行工具。' >&2
    exit 1
fi

out_dir="../build/lunar-cn"
app_dir="$out_dir/LunarCN.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp Info.plist "$app_dir/Contents/Info.plist"
xcrun swift Tools/MakeIcon.swift "$out_dir/LunarCN.iconset"
iconutil -c icns "$out_dir/LunarCN.iconset" -o "$app_dir/Contents/Resources/LunarCN.icns"

xcrun clang -O2 -Wall -Wextra -fmodules -DMAX_DISPLAYS=32 \
    -target arm64-apple-macos13.0 -I Vendor/m1ddc/headers \
    Vendor/m1ddc/sources/i2c.m Vendor/m1ddc/sources/ioregistry.m Sources/DDCHelper.m \
    -framework Foundation -framework IOKit -framework CoreGraphics -framework CoreDisplay \
    -o "$app_dir/Contents/MacOS/ddc-helper"

xcrun swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macosx13.0 \
    Sources/BuiltinDisplayEngine.swift Sources/ScreenGuardian.swift \
    -framework CoreGraphics -framework IOKit \
    -o "$app_dir/Contents/MacOS/screen-guardian"

xcrun swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macosx13.0 \
    Sources/DisplayControl.swift Sources/Preferences.swift Sources/AutomaticBrightness.swift Sources/LiveBrightness.swift Sources/BuiltinDisplayEngine.swift Sources/BuiltinDisplay.swift Sources/App.swift Sources/SelfTests.swift \
    -framework AppKit -framework SwiftUI -framework CoreDisplay \
    -o "$app_dir/Contents/MacOS/LunarCN"

cat NOTICE.txt Vendor/m1ddc/LICENSE ../LICENSE > "$app_dir/Contents/Resources/NOTICE.txt"
codesign --force --sign - "$app_dir/Contents/MacOS/ddc-helper"
codesign --force --sign - "$app_dir/Contents/MacOS/screen-guardian"
codesign --force --sign - "$app_dir"
"$app_dir/Contents/MacOS/LunarCN" --self-test
codesign --verify --deep --strict "$app_dir"
ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$out_dir/LunarCN.zip"
echo "构建完成：$(cd "$out_dir" && pwd)/LunarCN.app"
