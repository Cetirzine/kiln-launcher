#!/bin/bash
# 打包安装用的 DMG：包含 Kiln.app 与“应用程序”文件夹的快捷方式
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.2.9}"
export VERSION
./scripts/build-app.sh

DMG="build/Kiln-$VERSION.dmg"
STAGING="$(mktemp -d)/Kiln"
mkdir -p "$STAGING"
cp -R build/Kiln.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create -volname "Kiln $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null
codesign --force --sign - "$DMG" >/dev/null
echo "已生成 $DMG（$(du -h "$DMG" | cut -f1)）"
shasum -a 256 "$DMG"
