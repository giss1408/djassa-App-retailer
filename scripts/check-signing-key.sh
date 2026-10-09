#!/usr/bin/env bash
# Check this app's signing key the way the release workflow does.
#
# Usage: scripts/check-signing-key.sh [path to .jks]
#
# Reads the password from the secrets file written by create-signing-key.sh,
# or from `pass`, and only asks as a last resort. It also checks that the
# base64 in the secrets file is this key (a clipboard mix-up between the two
# apps is the easiest mistake to make).
set -euo pipefail

ALIAS="fidelia-merchant"
KEY="${1:-${HOME}/fidelia-merchant-release.jks}"
SECRETS="${HOME}/fidelia-merchant-github-secrets.txt"
[ -f "$KEY" ] || { echo "error: $KEY not found." >&2; exit 1; }

# Drop what pasting can add: bracketed-paste markers, control characters,
# surrounding whitespace.
clean() { printf '%s' "$1" | sed $'s/\x1b\\[20[01]~//g' | LC_ALL=C tr -d '\000-\037\177' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'; }

SOURCE=""
if [ -f "$SECRETS" ]; then
  PASS="$(grep '^ANDROID_KEYSTORE_PASSWORD=' "$SECRETS" | cut -d= -f2-)"; SOURCE="$SECRETS"
elif command -v pass >/dev/null 2>&1 && pass show "android/fidelia-merchant-password" >/dev/null 2>&1; then
  PASS="$(pass show "android/fidelia-merchant-password" | head -1)"; SOURCE="pass android/fidelia-merchant-password"
else
  read -r -s -p "Password for $KEY: " RAW; echo
  PASS="$(clean "$RAW")"; SOURCE="typed"
  [ "$PASS" != "$RAW" ] && echo "note: removed invisible characters or spaces from what was typed or pasted."
fi
echo "password from: $SOURCE (${#PASS} characters)"

if ! keytool -list -keystore "$KEY" -storepass "$PASS" >/dev/null 2>&1; then
  echo "FAIL: this password does not open $KEY." >&2
  echo "      If the key was made by an older version of the script and its password is lost," >&2
  echo "      and the app was never released: mv $KEY $KEY.OLD && scripts/create-signing-key.sh" >&2
  exit 1
fi
if ! keytool -list -keystore "$KEY" -storepass "$PASS" -alias "$ALIAS" >/dev/null 2>&1; then
  echo "FAIL: the password is right, but the key has no alias '$ALIAS'." >&2
  exit 1
fi
echo "OK: the password opens $KEY, alias $ALIAS."

if [ -f "$SECRETS" ]; then
  B64="$(grep '^ANDROID_KEYSTORE_BASE64=' "$SECRETS" | cut -d= -f2-)"
  if [ "$B64" = "$(base64 < "$KEY" | tr -d '\n')" ]; then
    echo "OK: ANDROID_KEYSTORE_BASE64 in $SECRETS is this key."
  else
    echo "FAIL: ANDROID_KEYSTORE_BASE64 in $SECRETS is NOT this key." >&2; exit 1
  fi
fi
echo "GitHub will accept these secrets, provided they are pasted exactly."
