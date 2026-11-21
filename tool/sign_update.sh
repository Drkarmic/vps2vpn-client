#!/usr/bin/env bash
# Sign vps2vpn client installers for the in-app update check: writes <file>.sig next to each file.
# The app verifies the Ed25519 signature over
#   "vps2vpn-update-v1\n<file name>\n<sha256 hex>\n<size in bytes>\n"
# with the public key built into it (lib/vps2vpn/update_signing.dart).
# usage: UPDATE_SIGNING_KEY=key.pem tool/sign_update.sh file...   (or: tool/sign_update.sh -k key.pem file...)
set -euo pipefail
KEY=${UPDATE_SIGNING_KEY:-}
if [ "${1:-}" = -k ]; then KEY=$2; shift 2; fi
[ -r "$KEY" ] || { echo "signing key not found: $KEY" >&2; exit 1; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for f in "$@"; do
  name=$(basename "$f")
  sum=$(sha256sum "$f" | cut -d' ' -f1)
  size=$(stat -c %s "$f")
  printf 'vps2vpn-update-v1\n%s\n%s\n%s\n' "$name" "$sum" "$size" > "$tmp/statement"
  openssl pkeyutl -sign -inkey "$KEY" -rawin -in "$tmp/statement" -out "$tmp/sig"
  base64 -w0 "$tmp/sig" > "$f.sig"
  echo >> "$f.sig"
  echo "signed $name ($size bytes, sha256 $sum)"
done
