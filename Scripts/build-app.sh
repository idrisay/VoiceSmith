#!/bin/bash
# Builds VoiceSmith.app from the SPM executable.
#
#   ./Scripts/build-app.sh            debug build
#   ./Scripts/build-app.sh release    optimised build
#   ./Scripts/build-app.sh release run   build, then launch
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="debug"
RUN="no"
for arg in "$@"; do
  case "$arg" in
    release) CONFIG="release" ;;
    debug)   CONFIG="debug" ;;
    run)     RUN="yes" ;;
  esac
done

APP="build/VoiceSmith.app"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"
BINARY="$(swift build -c "$CONFIG" --show-bin-path)/VoiceSmith"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/VoiceSmith"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# macOS keys permission grants (Accessibility, microphone, speech) to the app's
# code signature. An ad-hoc signature is derived from the binary's contents, so
# it CHANGES ON EVERY BUILD — macOS then treats each rebuild as a different app
# and silently drops the grants, leaving a stale entry ticked in System Settings
# that no longer matches. That is why Accessibility keeps needing re-granting.
#
# A self-signed identity fixes it permanently: the signature stays stable across
# builds, so the grants stick. Create one with Scripts/create-signing-identity.sh.
IDENTITY="VoiceSmith Dev"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  echo "==> codesign ($IDENTITY — stable, permissions persist)"
  codesign --force --deep --sign "$IDENTITY" \
    --identifier com.voicesmith.app \
    "$APP" >/dev/null 2>&1
else
  echo "==> codesign (ad-hoc)"
  codesign --force --deep --sign - \
    --identifier com.voicesmith.app \
    "$APP" >/dev/null 2>&1
  echo "    note: ad-hoc signature changes every build, so macOS will ask for"
  echo "    Accessibility again after each rebuild. Run this once to stop that:"
  echo "      ./Scripts/create-signing-identity.sh"
fi

echo "==> built $APP"

if [ "$RUN" = "yes" ]; then
  echo "==> launching"
  # Replace a running copy so the shortcut isn't registered twice.
  pkill -x VoiceSmith 2>/dev/null || true
  sleep 0.3
  open "$APP"
fi
