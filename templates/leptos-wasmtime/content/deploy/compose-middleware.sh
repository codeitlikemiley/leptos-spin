#!/usr/bin/env bash
# Wasmtime precompose path for the fused secure-defaults component.
# Spin 4.2.5 should use spin.middleware.toml (`dependencies.middleware`)
# instead of this script. Do not serve the output of this script with that
# manifest: the host would compose the same policy twice.
# This does not run during `spin up` or `spin build`.
#
# The guest must be the standard `ssr` build. Refuses an HMAC ingress
# artifact. Refuses the split chain: secure-defaults already applies
# nosniff, strict-origin-when-cross-origin, and CORS.
#
# Build secure-defaults.wasm from codeitlikemiley/wasi-http-middleware
# commit 3df96c21a7906b885e67229e9a7c8c01b6497109. Final target is the
# unpublished tag v0.2.0-alpha.4. Requires wac 0.10.1.
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <application.wasm> <output.wasm> <secure-defaults.wasm>" >&2
  exit 2
fi

APP="$1"
OUTPUT="$2"
MIDDLEWARE="$3"

case "$APP" in
  *trusted-ingress*)
    echo "refusing to compose middleware around an HMAC ingress component: $APP" >&2
    exit 2
    ;;
esac

case "$MIDDLEWARE" in
  *security-headers*|*request-id*|*authn-policy*|*cors.wasm*)
    echo "refusing split middleware; secure-defaults already sets nosniff, referrer-policy, and CORS: $MIDDLEWARE" >&2
    exit 2
    ;;
esac

if [[ ! -f "$APP" ]]; then
  echo "application component does not exist: $APP" >&2
  exit 2
fi

if [[ ! -f "$MIDDLEWARE" ]]; then
  echo "secure-defaults component does not exist: $MIDDLEWARE" >&2
  exit 2
fi

if ! command -v wac >/dev/null 2>&1; then
  echo "wac 0.10.1 is not on PATH; middleware composition was not run" >&2
  exit 2
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
stage="$TMP/secure-defaults.wasm"
wac plug --plug "$APP" "$MIDDLEWARE" --output "$stage"
mkdir -p "$(dirname "$OUTPUT")"
install -m 0644 "$stage" "$OUTPUT"
echo "composed secure-defaults: $OUTPUT"
