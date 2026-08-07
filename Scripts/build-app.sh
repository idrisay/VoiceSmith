#!/bin/bash
# Builds VoiceSmith.app from the SPM executable.
#
#   ./Scripts/build-app.sh            debug build
#   ./Scripts/build-app.sh release    optimised build
#   ./Scripts/build-app.sh release run   build, then launch
#   ./Scripts/build-app.sh release universal   Intel + Apple Silicon
#
# Scripts/release.sh drives this to produce what ships; it passes `universal`
# and sets VOICESMITH_SIGN_IDENTITY, then re-signs with release settings.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="debug"
RUN="no"
UNIVERSAL="no"
for arg in "$@"; do
  case "$arg" in
    release)   CONFIG="release" ;;
    debug)     CONFIG="debug" ;;
    run)       RUN="yes" ;;
    universal) UNIVERSAL="yes" ;;
  esac
done

APP="build/VoiceSmith.app"
# Keep in step with `platforms:` in Package.swift and LSMinimumSystemVersion
# in Resources/Info.plist.
DEPLOYMENT_TARGET="14.0"

build_one() {
  # --triple, not --arch. Both cross-compile, but --arch switches SwiftPM to
  # Xcode's build system, which reads swiftLanguageMode(.v5) out of
  # Package.swift as an empty SWIFT_VERSION on Xcode 16 and dies with
  # "duplicate output file". --triple stays on SwiftPM's own build system,
  # which handles it on every toolchain we build with.
  swift build -c "$CONFIG" --triple "$1-apple-macosx$DEPLOYMENT_TARGET" >&2
  swift build -c "$CONFIG" --triple "$1-apple-macosx$DEPLOYMENT_TARGET" --show-bin-path
}

if [ "$UNIVERSAL" = "yes" ]; then
  echo "==> swift build -c $CONFIG (arm64 + x86_64)"
  ARM64_BIN="$(build_one arm64)/VoiceSmith"
  X86_64_BIN="$(build_one x86_64)/VoiceSmith"
  BINARY="build/VoiceSmith.universal"
  mkdir -p build
  lipo -create "$ARM64_BIN" "$X86_64_BIN" -output "$BINARY"
else
  echo "==> swift build -c $CONFIG"
  swift build -c "$CONFIG"
  BINARY="$(swift build -c "$CONFIG" --show-bin-path)/VoiceSmith"
fi

if [ ! -f "$BINARY" ]; then
  echo "error: swift build reported $BINARY but nothing is there" >&2
  exit 1
fi

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
if [ -n "${VOICESMITH_SIGN_IDENTITY:-}" ]; then
  # release.sh signs on its own terms and doesn't want a local developer
  # certificate baked into something other people download.
  echo "==> codesign ($VOICESMITH_SIGN_IDENTITY)"
  codesign --force --sign "$VOICESMITH_SIGN_IDENTITY" \
    --identifier com.voicesmith.app \
    "$APP" >/dev/null 2>&1
elif security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
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
