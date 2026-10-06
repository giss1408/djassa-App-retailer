#!/usr/bin/env bash
# Run the app on a USB-connected Android device against a backend on this
# machine.
#
# Usage: scripts/run-device.sh [backend port]
#
# `adb reverse` makes the phone's own localhost:PORT tunnel back to this
# machine over USB. That beats putting a LAN IP in the build because it needs no
# shared Wi-Fi, survives the laptop changing networks, and the traffic never
# leaves the cable.
#
# (10.0.2.2 is emulator-only and does NOT work on a physical device.)
set -euo pipefail

PORT="${1:-8002}"
cd "$(dirname "$0")/.."

if ! adb get-state >/dev/null 2>&1; then
  echo "error: no device over adb. Enable USB debugging and check 'adb devices'." >&2
  exit 1
fi

echo "Tunnelling device localhost:$PORT -> this machine's $PORT"
adb reverse --remove-all >/dev/null 2>&1 || true
adb reverse "tcp:$PORT" "tcp:$PORT"

# Cleartext to localhost is permitted in debug builds only, and only for
# loopback (see android/app/src/debug/res/xml/network_security_config.xml).
#
# The sign-in form is prefilled with 0700000002, the seeded sample merchant
# (app/seed.py, DEV_MERCHANT_PHONE). Run the backend with OTP_DEV_ECHO=1 and
# the SMS code is filled in too. Override with HOSSOUKO_DEV_PHONE.
exec flutter run \
  --dart-define=HOSSOUKO_API_BASE="http://localhost:$PORT" \
  --dart-define=HOSSOUKO_DEV_PHONE="${HOSSOUKO_DEV_PHONE:-0700000002}"
