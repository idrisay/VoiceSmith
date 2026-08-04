#!/bin/bash
# Creates a self-signed code-signing identity for local development.
#
# Why this exists: macOS ties permission grants — Accessibility, microphone,
# speech recognition — to an app's code signature. An ad-hoc signature is
# derived from the binary's contents, so it changes on every build. macOS then
# treats each rebuild as a different app and drops the grants, while leaving a
# stale, still-ticked entry in System Settings that no longer matches anything.
# The symptom is Accessibility that "is already enabled" but doesn't work.
#
# A self-signed certificate gives the app a stable identity, so grants persist
# across rebuilds. Run this once.
#
# Everything it creates is local to your login keychain and undoable:
#   security delete-certificate -c "VoiceSmith Dev"
set -euo pipefail

NAME="VoiceSmith Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$NAME"; then
  echo "Identity \"$NAME\" already exists — nothing to do."
  echo "Rebuild with ./Scripts/build-app.sh and it will be used automatically."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# codeSigning extended key usage is what makes the cert usable by `codesign`.
cat > "$TMP/openssl.cnf" <<'CONF'
[ req ]
distinguished_name = dn
x509_extensions    = ext
prompt             = no

[ dn ]
CN = VoiceSmith Dev

[ ext ]
basicConstraints     = critical,CA:false
keyUsage             = critical,digitalSignature
extendedKeyUsage     = critical,codeSigning
CONF

echo "==> generating a self-signed code-signing certificate"
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -config "$TMP/openssl.cnf" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" >/dev/null 2>&1

openssl pkcs12 -export -legacy \
  -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/identity.p12" -passout pass: >/dev/null 2>&1 \
  || openssl pkcs12 -export \
       -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
       -out "$TMP/identity.p12" -passout pass: >/dev/null 2>&1

echo "==> importing into your login keychain"
echo "    (macOS may ask for your password, and whether to allow codesign access)"
security import "$TMP/identity.p12" \
  -k "$KEYCHAIN" \
  -P "" \
  -T /usr/bin/codesign

# Let codesign use the key without prompting on every build.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" "$KEYCHAIN" >/dev/null 2>&1 || true

echo
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$NAME"; then
  echo "Done. \"$NAME\" is now available for signing."
  echo
  echo "Next:"
  echo "  1. ./Scripts/build-app.sh release run"
  echo "  2. Remove VoiceSmith from System Settings › Privacy & Security ›"
  echo "     Accessibility (select it, click −), then add it again with +."
  echo
  echo "From then on the grant survives rebuilds."
else
  echo "The certificate was created but isn't showing as a codesigning identity."
  echo "Open Keychain Access, find \"$NAME\", and set its trust for Code Signing"
  echo "to \"Always Trust\"."
  exit 1
fi
