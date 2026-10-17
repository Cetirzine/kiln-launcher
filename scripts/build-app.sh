#!/bin/bash
# 构建 Kiln.app（Apple 芯片原生，release 优化）
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.2.9}"
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
# -emit-const-values：生成 App Intents（快捷指令）元数据所需的常量信息
swift build -c release "${ARCH_FLAGS[@]}" -Xswiftc -emit-const-values
BIN_DIR="$(swift build -c release "${ARCH_FLAGS[@]}" -Xswiftc -emit-const-values --show-bin-path)"
BIN="$BIN_DIR/Kiln"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Kiln"

# 快捷指令与聚焦搜索：从源码与常量信息生成 Metadata.appintents（需要 Xcode 中的 appintentsmetadataprocessor）
if PROCESSOR="$(xcrun --find appintentsmetadataprocessor 2>/dev/null)"; then
    WORK="$(mktemp -d)"
    find "$PWD/Sources/Kiln" -name "*.swift" > "$WORK/sources.txt"
    find "$PWD/.build" -name "*.swiftconstvalues" -path "*Kiln*" -path "*elease*" | grep -v LauncherCore > "$WORK/consts.txt" || true
    if [ -s "$WORK/consts.txt" ]; then
        "$PROCESSOR" --output "$APP/Contents/Resources" \
            --toolchain-dir "$(dirname "$(dirname "$(dirname "$(xcrun --find swift)")")")" \
            --module-name Kiln --sdk-root "$(xcrun --show-sdk-path)" \
            --xcode-version "$(xcodebuild -version | awk '/Build version/ {print $3}')" \
            --platform-family macOS --deployment-target 14.0 --target-triple arm64-apple-macos14.0 \
            --source-file-list "$WORK/sources.txt" --swift-const-vals-list "$WORK/consts.txt" \
            --binary-file "$APP/Contents/MacOS/Kiln" --force >/dev/null 2>"$WORK/err.txt" \
            || { echo "警告：生成快捷指令元数据失败" >&2; cat "$WORK/err.txt" >&2; }
    else
        echo "警告：没有找到 .swiftconstvalues，跳过快捷指令元数据" >&2
    fi
    rm -rf "$WORK"
else
    echo "警告：未安装 Xcode，跳过快捷指令元数据" >&2
fi
# 快捷指令中操作名称的英文翻译（中文直接使用源码中的文字）
mkdir -p "$APP/Contents/Resources/en.lproj"
cat > "$APP/Contents/Resources/en.lproj/Localizable.strings" <<'STRINGS'
"Minecraft 版本" = "Minecraft Instance";
"启动 Minecraft 版本" = "Launch Minecraft Instance";
"用 Kiln 启动指定的 Minecraft 版本。" = "Launch a Minecraft instance with Kiln.";
"版本" = "Instance";
"启动 ${instance}" = "Launch ${instance}";
"继续游戏" = "Continue Playing";
"用 Kiln 启动上次玩过的版本。" = "Launch the instance you played last with Kiln.";
"启动版本" = "Launch Instance";
STRINGS

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
    <key>CFBundleURLTypes</key>
    <array><dict>
        <key>CFBundleURLName</key><string>app.kiln.launcher.launch</string>
        <key>CFBundleURLSchemes</key><array><string>kiln</string></array>
    </dict></array>
</dict>
</plist>
PLIST

# 本地使用的临时签名
codesign --force --sign - "$APP" >/dev/null
echo "已生成 $APP"
