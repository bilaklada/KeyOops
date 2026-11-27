#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p dist
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' Resources/Info.plist)
image="KeyOops-build-$version-macOS-universal.dmg"
stage=$(mktemp -d "$PWD/dist/disk.XXXXXX")
mount="$stage/volume"
mkdir "$mount"
mounted=no
cleanup() {
    if [ "$mounted" = yes ]; then hdiutil detach "$mount" || return; fi
    rm -rf "$stage"
}
trap cleanup EXIT
hdiutil create -size 32m -fs HFS+ -volname KeyOops "$stage/staging.dmg"
hdiutil attach -nobrowse -mountpoint "$mount" "$stage/staging.dmg"
mounted=yes
KEYOOPS_BUNDLE_OUTPUT="$mount/KeyOops.app" Scripts/build-app.sh --universal
ln -s /Applications "$mount/Applications"
codesign --verify --strict --all-architectures "$mount/KeyOops.app"
hdiutil detach "$mount"
mounted=no
hdiutil convert "$stage/staging.dmg" -format UDZO -o "$stage/release.dmg"
hdiutil verify "$stage/release.dmg"
hdiutil attach -readonly -nobrowse -mountpoint "$mount" "$stage/release.dmg"
mounted=yes
codesign --verify --strict --all-architectures "$mount/KeyOops.app"
lipo "$mount/KeyOops.app/Contents/MacOS/KeyOops" -verify_arch arm64 x86_64
test -s "$mount/KeyOops.app/Contents/Resources/ru-lex.bin"
test -s "$mount/KeyOops.app/Contents/Resources/en-lex.bin"
test -s "$mount/KeyOops.app/Contents/Resources/phrases.arpa"
test -s "$mount/KeyOops.app/Contents/Resources/Licenses/Tilqos-MIT.txt"
test -L "$mount/Applications"
hdiutil detach "$mount"
mounted=no
mv "$stage/release.dmg" "dist/$image"
(cd dist && shasum -a 256 "$image" > "$image.sha256")
echo "dist/$image"
