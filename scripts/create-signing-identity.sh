#!/usr/bin/env bash
# Create a stable self-signed code signing identity in the login keychain.
#
# Keychain access control lists are tied to the signing identity of the app that
# created them. Ad-hoc signing produces a fresh identity on every build, so each
# reinstall looks like a different app and macOS asks for the keychain password
# again. Signing every build with one long-lived certificate keeps the identity
# stable, so "Always Allow" is answered once and holds.
set -euo pipefail

IDENTITY_NAME="${1:-Notchi Local Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

if security find-certificate -c "$IDENTITY_NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "Identity \"$IDENTITY_NAME\" already exists."
    exit 0
fi

# The system openssl is LibreSSL, which cannot write the PKCS#12 encoding
# Security.framework reads; prefer Homebrew's OpenSSL 3 when it is installed.
OPENSSL="$(command -v openssl)"
for candidate in /opt/homebrew/opt/openssl@3/bin/openssl /usr/local/opt/openssl@3/bin/openssl; do
    if [[ -x "$candidate" ]]; then OPENSSL="$candidate"; break; fi
done
P12_FLAGS=()
if "$OPENSSL" pkcs12 -help 2>&1 | grep -q -- '-legacy'; then
    P12_FLAGS+=(-legacy)
fi

echo "==> Generating certificate (using $OPENSSL)"
cat > "$WORK_DIR/openssl.cnf" <<EOF
[ req ]
distinguished_name = dn
prompt = no
x509_extensions = ext

[ dn ]
CN = $IDENTITY_NAME

[ ext ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
1.2.840.113635.100.6.1.14 = critical,DER:0500
EOF

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes \
    -keyout "$WORK_DIR/key.pem" -out "$WORK_DIR/cert.pem" \
    -days 3650 -config "$WORK_DIR/openssl.cnf" 2>/dev/null

# Security.framework cannot read the PKCS#12 MAC that OpenSSL 3 writes by
# default, and it rejects an empty password outright, so use the legacy
# encoding with a throwaway passphrase.
P12_PASSWORD="notchi-local"
"$OPENSSL" pkcs12 -export "${P12_FLAGS[@]}" -inkey "$WORK_DIR/key.pem" -in "$WORK_DIR/cert.pem" \
    -out "$WORK_DIR/identity.p12" -passout "pass:$P12_PASSWORD" -name "$IDENTITY_NAME" 2>/dev/null

echo "==> Importing into the login keychain"
# codesign is allowed to use the private key without further prompting.
security import "$WORK_DIR/identity.p12" -k "$KEYCHAIN" -P "$P12_PASSWORD" \
    -T /usr/bin/codesign -T /usr/bin/security >/dev/null

echo "==> Trusting it for code signing (may ask for your login password)"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK_DIR/cert.pem"

# Without this, codesign stops to ask for keychain access on every build.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" "$KEYCHAIN" >/dev/null 2>&1 || true

echo
echo "Done. \"$IDENTITY_NAME\" is now available:"
security find-identity -v -p codesigning | grep "$IDENTITY_NAME" || true
echo
echo "Run ./scripts/install.sh — it picks the identity up automatically."
echo "macOS asks for the keychain password once more; choose Always Allow."
