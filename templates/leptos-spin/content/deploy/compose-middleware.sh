#!/usr/bin/env bash
# Wasmtime precompose path. Spin 4.2.5 should use spin.middleware.toml
# (`dependencies.middleware`) instead of this script. Do not serve the
# output of this script with that manifest: the host would compose the
# same policy twice. This does not run during `spin up` or `spin build`.
#
# The guest passed as <application.wasm> must be the standard `ssr` build.
# Refuses a trusted-ingress artifact: that profile already has an HMAC
# boundary, and stacking authn, CORS, or security-headers would apply them
# twice (the ingress owns that policy; security-headers replaces nosniff,
# it does not get a second copy from this guest).
#
# Component order is outer to inner, matching the tested leptos_wasi profile:
#   request-id, security-headers, cors, authn-policy
# `/pkg/...` stays on the fileserver trigger in spin.middleware.toml and is
# not part of this composition.
#
# Middleware components are not published as a release of this template.
# Build them from codeitlikemiley/wasi-http-middleware @ 61b419958122
# (intended final target: a signed wasi-http-middleware 0.2.0 artifact).
# Requires `wac` 0.10.1, the version locked by leptos_wasi 0.4.2.
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "usage: $0 <application.wasm> <output.wasm> <outer.wasm> [inner.wasm ...]" >&2
  exit 2
fi

APP="$1"
OUTPUT="$2"
shift 2

case "$APP" in
  *trusted-ingress*)
    echo "refusing to compose middleware around a trusted-ingress component: $APP" >&2
    exit 2
    ;;
esac

if [[ ! -f "$APP" ]]; then
  echo "application component does not exist: $APP" >&2
  exit 2
fi

if ! command -v wac >/dev/null 2>&1; then
  echo "wac 0.10.1 is not on PATH; middleware composition was not run" >&2
  exit 2
fi

CURRENT="$APP"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# The last path is plugged first, so it sits closest to the application.
index=0
for component in "$@"; do
  index=$((index + 1))
done
count="$index"
index=0
# Walk from the innermost argument back to the outermost.
args=("$@")
for ((i = count - 1; i >= 0; i--)); do
  component="${args[$i]}"
  if [[ ! -f "$component" ]]; then
    echo "middleware component does not exist: $component" >&2
    exit 2
  fi
  stage="$TMP/stage-$i.wasm"
  wac plug --plug "$CURRENT" "$component" --output "$stage"
  CURRENT="$stage"
  index=$((index + 1))
done

mkdir -p "$(dirname "$OUTPUT")"
install -m 0644 "$CURRENT" "$OUTPUT"
echo "composed $index middleware component(s): $OUTPUT"
