#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
bundle=${KEYOOPS_BUNDLE_OUTPUT:-dist/KeyOops.app}
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
case "${1:-}" in
    --universal)
        for arch in arm64 x86_64; do
            swift build --arch "$arch" -c release --product KeyOops
        done
        arm=$(swift build --arch arm64 -c release --show-bin-path)
        intel=$(swift build --arch x86_64 -c release --show-bin-path)
        lipo -create "$arm/KeyOops" "$intel/KeyOops" -output "$bundle/Contents/MacOS/KeyOops"
        lipo "$bundle/Contents/MacOS/KeyOops" -verify_arch arm64 x86_64
        ;;
    "")
        swift build -c release --product KeyOops
        bin=$(swift build -c release --show-bin-path)
        cp "$bin/KeyOops" "$bundle/Contents/MacOS/"
        ;;
    *) echo "Usage: $0 [--universal]" >&2; exit 2 ;;
esac
cp Resources/Info.plist "$bundle/Contents/"
cp Sources/KeyOopsCore/Data/*.bin "$bundle/Contents/Resources/"
cp Sources/KeyOopsCore/Data/phrases.arpa Sources/KeyOopsCore/Data/layout-channel.json "$bundle/Contents/Resources/"
cp -R Licenses "$bundle/Contents/Resources/"
cp THIRD_PARTY_NOTICES.md "$bundle/Contents/Resources/"
cp LICENSE "$bundle/Contents/Resources/"
plutil -lint "$bundle/Contents/Info.plist"
# Finder may attach bundle metadata after the first launch. It prevents re-signing.
if xattr -p com.apple.FinderInfo "$bundle" >/dev/null 2>&1; then
    xattr -d com.apple.FinderInfo "$bundle"
fi
codesign --force --sign - "$bundle"
codesign --verify --strict "$bundle"
echo "Built $bundle"
