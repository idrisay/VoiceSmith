#!/bin/bash
# Installs the latest VoiceSmith release into /Applications.
#
#   curl -fsSL https://raw.githubusercontent.com/idrisay/VoiceSmith/main/install.sh | bash
#
# What it does, in full: downloads the release .zip from GitHub, unpacks it,
# removes the quarantine flag macOS puts on anything downloaded, and launches
# the app. Removing the flag is the reason this exists — VoiceSmith is not
# notarised by Apple yet, so without it macOS refuses the first launch and
# sends you to System Settings › Privacy & Security to click Open Anyway.
#
# To undo everything: drag /Applications/VoiceSmith.app to the Trash and delete
# ~/Library/Application Support/VoiceSmith.
set -euo pipefail

REPO="idrisay/VoiceSmith"
ZIP_URL="https://github.com/$REPO/releases/latest/download/VoiceSmith.zip"
APP_NAME="VoiceSmith.app"
MIN_MACOS=14

fail() { echo "error: $*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "VoiceSmith is macOS only."

MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[ "$MACOS_MAJOR" -ge "$MIN_MACOS" ] || \
  fail "VoiceSmith needs macOS $MIN_MACOS or later (this is $(sw_vers -productVersion))."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> downloading the latest release"
curl -fL# -o "$TMP/VoiceSmith.zip" "$ZIP_URL" \
  || fail "download failed. Check https://github.com/$REPO/releases for a published release."

echo "==> unpacking"
# ditto, not `unzip`: it keeps the code signature intact, and macOS ties
# microphone and Accessibility grants to that signature.
ditto -x -k "$TMP/VoiceSmith.zip" "$TMP/unpacked" || fail "the download was not a readable archive."
[ -d "$TMP/unpacked/$APP_NAME" ] || fail "the archive did not contain $APP_NAME."

# A copy already running would keep its old code loaded and register the
# dictation shortcut twice.
if pgrep -x VoiceSmith >/dev/null 2>&1; then
  echo "==> quitting the running copy"
  pkill -x VoiceSmith || true
  sleep 1
fi

# /Applications is group-writable by admin on a stock Mac, so this usually
# needs no password. Only ask for one when it genuinely isn't writable.
DEST="/Applications"
if [ -w "$DEST" ]; then
  SUDO=""
else
  echo "==> $DEST needs an administrator password"
  SUDO="sudo"
fi

echo "==> installing to $DEST/$APP_NAME"
$SUDO rm -rf "${DEST:?}/$APP_NAME"
$SUDO ditto "$TMP/unpacked/$APP_NAME" "$DEST/$APP_NAME"

# The point of the whole script. Without this macOS blocks the first launch.
$SUDO xattr -dr com.apple.quarantine "$DEST/$APP_NAME" 2>/dev/null || true

echo "==> launching"
open "$DEST/$APP_NAME"

cat <<'DONE'

Installed. VoiceSmith lives in your menu bar — there is no Dock icon and no
window, which is expected.

A setup assistant should be on screen now. It asks for microphone access and
for Accessibility (System Settings › Privacy & Security › Accessibility), which
is what lets VoiceSmith type into whichever app you are using.

Then: double-tap Shift, speak, double-tap Shift again.
DONE
