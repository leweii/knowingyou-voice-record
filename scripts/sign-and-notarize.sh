#!/bin/sh
# Archives a Release build, signs it with a real Developer ID Application
# identity, submits it for notarization, staples the ticket, and verifies
# the result with spctl. See docs/specs/S21.
#
# Deliberately does NOT hardcode a signing identity or team — per S21's
# decision record, those are supplied by the caller's environment so the
# repo itself never carries anyone's Apple Developer identity:
#
#   KY_SIGN_IDENTITY   "Developer ID Application: Your Name (TEAMID)"
#   KY_TEAM_ID         "TEAMID"
#   KY_NOTARY_PROFILE  name of a keychain profile created ahead of time with
#                      `xcrun notarytool store-credentials <profile-name>`
#
# Usage: scripts/sign-and-notarize.sh <version>
# Produces: build/export/KnowingYou.app (signed, notarized, stapled)
set -eu

VERSION="${1:?usage: $0 <version>}"

: "${KY_SIGN_IDENTITY:?set KY_SIGN_IDENTITY to your 'Developer ID Application: ...' identity}"
: "${KY_TEAM_ID:?set KY_TEAM_ID to your Apple Developer Team ID}"
: "${KY_NOTARY_PROFILE:?set KY_NOTARY_PROFILE to a notarytool keychain profile name (see script header)}"

SCHEME="KnowingYou"
BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/KnowingYou-$VERSION.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
EXPORT_PLIST="$BUILD_DIR/ExportOptions.plist"

mkdir -p "$BUILD_DIR"

cat > "$EXPORT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>developer-id</string>
	<key>teamID</key>
	<string>$KY_TEAM_ID</string>
	<key>signingStyle</key>
	<string>manual</string>
	<key>signingCertificate</key>
	<string>$KY_SIGN_IDENTITY</string>
</dict>
</plist>
PLIST

echo "sign-and-notarize: archiving (Release, $KY_SIGN_IDENTITY)..."
xcodebuild archive \
	-scheme "$SCHEME" \
	-configuration Release \
	-archivePath "$ARCHIVE_PATH" \
	-destination 'generic/platform=macOS' \
	CODE_SIGN_IDENTITY="$KY_SIGN_IDENTITY" \
	DEVELOPMENT_TEAM="$KY_TEAM_ID" \
	CODE_SIGN_STYLE=Manual

echo "sign-and-notarize: exporting signed .app..."
rm -rf "$EXPORT_DIR"
xcodebuild -exportArchive \
	-archivePath "$ARCHIVE_PATH" \
	-exportPath "$EXPORT_DIR" \
	-exportOptionsPlist "$EXPORT_PLIST"

APP_PATH="$EXPORT_DIR/KnowingYou.app"

echo "sign-and-notarize: verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "sign-and-notarize: zipping for notarization submission..."
NOTARIZE_ZIP="$BUILD_DIR/KnowingYou-$VERSION-notarize.zip"
rm -f "$NOTARIZE_ZIP"
ditto -c -k --keepParent "$APP_PATH" "$NOTARIZE_ZIP"

echo "sign-and-notarize: submitting to notarytool (profile: $KY_NOTARY_PROFILE)..."
xcrun notarytool submit "$NOTARIZE_ZIP" --keychain-profile "$KY_NOTARY_PROFILE" --wait

echo "sign-and-notarize: stapling ticket..."
xcrun stapler staple "$APP_PATH"

echo "sign-and-notarize: verifying with spctl..."
spctl -a -vv "$APP_PATH"

echo "sign-and-notarize: OK -> $APP_PATH"
