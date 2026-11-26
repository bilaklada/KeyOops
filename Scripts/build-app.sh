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
codesign --force --sign - "$bundle"
codesign --verify --strict "$bundle"
echo "Built $bundle"
