#!/usr/bin/env bash
# Generate both Spin templates from this checkout, resolve their crates,
# build the standard profile, and serve it. Middleware composition and the
# trusted-ingress process are checked as source and feature-resolution
# constraints; this script does not start PostgreSQL or wac.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${HOME}/.local/bin:${HOME}/.cargo/bin:/usr/local/cargo/bin:${PATH}"
export CARGO_TERM_COLOR=never

EVIDENCE="${EVIDENCE:-/tmp/leptos-spin-generation-evidence.txt}"
WORK="${WORK:-$(mktemp -d /tmp/leptos-spin-gen.XXXXXX)}"
: >"$EVIDENCE"

log() {
  printf '%s\n' "$*" | tee -a "$EVIDENCE"
}

require_version() {
  local label="$1" actual="$2" expected="$3"
  log "${label}: ${actual}"
  if [[ "$actual" != "$expected" ]]; then
    log "FAIL ${label}: expected ${expected}"
    exit 1
  fi
}

log "work directory: ${WORK}"
log "repository: ${ROOT}"
log "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

require_version "rustc" "$(rustc --version)" "rustc 1.99.0 (b940084d7 2026-09-28)"
log "cargo: $(cargo --version)"
require_version "cargo-leptos" "$(cargo leptos --version)" "cargo-leptos 0.3.7"
require_version "wasm-bindgen" "$(wasm-bindgen --version)" "wasm-bindgen 0.2.129"
spin_version="$(spin --version)"
log "spin: ${spin_version}"
case "$spin_version" in
  "spin 4.2.5 "*) ;;
  *)
    log "FAIL spin: expected 4.2.5"
    exit 1
    ;;
esac

log "installing templates from ${ROOT}"
spin templates install --dir "$ROOT" --upgrade >>"$EVIDENCE" 2>&1
spin templates list >>"$EVIDENCE" 2>&1

generate() {
  local name="$1" template="$2"
  local dir="${WORK}/${name}"
  log "spin new ${name} -t ${template}"
  (cd "$WORK" && spin new "$name" -t "$template" -a --no-vcs)
  test -f "${dir}/spin.toml"
  test -f "${dir}/spin.middleware.toml"
  test -f "${dir}/spin.trusted-ingress.toml"
  test -x "${dir}/deploy/compose-middleware.sh" || chmod +x "${dir}/deploy/compose-middleware.sh"
  bash -n "${dir}/deploy/compose-middleware.sh"
  python3 - "$dir" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
standard = (root / "spin.toml").read_text()
middleware = (root / "spin.middleware.toml").read_text()
ingress = (root / "spin.trusted-ingress.toml").read_text()
sources = "\n".join(path.read_text() for path in (root / "src").glob("*.rs"))
errors = []
def forbid(text, token, label):
    if token in text:
        errors.append(f"{label} contains {token}")
def need(text, token, label):
    if token not in text:
        errors.append(f"{label} missing {token}")
cargo = (root / "Cargo.toml").read_text()
forbid(standard, "WASI_MIDDLEWARE_", "spin.toml")
forbid(standard, "AUTH_TRUSTED_INGRESS", "spin.toml")
forbid(standard, "trusted-ingress", "spin.toml")
forbid(standard, "-middleware.wasm", "spin.toml")
forbid(standard, "dependencies.middleware", "spin.toml")
need(standard, '--features ssr"', "spin.toml")
need(middleware, "dependencies.middleware", "spin.middleware.toml")
need(middleware, "secure-defaults.wasm", "spin.middleware.toml")
need(middleware, "WASI_MIDDLEWARE_CORS_ORIGINS", "spin.middleware.toml")
need(middleware, "896f8f5426b1bdc6d208367d0ac8dbf44146dfda", "spin.middleware.toml")
forbid(middleware, "-middleware.wasm", "spin.middleware.toml")
forbid(middleware, "security-headers.wasm", "spin.middleware.toml")
forbid(middleware, "request-id.wasm", "spin.middleware.toml")
forbid(middleware, "authn-policy.wasm", "spin.middleware.toml")
forbid(middleware, "cors.wasm", "spin.middleware.toml")
forbid(middleware, "AUTH_TRUSTED_INGRESS", "spin.middleware.toml")
forbid(middleware, "trusted-ingress", "spin.middleware.toml")
need(cargo, "3cf30012b50a1afb750dac3d28aa6da4a32c3468", "Cargo.toml")
need(cargo, 'version = "=0.9.0"', "Cargo.toml")
need(cargo, 'version = "=0.2.129"', "Cargo.toml")
need(cargo, 'version = "=0.8.22"', "Cargo.toml")
if "dep:spin-sdk" in cargo.split("[features]", 1)[-1]:
    errors.append("ssr features enable spin-sdk")
need(ingress, "target/trusted-ingress/", "spin.trusted-ingress.toml")
need(ingress, "AUTH_TRUSTED_INGRESS_KEY_BASE64", "spin.trusted-ingress.toml")
need(ingress, "127.0.0.1:3009", "spin.trusted-ingress.toml")
need(ingress, "ssr,trusted-ingress", "spin.trusted-ingress.toml")
forbid(ingress, "WASI_MIDDLEWARE_", "spin.trusted-ingress.toml")
forbid(ingress, "-middleware.wasm", "spin.trusted-ingress.toml")
forbid(ingress, "dependencies.middleware", "spin.trusted-ingress.toml")
lower = sources.lower()
for token in (
    "access-control-allow-origin",
    "apply_response_security",
    "apply_secure_response_headers",
    "nosniff",
    "referrer-policy",
    "strict-origin-when-cross-origin",
):
    if token in lower:
        errors.append(f"guest source contains {token}")
if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
print("profile invariants ok", root.name)
PY
}

