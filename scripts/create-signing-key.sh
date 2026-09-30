#!/usr/bin/env bash
# Create this app's release signing key, once, and print what GitHub needs.
#
# Usage: scripts/create-signing-key.sh
#
# The key is what lets testers install an UPDATE over the previous version:
# Android refuses an update signed with a different key. Lose it and every
# tester must uninstall and reinstall. So:
#   1. Run this once, on your own machine (needs a JDK for keytool).
#   2. Save the .jks file and the password in a password manager.
#   3. Paste the four printed values into GitHub: repository Settings →
#      Secrets and variables → Actions → New repository secret.
# Never commit the .jks or the password.
set -euo pipefail

ALIAS="djassa-merchant"
OUT="${HOME}/djassa-merchant-release.jks"

if [ -e "$OUT" ]; then
  echo "error: $OUT already exists. Reuse it; creating a new key breaks updates." >&2
  exit 1
fi
command -v keytool >/dev/null || { echo "error: keytool not found; install a JDK (e.g. Android Studio's)." >&2; exit 1; }

read -r -s -p "Choose a keystore password (16+ characters): " PASS; echo
[ ${#PASS} -ge 16 ] || { echo "error: use at least 16 characters." >&2; exit 1; }

keytool -genkeypair -v -keystore "$OUT" -alias "$ALIAS" \
  -keyalg RSA -keysize 4096 -validity 10000 \
  -storepass "$PASS" -keypass "$PASS" \
  -dname "CN=Djassa marchand, O=Djassa, L=Abidjan, C=CI" >/dev/null

echo
echo "Created $OUT. Back it up now, with the password, in a password manager."
echo
echo "GitHub secrets to create in this repository:"
echo "  ANDROID_KEYSTORE_BASE64   = (copied to your clipboard below)"
echo "  ANDROID_KEYSTORE_PASSWORD = the password you just chose"
echo "  ANDROID_KEY_ALIAS         = $ALIAS"
echo "  ANDROID_KEY_PASSWORD      = the same password"
if command -v pbcopy >/dev/null; then
  base64 < "$OUT" | tr -d '\n' | pbcopy
  echo
  echo "ANDROID_KEYSTORE_BASE64 is on your clipboard: paste it into GitHub."
else
  echo
  echo "ANDROID_KEYSTORE_BASE64:"
  base64 < "$OUT" | tr -d '\n'; echo
fi
