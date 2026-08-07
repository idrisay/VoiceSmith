#!/bin/bash
# Packages VoiceSmith.app for people to download.
#
#   ./Scripts/release.sh
#
# Produces two files in dist/, both from the same build:
#
#   VoiceSmith-<version>.dmg   drag-to-Applications image, for humans
#   VoiceSmith.zip             fixed name, so the GitHub "latest" URL that
#                              install.sh downloads never changes
#
# Resources/Info.plist is the single source of truth for the version. Bump
# CFBundleShortVersionString there, commit, then tag — .github/workflows/
# release.yml refuses to publish if the tag and the plist disagree.
#
# Signing, and why the downloads look the way they do:
#
#   By default this signs ad-hoc, which is enough to run but not enough for
#   Gatekeeper. Users get "Apple could not verify VoiceSmith" and have to go to
#   System Settings › Privacy & Security › Open Anyway. install.sh sidesteps
#   that by removing the quarantine flag itself.
#
#   Set DEVELOPER_ID to a "Developer ID Application: …" identity and the app is
#   signed for real, with the hardened runtime. Also set NOTARY_PROFILE to a
#   profile name from `xcrun notarytool store-credentials` and the results are
#   notarised and stapled — at which point the .dmg opens on a double click and
#   nobody has to visit System Settings at all:
#
#     DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \
#     NOTARY_PROFILE=voicesmith ./Scripts/release.sh
set -euo pipefail

cd "$(dirname "$0")/.."

APP="build/VoiceSmith.app"
DIST="dist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
DMG="$DIST/VoiceSmith-$VERSION.dmg"
ZIP="$DIST/VoiceSmith.zip"

echo "==> VoiceSmith $VERSION"

# Ad-hoc here regardless: a local "VoiceSmith Dev" certificate is trusted only
# on the machine that made it, so shipping one would be worse than shipping
# nothing. If DEVELOPER_ID is set the bundle is re-signed properly below.
VOICESMITH_SIGN_IDENTITY="-" ./Scripts/build-app.sh release universal

echo "==> architectures"
lipo -info "$APP/Contents/MacOS/VoiceSmith" | sed 's/^/    /'

if [ -n "${DEVELOPER_ID:-}" ]; then
  echo "==> codesign (Developer ID, hardened runtime)"
  # --deep is deprecated by Apple, and unnecessary: the bundle holds one
  # binary, so signing the bundle covers everything in it.
  codesign --force --timestamp --options runtime \
    --entitlements Resources/VoiceSmith.entitlements \
    --sign "$DEVELOPER_ID" \
    --identifier com.voicesmith.app \
    "$APP"
else
  echo "==> codesign: ad-hoc (set DEVELOPER_ID to sign for distribution)"
fi

codesign --verify --strict --verbose=1 "$APP"

# Notarisation works on an archive, not a bundle, and the ticket is stapled
# back onto the .app afterwards — so this has to happen before the .zip and
# .dmg that ship are built, or they would carry an unstapled copy.
if [ -n "${NOTARY_PROFILE:-}" ]; then
  if [ -z "${DEVELOPER_ID:-}" ]; then
    echo "error: NOTARY_PROFILE is set but DEVELOPER_ID is not." >&2
    echo "       Apple only notarises Developer ID signatures." >&2
    exit 1
  fi
  NOTARIZE_ZIP="$(mktemp -d)/VoiceSmith.zip"
  ditto -c -k --keepParent "$APP" "$NOTARIZE_ZIP"
  echo "==> notarising the app (this waits on Apple, usually a few minutes)"
  xcrun notarytool submit "$NOTARIZE_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
fi

rm -rf "$DIST"
mkdir -p "$DIST"

# ditto, not `zip`: it preserves the code signature and resource forks.
echo "==> $ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> $DMG"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
# The symlink is what makes the window a drag-and-drop target.
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "VoiceSmith $VERSION" \
  -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"

if [ -n "${NOTARY_PROFILE:-}" ]; then
  echo "==> notarising the disk image"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

echo
echo "==> done"
ls -lh "$DIST" | tail -n +2 | sed 's/^/    /'
echo
# spctl is the same check Gatekeeper runs on a double click, so this reports
# what a user will actually experience rather than what we hoped for.
if spctl --assess --type execute "$APP" >/dev/null 2>&1; then
  echo "    Gatekeeper: accepted — this opens on a double click."
else
  echo "    Gatekeeper: rejected — expected without DEVELOPER_ID + NOTARY_PROFILE."
  echo "    Users double-clicking the .dmg will need System Settings ›"
  echo "    Privacy & Security › Open Anyway. install.sh avoids that."
fi
