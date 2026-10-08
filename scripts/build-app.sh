#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release --product EyeRest
app="$PWD/build/休息一下.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/EyeRest "$app/Contents/MacOS/EyeRest"
cp Sources/EyeRestApp/Resources/tutu-spritesheet.png "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.liuqh.eyerest</string>
<key>CFBundleName</key><string>休息一下</string>
<key>CFBundleDisplayName</key><string>休息一下</string>
<key>CFBundleExecutable</key><string>EyeRest</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
swift scripts/make-icon.swift "$PWD/build/AppIcon.iconset"
iconutil -c icns build/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier com.liuqh.eyerest "$app"
codesign --verify --strict "$app"
print "Built: $app"
