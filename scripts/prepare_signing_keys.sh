#!/usr/bin/env bash

set -eo pipefail
umask 077

SRC_DIR="${SRC_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)}"
SECURITY_DIR="$SRC_DIR/security"
KEY="$SECURITY_DIR/onigiri_platform.pk8"
CERT="$SECURITY_DIR/onigiri_platform.x509.pem"
mkdir -p "$SECURITY_DIR"

if [ -f "$KEY" ] && [ -f "$CERT" ]; then
    KEY_PUBLIC="$(openssl pkey -inform DER -in "$KEY" -pubout 2>/dev/null)"
    CERT_PUBLIC="$(openssl x509 -in "$CERT" -pubkey -noout)"
    [ "$KEY_PUBLIC" = "$CERT_PUBLIC" ] || {
        echo "Onigiri signing certificate does not match the private key." >&2
        exit 1
    }
    chmod 600 "$KEY"
    exit 0
elif [ -e "$KEY" ] || [ -e "$CERT" ]; then
    echo "Incomplete Onigiri signing key pair; restore the original pair before building." >&2
    exit 1
fi

STAGE="$(mktemp -d "$SECURITY_DIR/.signing.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
openssl req -new -x509 -newkey rsa:4096 -nodes -sha256 -days 3650 \
    -subj /CN=Onigiri/ -keyout "$STAGE/private.pem" -out "$STAGE/certificate.pem" 2>/dev/null
openssl pkcs8 -topk8 -nocrypt -in "$STAGE/private.pem" -outform DER -out "$STAGE/private.pk8"
mv "$STAGE/private.pk8" "$KEY"
mv "$STAGE/certificate.pem" "$CERT"
chmod 644 "$CERT"
