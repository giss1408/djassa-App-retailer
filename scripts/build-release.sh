#!/usr/bin/env bash
# Build the merchant APKs for distribution.
#
# Usage: scripts/build-release.sh https://api.djassa.ci
#
# Produces one APK per ARM ABI plus a universal APK for sideloading, with Dart
# obfuscation on and the symbol map kept in build/symbols/ so a crash report
# from the field can still be read. Archive that directory with the release.
set -euo pipefail

API_BASE="${1:-}"
if [ -z "$API_BASE" ]; then
  echo "usage: $0 <https api base url>" >&2
  exit 2
fi
case "$API_BASE" in
  https://*) ;;
  *) echo "error: API base must be https, got: $API_BASE" >&2; exit 2 ;;
esac

cd "$(dirname "$0")/.."

if [ ! -f android/key.properties ]; then
  echo "warning: android/key.properties is missing; the APKs will be UNSIGNED." >&2
  echo "         See android/key.properties.example. Do not distribute unsigned builds." >&2
fi

# No --split-per-abi here: the splits{} block in android/app/build.gradle
# already emits one APK per ABI plus the universal one. Passing both makes the
# Flutter tool look for a single app-release.apk and report a spurious failure.
flutter build apk --release \
  --obfuscate --split-debug-info=build/symbols \
  --dart-define=DJASSA_API_BASE="$API_BASE"

echo
echo "Artifacts:"
# Only the release APKs: the directory also holds debug builds from a previous
# `flutter run`, which are several times larger and must never be distributed.
ls -la build/app/outputs/flutter-apk/*release*.apk
echo
echo "Symbol maps (archive these, do not ship them): build/symbols/"