generate check-spin-app leptos-spin
generate check-wasmtime-app leptos-wasmtime

assert_resolved() {
  local dir="$1" features="$2" expect_wasi_auth="$3"
  log "cargo metadata ${dir} --features ${features}"
  (cd "$dir" && cargo metadata --format-version 1 --locked --features "$features" --filter-platform wasm32-wasip2) \
    | python3 - "$expect_wasi_auth" "$EVIDENCE" <<'PY'
import json, sys
expect_auth = sys.argv[1] == "yes"
evidence = sys.argv[2]
meta = json.load(sys.stdin)
wanted = {
    "leptos": "0.8.22",
    "leptos_meta": "0.8.7",
    "leptos_router": "0.8.17",
    "server_fn": "0.8.13",
    "leptos-wasi-runtime": "0.4.2",
    "wasip3": "0.9.0+wasi-0.3.0",
    "wit-bindgen": "0.62.0",
    "wasm-bindgen": "0.2.129",
    "wasi-auth": "0.1.0-rc.5",
}
by_id = {pkg["id"]: pkg for pkg in meta["packages"]}
root_id = meta["resolve"]["root"]
root = next(node for node in meta["resolve"]["nodes"] if node["id"] == root_id)
direct = {}
for dep in root["deps"]:
    pkg = by_id[dep["pkg"]]
    direct[pkg["name"]] = pkg["version"]
from collections import defaultdict
resolved = defaultdict(set)
for node in meta["resolve"]["nodes"]:
    pkg = by_id[node["id"]]
    resolved[pkg["name"]].add(pkg["version"])
lines = ["direct dependencies:"]
for name in sorted(direct):
    lines.append(f"  {name} {direct[name]}")
interesting = [
    "leptos",
    "leptos_meta",
    "leptos_router",
    "server_fn",
    "leptos-wasi-runtime",
    "wasip3",
    "wit-bindgen",
    "wasm-bindgen",
    "wasi-auth",
    "spin-sdk",
]
lines.append("resolved pins:")
errors = []
for name in interesting:
    actual = sorted(resolved.get(name, ()))
    lines.append(f"  {name}={actual}")
    if name in ("wasi-auth", "spin-sdk"):
        continue
    if actual != [wanted[name]]:
        errors.append(f"{name}: resolved {actual}, expected [{wanted[name]}]")
wit = resolved.get("wit-bindgen", set())
if wit - {"0.62.0", "0.51.0"}:
    errors.append(f"unexpected wit-bindgen versions: {sorted(wit)}")
wasip3_versions = resolved.get("wasip3", set())
if any(v.startswith("0.4.") or v.startswith("0.6.") for v in wasip3_versions):
    errors.append(f"old wasip3 still resolved: {sorted(wasip3_versions)}")
if "spin-sdk" in resolved:
    errors.append(f"spin-sdk is linked into this feature set: {sorted(resolved['spin-sdk'])}")
if expect_auth:
    if resolved.get("wasi-auth") != {wanted["wasi-auth"]}:
        errors.append(f"wasi-auth: resolved {sorted(resolved.get('wasi-auth', ()))}, expected {wanted['wasi-auth']}")
elif "wasi-auth" in resolved:
    errors.append("wasi-auth is present on the standard ssr resolve")
text = "\n".join(lines)
print(text)
with open(evidence, "a", encoding="utf-8") as handle:
    handle.write(text + "\n")
if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
PY
}

