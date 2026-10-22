#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/dist/macos"
APP="$OUT/LokiThrogPets.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/artifacts/macos-build"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
for ARCH in arm64 x86_64; do
  xcrun swiftc -swift-version 5 -O -sdk "$SDK" -target "$ARCH-apple-macosx11.0" \
    -framework AppKit -framework ImageIO "$ROOT"/macos/Sources/*.swift \
    -o "$ROOT/artifacts/macos-build/LokiThrogPets-$ARCH"
done
lipo -create "$ROOT/artifacts/macos-build/LokiThrogPets-arm64" "$ROOT/artifacts/macos-build/LokiThrogPets-x86_64" -output "$APP/Contents/MacOS/LokiThrogPets"
cp "$ROOT/macos/Info.plist" "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources/assets" "$APP/Contents/Resources/sounds" "$APP/Contents/Resources/fixtures"
cp "$ROOT"/assets/*.png "$APP/Contents/Resources/assets/"
cp "$ROOT"/sounds/*.wav "$APP/Contents/Resources/sounds/"
cp "$ROOT"/macos/Tests/fixtures/*.png "$APP/Contents/Resources/fixtures/"
cp "$ROOT/docs/action-catalog.json" "$APP/Contents/Resources/actions.json"
cp "$ROOT/docs/sound-cues.json" "$APP/Contents/Resources/sound-cues.json"
cp "$ROOT/NOTICE.md" "$APP/Contents/Resources/NOTICE.md"
chmod 755 "$APP/Contents/MacOS/LokiThrogPets"
plutil -lint "$APP/Contents/Info.plist"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
lipo -archs "$APP/Contents/MacOS/LokiThrogPets" | tee "$OUT/architectures.txt"
cp "$ROOT/macos/使用说明.md" "$OUT/使用说明.md"
cp "$ROOT/NOTICE.md" "$OUT/NOTICE.md"
cd "$OUT"
ditto -c -k --sequesterRsrc --keepParent LokiThrogPets.app LokiThrogPets-v0.10.1-macos-universal.zip
shasum -a 256 LokiThrogPets-v0.10.1-macos-universal.zip > SHA256SUMS-macos.txt
echo "Built $OUT/LokiThrogPets-v0.10.1-macos-universal.zip"
