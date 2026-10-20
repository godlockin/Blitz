#!/bin/bash
# One-time: stop login-keychain password prompts on every `codesign` / `make install`.
#
# Cause: Blitz Dev's private key lives in login.keychain; without a partition ACL,
# macOS asks for your *login keychain* password each time codesign uses it.
set -euo pipefail

NAME="${1:-Blitz Dev}"
LOGIN_KC="${HOME}/Library/Keychains/login.keychain-db"

if ! security find-identity -p codesigning -v 2>/dev/null | grep -F "$NAME" >/dev/null; then
  echo "No '$NAME' identity — run: make signing-cert" >&2
  exit 1
fi

echo "This updates the ACL on '$NAME' so /usr/bin/codesign can use it without prompting."
echo "Enter your macOS login keychain password (usually your account password)."
echo -n "Login keychain password: "
read -rs KC_PASS
echo

if ! security unlock-keychain -p "$KC_PASS" "$LOGIN_KC" 2>/dev/null; then
  echo "Wrong password or unlock failed." >&2
  exit 1
fi

# -A on partition list for the signing key; scoped to codesign tooling.
if ! security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PASS" "$LOGIN_KC" >/dev/null; then
  echo "set-key-partition-list failed." >&2
  exit 1
fi

echo "OK — codesign should no longer ask for a password."
echo "Try: cd blitz && make install"
