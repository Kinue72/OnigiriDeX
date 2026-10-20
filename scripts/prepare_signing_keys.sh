#!/usr/bin/env bash

set -eo pipefail
umask 077

SRC_DIR="${SRC_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)}"
SECURITY_DIR="$SRC_DIR/security"
mkdir -p "$SECURITY_DIR"

# PREPARE_KEY <name> <rsa bits> <subject>
PREPARE_KEY()
{
    local KEY="$SECURITY_DIR/onigiri_$1.pk8"
    local CERT="$SECURITY_DIR/onigiri_$1.x509.pem"

    if [ -f "$KEY" ] && [ -f "$CERT" ]; then
        KEY_PUBLIC="$(openssl pkey -inform DER -in "$KEY" -pubout 2>/dev/null)"
        CERT_PUBLIC="$(openssl x509 -in "$CERT" -pubkey -noout)"
        [ "$KEY_PUBLIC" = "$CERT_PUBLIC" ] || {
            echo "Onigiri $1 signing certificate does not match the private key." >&2
            exit 1
        }
        chmod 600 "$KEY"
        return 0
    elif [ -e "$KEY" ] || [ -e "$CERT" ]; then
        echo "Incomplete Onigiri $1 signing key pair; restore the original pair before building." >&2
        exit 1
    fi

    STAGE="$(mktemp -d "$SECURITY_DIR/.signing.XXXXXX")"
    trap 'rm -rf "$STAGE"' EXIT
    openssl req -new -x509 -newkey "rsa:$2" -nodes -sha256 -days 3650 \
        -subj "$3" -keyout "$STAGE/private.pem" -out "$STAGE/certificate.pem" 2>/dev/null
    openssl pkcs8 -topk8 -nocrypt -in "$STAGE/private.pem" -outform DER -out "$STAGE/private.pk8"
    mv "$STAGE/private.pk8" "$KEY"
    mv "$STAGE/certificate.pem" "$CERT"
    chmod 644 "$CERT"
    rm -rf "$STAGE"
}

PREPARE_KEY platform 4096 /CN=Onigiri/
# Recovery only trusts packages signed with this key (otacerts.zip). Same RSA-2048 as
# Samsung's own OTA signer, which its recovery is known to accept.
PREPARE_KEY ota 2048 "/CN=Onigiri OTA/"
