#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
CONFIG=${1:-release}
swift build --build-system native -c "$CONFIG"
APP="XWriter.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" .build/AppIcon.iconset
cp ".build/$CONFIG/XWriter" "$APP/Contents/MacOS/XWriter"
if [[ -f me.png ]]; then
    cp -X me.png "$APP/Contents/Resources/me.png"
    xattr -c "$APP/Contents/Resources/me.png"
fi
".build/$CONFIG/XWriter" --make-icon .build/AppIcon-1024.png
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" .build/AppIcon-1024.png --out ".build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" .build/AppIcon-1024.png --out ".build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns .build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>XWriter</string>
    <key>CFBundleIdentifier</key><string>com.spakhm.xwriter</string>
    <key>CFBundleName</key><string>XWriter</string>
    <key>CFBundleDisplayName</key><string>XWriter</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $PWD/$APP"
