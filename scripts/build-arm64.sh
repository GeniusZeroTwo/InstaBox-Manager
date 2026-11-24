#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

HOST_ARCH="$(uname -m)"
if [[ "$HOST_ARCH" != "arm64" ]]; then
  echo "Error: This build targets Apple Silicon (arm64) only, current host is $HOST_ARCH."
  exit 1
fi

echo "==> [1/6] Building InstaBoxManager (Release, arm64-only)..."
swift build -c release --arch arm64

BIN_PATH="$PROJECT_DIR/.build/arm64-apple-macosx/release/InstaBoxManager"
if [[ ! -f "$BIN_PATH" ]]; then
  BIN_PATH="$(swift build -c release --arch arm64 --show-bin-path)/InstaBoxManager"
fi

ARCHS="$(lipo -archs "$BIN_PATH")"
echo "==> Verified binary architectures: $ARCHS"
if [[ "$ARCHS" != "arm64" ]]; then
  echo "Error: Expected strictly arm64 binary, got: $ARCHS"
  exit 1
fi

APP_NAME="InstaBox Manager"
VERSION="1.0.0"
DIST_DIR="$PROJECT_DIR/dist"
APP_BUNDLE="$DIST_DIR/${APP_NAME}.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
DMG_PATH="$DIST_DIR/InstaBox-Manager-${VERSION}-arm64.dmg"
ZIP_PATH="$DIST_DIR/InstaBox-Manager-${VERSION}-arm64.zip"
CHECKSUM_PATH="$DIST_DIR/SHA256SUMS.txt"

TMP_WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_WORK_DIR"' EXIT

rm -rf "$APP_BUNDLE" "$DMG_PATH" "$ZIP_PATH" "$CHECKSUM_PATH"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

echo "==> [2/6] Generating macOS AppIcon.icns..."
ICONSET_DIR="$TMP_WORK_DIR/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"

swift - "$ICONSET_DIR" << 'SWIFT_ICON'
import AppKit
import Foundation

let iconsetPath = CommandLine.arguments[1]
let sizes = [16, 32, 64, 128, 256, 512, 1024]

for size in sizes {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let inset = CGFloat(size) * 0.08
    let cardRect = rect.insetBy(dx: inset, dy: inset)
    let radius = CGFloat(size) * 0.225

    // 1. Deep obsidian-emerald luminous base squircle
    let path = NSBezierPath(roundedRect: cardRect, xRadius: radius, yRadius: radius)
    let baseGradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.04, green: 0.14, blue: 0.09, alpha: 1.0),
        NSColor(calibratedRed: 0.06, green: 0.34, blue: 0.18, alpha: 1.0),
        NSColor(calibratedRed: 0.13, green: 0.83, blue: 0.40, alpha: 1.0)
    ])!
    baseGradient.draw(in: path, angle: -48)

    // 2. Top-left caustic Liquid Glass specular sheen
    let sheenGradient = NSGradient(colors: [
        NSColor(calibratedWhite: 1.0, alpha: 0.42),
        NSColor(calibratedWhite: 1.0, alpha: 0.08),
        NSColor(calibratedWhite: 1.0, alpha: 0.0)
    ])!
    sheenGradient.draw(in: path, relativeCenterPosition: NSPoint(x: -0.42, y: 0.48))

    // 3. Inner floating frosted Liquid Glass prism plate
    let innerInset = CGFloat(size) * 0.19
    let innerRect = rect.insetBy(dx: innerInset, dy: innerInset)
    let innerRadius = CGFloat(size) * 0.16
    let innerPath = NSBezierPath(roundedRect: innerRect, xRadius: innerRadius, yRadius: innerRadius)
    let glassPlate = NSGradient(colors: [
        NSColor(calibratedWhite: 1.0, alpha: 0.26),
        NSColor(calibratedWhite: 1.0, alpha: 0.08)
    ])!
    glassPlate.draw(in: innerPath, angle: -65)
    NSColor(calibratedWhite: 1.0, alpha: 0.38).setStroke()
    innerPath.lineWidth = max(CGFloat(size) * 0.008, 0.75)
    innerPath.stroke()

    // Outer specular rim border
    NSColor(calibratedWhite: 1.0, alpha: 0.45).setStroke()
    path.lineWidth = max(CGFloat(size) * 0.010, 1.0)
    path.stroke()

    // 4. Stylized 3D cube wireframe inside glass prism
    let cx = CGFloat(size) * 0.5
    let cy = CGFloat(size) * 0.5
    let r = CGFloat(size) * 0.205
    let stroke = max(CGFloat(size) * 0.038, 1.4)

    NSColor.white.setStroke()
    let cube = NSBezierPath()
    cube.lineWidth = stroke
    cube.lineJoinStyle = .round
    cube.lineCapStyle = .round

    var pts: [NSPoint] = []
    for i in 0..<6 {
        let angle = CGFloat(i) * (.pi / 3.0) + (.pi / 6.0)
        pts.append(NSPoint(x: cx + r * cos(angle), y: cy + r * sin(angle)))
    }
    cube.move(to: pts[0])
    for i in 1..<6 { cube.line(to: pts[i]) }
    cube.close()

    // Inner Y edges
    cube.move(to: NSPoint(x: cx, y: cy))
    cube.line(to: pts[1])
    cube.move(to: NSPoint(x: cx, y: cy))
    cube.line(to: pts[3])
    cube.move(to: NSPoint(x: cx, y: cy))
    cube.line(to: pts[5])
    cube.stroke()

    NSGraphicsContext.restoreGraphicsState()

    if let png = rep.representation(using: .png, properties: [:]) {
        let outURL = URL(fileURLWithPath: iconsetPath).appendingPathComponent("icon_\(size)x\(size).png")
        try png.write(to: outURL)
    }
}
SWIFT_ICON

