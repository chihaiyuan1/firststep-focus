#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/swift-env.sh
FIRSTSTEP_SDK=$(firststep_sdk)
mkdir -p dist
swift build -c release --build-system native --sdk "$FIRSTSTEP_SDK"
BIN_DIR=$(swift build -c release --build-system native --sdk "$FIRSTSTEP_SDK" --show-bin-path)
APP="dist/先做一刻.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/FirstStep" "$APP/Contents/MacOS/FirstStep"
cp "$BIN_DIR/FirstStep" "$APP/Contents/MacOS/FirstStepNative"
/usr/bin/swift scripts/make-icons.swift dist
/usr/bin/iconutil -c icns dist/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cp dist/icon128.png extension/icon128.png
python3 - <<'PY'
import plistlib
from pathlib import Path
p=Path('dist/先做一刻.app/Contents/Info.plist')
p.write_bytes(plistlib.dumps({'CFBundleName':'先做一刻','CFBundleDisplayName':'先做一刻','CFBundleIdentifier':'com.dayuan.firststep','CFBundleExecutable':'FirstStep','CFBundlePackageType':'APPL','CFBundleShortVersionString':'0.7.1','CFBundleVersion':'10','LSMinimumSystemVersion':'13.0','NSHighResolutionCapable':True,'CFBundleIconFile':'AppIcon','NSHumanReadableCopyright':'Personal local focus tool'}))
PY
codesign --force --deep --sign - "$APP"
rm -rf dist/AppIcon.iconset
printf 'Built: %s/%s\n' "$PWD" "$APP"
