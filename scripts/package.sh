#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n "${NOTARY_PROFILE:-}" && -z "${SIGNING_IDENTITY:-}" ]]; then
    echo "NOTARY_PROFILE requires a Developer ID SIGNING_IDENTITY." >&2
    exit 1
fi
zsh scripts/build-app.sh
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Packaging/Info.plist)"
NAME="Screenz-$VERSION-universal"
APP_DIR="$PWD/dist/Screenz.app"
ZIP_PATH="$PWD/dist/$NAME.zip"
DMG_PATH="$PWD/dist/$NAME.dmg"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    SUBMISSION="$PWD/.build/package/notarization.zip"
    rm -f "$SUBMISSION"
    ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$SUBMISSION"
    xcrun notarytool submit "$SUBMISSION" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP_DIR"
    xcrun stapler validate "$APP_DIR"
fi
STAGING="$PWD/.build/dmg-root"
rm -rf "$STAGING"
mkdir -p "$STAGING"
ditto "$APP_DIR" "$STAGING/Screenz.app"
ln -s /Applications "$STAGING/Applications"
cp LICENSE "$STAGING/LICENSE.txt"
cp Packaging/Install.txt "$STAGING/Install.txt"
rm -f "$ZIP_PATH" "$DMG_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
hdiutil create -volname Screenz -srcfolder "$STAGING" -format UDZO -ov "$DMG_PATH"
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    codesign --timestamp --sign "$SIGNING_IDENTITY" "$DMG_PATH"
fi
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
    spctl --assess --type execute --verbose "$APP_DIR"
fi
codesign --verify --deep --strict "$APP_DIR"
hdiutil verify "$DMG_PATH"
(
    cd dist
    shasum -a 256 "$NAME.zip" "$NAME.dmg" > "$NAME.sha256"
)
echo "Packaged $DMG_PATH and $ZIP_PATH"
if [[ -z "${NOTARY_PROFILE:-}" ]]; then
    echo "This build is NOT notarized. See docs/RELEASING.md for Developer ID distribution."
fi
