#!/bin/bash
# 构建 Kiln.app（Apple 芯片原生，release 优化）
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.2.6}"
ARCH="${ARCH:-arm64}"            # 需要同时支持 Intel 时可设为 "arm64 x86_64"
APP="build/Kiln.app"

ARCH_FLAGS=()
for a in $ARCH; do ARCH_FLAGS+=(--arch "$a"); done

# 构建时注入微软登录的 Client ID（不修改源码中的文件）
ID_FILE="Sources/LauncherCore/Auth/EmbeddedClientID.swift"
if [ -n "${KILN_MS_CLIENT_ID:-}" ]; then
    if ! [[ "$KILN_MS_CLIENT_ID" =~ ^[0-9a-fA-F-]{36}$ ]]; then
        echo "KILN_MS_CLIENT_ID 应为 36 位的 GUID" >&2; exit 1
    fi
    cp "$ID_FILE" "$ID_FILE.orig"
    trap 'mv "$ID_FILE.orig" "$ID_FILE"' EXIT
    sed -i '' "s/package static let value = \".*\"/package static let value = \"$KILN_MS_CLIENT_ID\"/" "$ID_FILE"
fi
# 内置的 Mod 中文名表与 assets/mod-names-zh.json 保持同步
python3 scripts/gen-mod-names.py
swift build -c release "${ARCH_FLAGS[@]}"
BIN="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)/Kiln"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Kiln"

# 图标
TOOLS="$(mktemp -d)"
ICONSET="$TOOLS/Kiln.iconset"
swiftc -O scripts/make-icon/main.swift Sources/Kiln/UI/LogoMark.swift -o "$TOOLS/make-icon"
"$TOOLS/make-icon" "$ICONSET" assets/logo.png
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Kiln.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Kiln</string>
    <key>CFBundleDisplayName</key><string>Kiln</string>
    <key>CFBundleExecutable</key><string>Kiln</string>
    <key>CFBundleIdentifier</key><string>app.kiln.launcher</string>
    <key>CFBundleIconFile</key><string>Kiln</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
    <key>CFBundleLocalizations</key><array><string>zh_CN</string><string>zh_TW</string><string>en</string></array>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
    <key>NSHumanReadableCopyright</key><string>© 2026 NelsonPence</string>
    <key>LSArchitecturePriority</key><array><string>arm64</string></array>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
</dict>
</plist>
PLIST

# 本地使用的临时签名
codesign --force --sign - "$APP" >/dev/null
echo "已生成 $APP"