# Resolve once per app. `cargo fetch` writes the lock that metadata checks.
for app in check-spin-app check-wasmtime-app; do
  log "fetch ${app}"
  (cd "${WORK}/${app}" && cargo fetch --features hydrate,ssr,trusted-ingress) >>"$EVIDENCE" 2>&1
  assert_resolved "${WORK}/${app}" ssr no
  assert_resolved "${WORK}/${app}" "ssr,trusted-ingress" yes
  log "cargo check trusted-ingress feature ${app}"
  (cd "${WORK}/${app}" && cargo check --locked --target wasm32-wasip2 --no-default-features --features ssr,trusted-ingress)
  log "cargo check hydrate ${app}"
  (cd "${WORK}/${app}" && cargo check --locked --target wasm32-unknown-unknown --no-default-features --features hydrate)
done

serve_one() {
  local name="$1"
  local dir="${WORK}/${name}"
  local log_file="${WORK}/${name}.spin.log"
  log "release build ${name}"
  (cd "$dir" && cargo leptos build --release --frontend-only --lib-cargo-args=--locked)
  (cd "$dir" && LEPTOS_OUTPUT_NAME="${name//-/_}" cargo build --locked --lib --target wasm32-wasip2 --release --no-default-features --features ssr)
  local wasm="${dir}/target/wasm32-wasip2/release/${name//-/_}.wasm"
  test -f "$wasm"
  log "wasm: ${wasm} ($(wc -c <"$wasm") bytes)"
  local pkg
  pkg="$(find "${dir}/target/site/pkg" -maxdepth 1 -type f -name '*.js' -print -quit)"
  test -n "$pkg"
  local asset
  asset="$(basename "$pkg")"
  log "starting spin up for ${name}"
  (cd "$dir" && spin up >"$log_file" 2>&1) &
  local pid=$!
  cleanup() {
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  }
  trap cleanup RETURN
  local ready=0
  for _ in $(seq 1 90); do
    if curl -fsS -o /dev/null "http://127.0.0.1:3000/"; then
      ready=1
      break
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      break
    fi
    sleep 1
  done
  if [[ "$ready" != 1 ]]; then
    log "FAIL ${name} did not serve http://127.0.0.1:3000/"
    log "---- spin log ----"
    cat "$log_file" | tee -a "$EVIDENCE"
    exit 1
  fi
  local home_headers="${WORK}/${name}.home.headers"
  local home_body="${WORK}/${name}.home.body"
  curl -fsS -D "$home_headers" -o "$home_body" "http://127.0.0.1:3000/"
  grep -q "$name" "$home_body"
  grep -q "Count Value" "$home_body"
  python3 - "$home_headers" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read().lower()
nosniff = text.count("x-content-type-options:")
cors = text.count("access-control-allow-origin:")
print(f"x-content-type-options count={nosniff}")
print(f"access-control-allow-origin count={cors}")
if nosniff != 1 or cors != 0:
    sys.exit(1)
PY
  local missing
  missing="$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:3000/missing-page")"
  log "${name} missing-page status ${missing}"
  if [[ "$missing" != "404" ]]; then
    log "FAIL expected 404 for an unknown route"
    exit 1
  fi
  local code
  code="$(curl -sS -o "${WORK}/${name}.get_count.body" -w '%{http_code}' \
    -X POST "http://127.0.0.1:3000/api/get_count" \
    -H 'content-type: application/json' \
    -H 'accept: application/json' \
    --data '[]')"
  log "${name} POST /api/get_count -> ${code} body=$(cat "${WORK}/${name}.get_count.body")"
  if [[ "$code" != "200" ]]; then
    log "FAIL get_count"
    exit 1
  fi
  code="$(curl -sS -o "${WORK}/${name}.increment.body" -w '%{http_code}' \
    -X POST "http://127.0.0.1:3000/api/increment_count" \
    -H 'content-type: application/json' \
    -H 'accept: application/json' \
    --data '[]')"
  log "${name} POST /api/increment_count -> ${code} body=$(cat "${WORK}/${name}.increment.body")"
  if [[ "$code" != "200" ]]; then
    log "FAIL increment_count"
    exit 1
  fi
  curl -fsS -o "${WORK}/${name}.asset" "http://127.0.0.1:3000/pkg/${asset}"
  cmp -s "$pkg" "${WORK}/${name}.asset"
  log "${name} /pkg/${asset} matches the built file ($(wc -c <"$pkg") bytes)"
  cleanup
  trap - RETURN
  log "PASS ${name}"
}

serve_one check-spin-app
serve_one check-wasmtime-app

log "PASS generated both templates, resolved the pinned crates, and served / , /api/get_count, /api/increment_count, and /pkg"
log "UNVERIFIED in this script: Spin dependencies.middleware against secure-defaults.wasm from wasi-http-middleware 896f8f5 (tag v0.2.0-alpha.4 is unpublished and the Wasm is not vendored), wac composition, Wasmtime serve, and a live wasi-auth ingress with PostgreSQL"
log "evidence: ${EVIDENCE}"
