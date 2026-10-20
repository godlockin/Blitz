#!/bin/bash
# Unlock the Blitz codesign keychain so `codesign` never prompts for a password.
set -euo pipefail
KC_NAME="blitz-codesign.keychain-db"
KC_PATH="${HOME}/Library/Keychains/${KC_NAME}"
KC_PASS="blitz"

if [[ ! -f "$KC_PATH" ]]; then
  echo "No $KC_NAME — run: make signing-cert" >&2
  exit 1
fi

security unlock-keychain -p "$KC_PASS" "$KC_PATH"
security set-keychain-settings -lut 21600 "$KC_PATH" >/dev/null 2>&1 || true
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PASS" "$KC_PATH" >/dev/null 2>&1 || true

# Keep it on the search list (first).
EXISTING="$(security list-keychains -d user | tr -d '"')"
if ! echo "$EXISTING" | grep -F "$KC_PATH" >/dev/null; then
  # shellcheck disable=SC2086
  security list-keychains -d user -s "$KC_PATH" $EXISTING
else
  # Ensure blitz keychain is first.
  REST="$(echo "$EXISTING" | grep -vF "$KC_PATH" || true)"
  # shellcheck disable=SC2086
  security list-keychains -d user -s "$KC_PATH" $REST
fi