cp "$ICONSET_DIR/icon_32x32.png" "$ICONSET_DIR/icon_16x16@2x.png"
cp "$ICONSET_DIR/icon_64x64.png" "$ICONSET_DIR/icon_32x32@2x.png"
rm -f "$ICONSET_DIR/icon_64x64.png"
cp "$ICONSET_DIR/icon_256x256.png" "$ICONSET_DIR/icon_128x128@2x.png"
cp "$ICONSET_DIR/icon_512x512.png" "$ICONSET_DIR/icon_256x256@2x.png"
cp "$ICONSET_DIR/icon_1024x1024.png" "$ICONSET_DIR/icon_512x512@2x.png"
rm -f "$ICONSET_DIR/icon_1024x1024.png"

iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"

echo "==> [3/6] Assembling .app bundle & Info.plist (arm64-only)..."
cp "$BIN_PATH" "$MACOS_DIR/InstaBoxManager"
chmod +x "$MACOS_DIR/InstaBoxManager"

cat > "$CONTENTS_DIR/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh-Hans</string>
    <key>CFBundleDisplayName</key>
    <string>InstaBox Manager</string>
    <key>CFBundleExecutable</key>
    <string>InstaBoxManager</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>sh.instabox.mac-manager</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>InstaBox Manager</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>27.0</string>
    <key>LSArchitecturePriority</key>
    <array>
        <string>arm64</string>
    </array>
    <key>LSRequiresNativeExecution</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "==> [4/6] Ad-hoc signing & verifying app bundle..."
codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"
"$MACOS_DIR/InstaBoxManager" --self-test

echo "==> [5/6] Packaging ZIP & DMG installers..."
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

DMG_STAGE="$TMP_WORK_DIR/dmg_stage"
mkdir -p "$DMG_STAGE"
ditto "$APP_BUNDLE" "$DMG_STAGE/${APP_NAME}.app"
ln -s /Applications "$DMG_STAGE/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGE" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

codesign --force --sign - "$DMG_PATH"
hdiutil verify "$DMG_PATH" >/dev/null

echo "==> [6/6] Generating SHA-256 checksums..."
(
  cd "$DIST_DIR"
  shasum -a 256 "$(basename "$DMG_PATH")" "$(basename "$ZIP_PATH")" > "$(basename "$CHECKSUM_PATH")"
)

echo ""
echo "Build & packaging complete!"
echo "  App Bundle : $APP_BUNDLE"
echo "  DMG Image  : $DMG_PATH"
echo "  ZIP Archive: $ZIP_PATH"
echo "  Checksums  : $CHECKSUM_PATH"
echo "  Arch       : $(lipo -archs "$MACOS_DIR/InstaBoxManager")"
