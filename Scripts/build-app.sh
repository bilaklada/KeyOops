#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build -c release --product KeyOops
bin=$(swift build -c release --show-bin-path)
bundle=dist/KeyOops.app
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$bin/KeyOops" "$bundle/Contents/MacOS/"
cp Resources/Info.plist "$bundle/Contents/"
cp LICENSE "$bundle/Contents/Resources/"
plutil -lint "$bundle/Contents/Info.plist"
# Finder may attach bundle metadata after the first launch. It prevents re-signing.
if xattr -p com.apple.FinderInfo "$bundle" >/dev/null 2>&1; then
    xattr -d com.apple.FinderInfo "$bundle"
fi
codesign --force --sign - "$bundle"
codesign --verify --strict "$bundle"
echo "Built $bundle"
