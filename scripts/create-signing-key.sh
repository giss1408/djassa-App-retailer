#!/usr/bin/env bash
# Create this app's release signing key, once, and write the GitHub secrets
# to a private file. Asks for nothing: no password is typed or pasted, so no
# terminal can mangle it.
#
# Usage: scripts/create-signing-key.sh
#
# The key is what lets testers install an UPDATE over the previous version:
# Android refuses an update signed with another key. So after running this:
#   1. Copy the four values from the secrets file into GitHub: repository
#      Settings → Secrets and variables → Actions → New repository secret.
#   2. Keep the .jks and its password in a password manager (done for you if
#      `pass` is installed), then delete the secrets file.
#   3. Check anytime with scripts/check-signing-key.sh.
# Never commit the .jks, the password or the secrets file.
set -euo pipefail

ALIAS="hossouko-merchant"
OUT="${HOME}/hossouko-merchant-release.jks"
SECRETS="${HOME}/hossouko-merchant-github-secrets.txt"

if [ -e "$OUT" ]; then
  echo "error: $OUT already exists. Reuse it (creating a new key breaks updates for testers)," >&2
  echo "       or move it aside first if this app was never released." >&2
  exit 1
fi
command -v keytool >/dev/null || { echo "error: keytool not found; install a JDK (e.g. Android Studio's)." >&2; exit 1; }

# 32 letters and digits: nothing a terminal, keyboard layout, properties file
# or GitHub secret can alter. `|| true`: under pipefail, tr is killed by
# SIGPIPE once head has its 32 characters.
PASS="$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32 || true)"
[ ${#PASS} -eq 32 ] || { echo "error: could not generate a password." >&2; exit 1; }

keytool -genkeypair -keystore "$OUT" -alias "$ALIAS" \
  -keyalg RSA -keysize 4096 -validity 10000 \
  -storepass "$PASS" -keypass "$PASS" \
  -dname "CN=Hossouko marchand, O=Hossouko, L=Abidjan, C=CI" >/dev/null 2>&1

# Prove the password opens the new key, exactly as the release workflow will.
keytool -list -keystore "$OUT" -storepass "$PASS" -alias "$ALIAS" >/dev/null 2>&1 \
  || { echo "error: the new keystore does not open with its password; removing it." >&2; rm -f "$OUT"; exit 1; }
chmod 600 "$OUT"

B64="$(base64 < "$OUT" | tr -d '\n')"
( umask 077
  {
    echo "# GitHub → hossouko repository → Settings → Secrets and variables → Actions."
    echo "# Copy each value after the '=' (nothing else). Delete this file afterwards."
    echo "ANDROID_KEYSTORE_PASSWORD=$PASS"
    echo "ANDROID_KEY_PASSWORD=$PASS"
    echo "ANDROID_KEY_ALIAS=$ALIAS"
    echo "ANDROID_KEYSTORE_BASE64=$B64"
  } > "$SECRETS" )

echo "Created $OUT and checked that its password opens it."
echo "GitHub secrets written to $SECRETS (readable only by you)."

if command -v pass >/dev/null 2>&1; then
  printf '%s\n' "$B64" | pass insert -m -f "android/hossouko-merchant-jks" >/dev/null
  printf '%s\n' "$PASS" | pass insert -m -f "android/hossouko-merchant-password" >/dev/null
  echo "Backed up in pass: android/hossouko-merchant-jks and android/hossouko-merchant-password."
else
  echo "Back up $OUT and the password in your password manager now."
fi

echo
echo "Next:"
echo "  1. open $SECRETS and copy the 4 values into GitHub (Update each secret)"
echo "  2. scripts/check-signing-key.sh     # must say OK"
echo "  3. rm $SECRETS"
