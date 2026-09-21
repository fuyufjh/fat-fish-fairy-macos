#!/bin/bash
# One-time local identity setup. Only the public certificate is stored in the repo.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CERT="$ROOT/signing/FatFishFairy.cer"
if [ -f "$CERT" ]; then
  echo "Public certificate already exists. Restore its private key to the login keychain; do not generate a replacement identity."
  exit 1
fi
umask 077
WORK="$(mktemp -d "${TMPDIR:-/tmp}/fatfish-signing.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/cert.conf" <<'CONF'
[req]
prompt = no
distinguished_name = subject
x509_extensions = signing
[subject]
CN = FatFishFairy Local Code Signing
[signing]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
CONF
openssl req -new -newkey rsa:3072 -nodes -x509 -sha256 -days 3650 \
  -config "$WORK/cert.conf" -keyout "$WORK/private.key" -out "$WORK/cert.pem" 2> "$WORK/openssl.log"
openssl rand -hex 32 > "$WORK/password"
openssl pkcs12 -export -inkey "$WORK/private.key" -in "$WORK/cert.pem" \
  -name 'FatFishFairy Local Code Signing' -out "$WORK/identity.p12" -passout "file:$WORK/password"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$(cat "$WORK/password")" -T /usr/bin/codesign
mkdir -p "$ROOT/signing"
openssl x509 -in "$WORK/cert.pem" -outform DER -out "$CERT"
chmod 644 "$CERT"
echo "Private key imported into login keychain. Public certificate: $CERT"
