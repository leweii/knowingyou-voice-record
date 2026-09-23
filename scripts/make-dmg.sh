#!/bin/sh
# Packages the signed, notarized .app from sign-and-notarize.sh into a DMG
# with an Applications-folder symlink, then signs/notarizes/staples the DMG
# itself (Gatekeeper checks the disk image too, not just the app inside it).
# See docs/specs/S21.
#
# Uses hdiutil rather than a third-party tool (create-dmg) — it ships with
# macOS, so `make release` doesn't need a new Homebrew dependency just to
# draw a background image.
#
# Usage: scripts/make-dmg.sh <version>
# Reads: build/export/KnowingYou.app (produced by sign-and-notarize.sh)
# Produces: build/KnowingYou-<version>-arm64.dmg, build/SHA256SUMS
set -eu

VERSION="${1:?usage: $0 <version>}"

: "${KY_SIGN_IDENTITY:?set KY_SIGN_IDENTITY to your 'Developer ID Application: ...' identity}"
: "${KY_NOTARY_PROFILE:?set KY_NOTARY_PROFILE to a notarytool keychain profile name}"

BUILD_DIR="build"
APP_PATH="$BUILD_DIR/export/KnowingYou.app"
DMG_NAME="KnowingYou-$VERSION-arm64.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"
STAGING_DIR="$BUILD_DIR/dmg-staging"

if [ ! -d "$APP_PATH" ]; then
	echo "make-dmg: $APP_PATH not found — run scripts/sign-and-notarize.sh $VERSION first" >&2
	exit 1
fi

echo "make-dmg: staging DMG contents..."
rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

echo "make-dmg: building $DMG_NAME..."
hdiutil create \
	-volname "KnowingYou $VERSION" \
	-srcfolder "$STAGING_DIR" \
	-ov -format UDZO \
	"$DMG_PATH"

echo "make-dmg: signing DMG..."
codesign --force --sign "$KY_SIGN_IDENTITY" "$DMG_PATH"

echo "make-dmg: submitting DMG to notarytool (profile: $KY_NOTARY_PROFILE)..."
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$KY_NOTARY_PROFILE" --wait

echo "make-dmg: stapling DMG..."
xcrun stapler staple "$DMG_PATH"

echo "make-dmg: verifying with spctl..."
spctl -a -t open --context context:primary-signature -vv "$DMG_PATH"

echo "make-dmg: writing SHA256SUMS..."
( cd "$BUILD_DIR" && shasum -a 256 "$DMG_NAME" > SHA256SUMS )

rm -rf "$STAGING_DIR"

echo "make-dmg: OK -> $DMG_PATH"
cat "$BUILD_DIR/SHA256SUMS"
