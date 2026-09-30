#!/usr/bin/env bash
# Check that a password opens this app's signing key, the way the release
# workflow does (keytool -storepass), then copy the key for GitHub.
#
# Usage: scripts/check-signing-key.sh [path to .jks]
#
# Use this rather than keytool's own password prompt: that prompt reads the
# terminal differently and can reject a correct password containing accented
# or layout-dependent characters.
set -euo pipefail

ALIAS="djassa-merchant"
KEY="${1:-${HOME}/djassa-merchant-release.jks}"
[ -f "$KEY" ] || { echo "error: $KEY not found." >&2; exit 1; }

read -r -s -p "Password for $KEY: " PASS; echo

# Facts about the password that explain most mismatches, without showing it.
case "$PASS" in *[![:print:]]*|*[!\ -~]*) echo "note: the password contains non-ASCII or non-printable characters (accents, etc.)." ;; esac
case "$PASS" in " "*|*" ") echo "note: the password starts or ends with a space." ;; esac
echo "length: ${#PASS} characters"

if ! keytool -list -keystore "$KEY" -storepass "$PASS" >/dev/null 2>&1; then
  echo "FAIL: this password does not open $KEY." >&2
  exit 1
fi
if ! keytool -list -keystore "$KEY" -storepass "$PASS" -alias "$ALIAS" >/dev/null 2>&1; then
  echo "FAIL: the password is right, but the key has no alias '$ALIAS'. Aliases:" >&2
  keytool -list -keystore "$KEY" -storepass "$PASS" | grep -i privatekeyentry >&2 || true
  exit 1
fi
echo "OK: the password opens $KEY, alias $ALIAS. GitHub will accept it."
echo
echo "Set these secrets (Settings → Secrets and variables → Actions):"
echo "  ANDROID_KEYSTORE_PASSWORD = this password"
echo "  ANDROID_KEY_PASSWORD      = this password"
echo "  ANDROID_KEY_ALIAS         = $ALIAS"
if command -v pbcopy >/dev/null; then
  base64 < "$KEY" | tr -d '\n' | pbcopy
  echo "  ANDROID_KEYSTORE_BASE64   = now on your clipboard: paste it first."
fi
