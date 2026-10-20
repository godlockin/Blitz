#!/bin/bash
# Create a local Code Signing identity so Accessibility TCC survives rebuilds.
#
# Uses a dedicated keychain with a known password so `codesign` does NOT prompt
# for the login-keychain password on every `make install`.
set -euo pipefail

NAME="${1:-Blitz Dev}"
KC_NAME="blitz-codesign.keychain-db"
KC_PATH="${HOME}/Library/Keychains/${KC_NAME}"
KC_PASS="blitz"
WORKDIR="$(mktemp -d /tmp/blitz-codesign.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT
cd "$WORKDIR"

cat > openssl.cnf <<EOF
[req]
distinguished_name = req_distinguished_name
prompt = no
x509_extensions = codesign_ext

[req_distinguished_name]
CN = ${NAME}
O = Blitz Local
C = US

[codesign_ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
EOF

openssl req -new -newkey rsa:2048 -nodes -keyout blitz.key -out blitz.csr -config openssl.cnf >/dev/null 2>&1
openssl x509 -req -days 3650 -in blitz.csr -signkey blitz.key -out blitz.crt \
  -extfile openssl.cnf -extensions codesign_ext >/dev/null 2>&1

# macOS security prefers legacy PKCS#12 from OpenSSL 3
if ! openssl pkcs12 -export -inkey blitz.key -in blitz.crt -out blitz.p12 \
    -passout pass:blitz -name "$NAME" -legacy 2>/dev/null; then
  openssl pkcs12 -export -inkey blitz.key -in blitz.crt -out blitz.p12 \
    -passout pass:blitz -name "$NAME" \
    -macalg sha1 -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES
fi

# Dedicated keychain — password is local-only "blitz", never the login password.
if [[ ! -f "$KC_PATH" ]]; then
  security create-keychain -p "$KC_PASS" "$KC_NAME"
fi
security set-keychain-settings -lut 21600 "$KC_PATH" >/dev/null 2>&1 || true
security unlock-keychain -p "$KC_PASS" "$KC_PATH"

# Prefer blitz keychain first so codesign finds this identity without UI.
EXISTING="$(security list-keychains -d user | tr -d '"')"
if ! echo "$EXISTING" | grep -F "$KC_PATH" >/dev/null; then
  # shellcheck disable=SC2086
  security list-keychains -d user -s "$KC_PATH" $EXISTING
fi

security import blitz.p12 -k "$KC_PATH" -P blitz -A \
  -T /usr/bin/codesign -T /usr/bin/security >/dev/null

# Allow codesign to use the private key without prompting (needs real keychain password).
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PASS" "$KC_PATH" >/dev/null

# Trust for code signing (may ask once for *admin* password — not every upgrade).
security add-trusted-cert -d -r trustRoot -k "$KC_PATH" blitz.crt 2>/dev/null || true

if security find-identity -p codesigning -v "$KC_PATH" 2>/dev/null | grep -F "$NAME" >/dev/null; then
  echo "Created valid identity: $NAME"
  echo "Keychain: $KC_PATH (password: blitz — local only, unlocks silently for codesign)"
  security find-identity -p codesigning -v "$KC_PATH" | grep -F "$NAME"
else
  echo "Import finished but identity not yet valid. In Keychain Access → My Certificates →"
  echo "  $NAME → Get Info → Trust → Code Signing: Always Trust"
  exit 1
fi
