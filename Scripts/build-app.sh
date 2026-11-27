#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
output=${KEYOOPS_BUNDLE_OUTPUT:-dist/KeyOops.app}
# File-provider folders can reattach Finder metadata between stripping it
# and signing. Assemble and sign on the local temporary volume first.
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
bundle="$stage/KeyOops.app"
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
codesign --force --sign - "$bundle"
codesign --verify --strict --all-architectures "$bundle"
mkdir -p "$(dirname "$output")"
ditto --norsrc "$bundle" "$output"
if xattr -p 'com.apple.fileprovider.fpfs#P' "$output" >/dev/null 2>&1; then
    # Finder may recreate its bundle flag immediately. Verify the signature
    # in place and strictly verify the delivered contents on a local volume.
    codesign --verify --all-architectures "$output"
    ditto --norsrc "$output" "$stage/copied.app"
    codesign --verify --strict --all-architectures "$stage/copied.app"
else
    codesign --verify --strict --all-architectures "$output"
fi
echo "Built $output"
