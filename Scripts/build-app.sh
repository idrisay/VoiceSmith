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

# Ad-hoc signature. Enough for local use — macOS keys microphone, speech, and
# Accessibility grants to the signed bundle, so an unsigned build would re-prompt
# on every launch. Distribution needs a Developer ID identity and notarisation.
echo "==> codesign (ad-hoc)"
codesign --force --deep --sign - \
  --identifier com.voicesmith.app \
  "$APP" >/dev/null 2>&1

echo "==> built $APP"

if [ "$RUN" = "yes" ]; then
  echo "==> launching"
  # Replace a running copy so the shortcut isn't registered twice.
  pkill -x VoiceSmith 2>/dev/null || true
  sleep 0.3
  open "$APP"
fi
