#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
mkdir -p .build/package dist
BINARIES=()
RESOURCE_BUNDLE=""
for architecture in arm64 x86_64; do
    BUILD_ARGS=(--build-system native --disable-sandbox --cache-path "$PWD/.build/cache"
                --scratch-path "$PWD/.build/$architecture" --arch "$architecture" -c release)
    swift build "${BUILD_ARGS[@]}"
    BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
    BINARIES+=("$BIN_DIR/Screenz")
    RESOURCE_BUNDLE="$BIN_DIR/Screenz_Screenz.bundle"
done
APP_DIR="$PWD/.build/package/Screenz.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
lipo -create "${BINARIES[@]}" -output "$APP_DIR/Contents/MacOS/Screenz"
chmod 755 "$APP_DIR/Contents/MacOS/Screenz"
ditto "$RESOURCE_BUNDLE" "$APP_DIR/Contents/Resources/Screenz_Screenz.bundle"
cp Packaging/Info.plist "$APP_DIR/Contents/Info.plist"
cp LICENSE "$APP_DIR/Contents/Resources/LICENSE.txt"
swift scripts/make-icon.swift "$PWD/.build/Screenz.iconset"
iconutil -c icns .build/Screenz.iconset -o "$APP_DIR/Contents/Resources/Screenz.icns"
plutil -lint "$APP_DIR/Contents/Info.plist"
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_DIR"
else
    codesign --force --sign - "$APP_DIR"
fi
codesign --verify --deep --strict "$APP_DIR"
lipo "$APP_DIR/Contents/MacOS/Screenz" -verify_arch arm64
lipo "$APP_DIR/Contents/MacOS/Screenz" -verify_arch x86_64
rm -rf "$PWD/dist/Screenz.app"
ditto "$APP_DIR" "$PWD/dist/Screenz.app"
echo "Built universal app: $PWD/dist/Screenz.app"
