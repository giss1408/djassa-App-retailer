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
# Never commit the .jks or the password. To test a password later, use
# scripts/check-signing-key.sh (not keytool's own prompt).
set -euo pipefail

ALIAS="djassa-merchant"
OUT="${HOME}/djassa-merchant-release.jks"

if [ -e "$OUT" ]; then
  echo "error: $OUT already exists. Reuse it; creating a new key breaks updates." >&2
  exit 1
fi
command -v keytool >/dev/null || { echo "error: keytool not found; install a JDK (e.g. Android Studio's)." >&2; exit 1; }

echo "Press Enter to generate a strong password (recommended), or type your own."
read -r -s -p "Keystore password: " PASS; echo
if [ -z "$PASS" ]; then
  # Letters and digits only: nothing a terminal, keyboard layout, properties
  # file or GitHub secret can mangle.
  # `|| true`: under pipefail, tr is killed by SIGPIPE once head has its 32
  # characters, which would otherwise abort the script right here.
  PASS="$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32 || true)"
  [ ${#PASS} -eq 32 ] || { echo "error: could not generate a password." >&2; exit 1; }
  echo
  echo "Generated password (save it in your password manager NOW, it is shown once):"
  echo
  echo "    $PASS"
  echo
else
  [ ${#PASS} -ge 16 ] || { echo "error: use at least 16 characters." >&2; exit 1; }
  case "$PASS" in *[!\ -~]*) echo "error: use plain ASCII (no accents): some terminals and tools encode them differently." >&2; exit 1 ;; esac
  # Typing is hidden, so ask twice: a typo here becomes the key's password and
  # nobody finds out until the build fails.
  read -r -s -p "Type it again: " PASS2; echo
  [ "$PASS" = "$PASS2" ] || { echo "error: the two passwords differ; nothing was created." >&2; exit 1; }
  unset PASS2
fi

keytool -genkeypair -v -keystore "$OUT" -alias "$ALIAS" \
  -keyalg RSA -keysize 4096 -validity 10000 \
  -storepass "$PASS" -keypass "$PASS" \
  -dname "CN=Djassa marchand, O=Djassa, L=Abidjan, C=CI" >/dev/null

# Prove the password opens the new key before anyone relies on it.
keytool -list -keystore "$OUT" -storepass "$PASS" -alias "$ALIAS" >/dev/null \
  || { echo "error: the new keystore does not open with that password; removing it." >&2; rm -f "$OUT"; exit 1; }

echo
echo "Created $OUT and checked that the password opens it."
echo "Back it up now, with the password, in a password manager."
echo
echo "GitHub secrets to create in this repository:"
echo "  ANDROID_KEYSTORE_BASE64   = (copied to your clipboard below)"
echo "  ANDROID_KEYSTORE_PASSWORD = the password (shown above if generated)"
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
