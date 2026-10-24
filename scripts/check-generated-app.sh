#!/usr/bin/env bash
# Generate both Spin templates from this checkout, resolve their crates,
# and serve the standard, optional-middleware, and trusted-ingress profiles
# on Spin 4.2.5. secure-defaults.wasm is built from wasi-http-middleware
# 3df96c21a7906b885e67229e9a7c8c01b6497109. This script does not start wac,
# Wasmtime, PostgreSQL, or the wasi-auth ingress process.
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
need(middleware, "3df96c21a7906b885e67229e9a7c8c01b6497109", "spin.middleware.toml")
need(cargo, "87e1476938c2b23d598a3fcc74a7acb094aac855", "Cargo.toml")
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
  local meta_json="${dir}.features-${features//,/-}.json"
  log "cargo metadata ${dir} --features ${features}"
  # A heredoc is this process's stdin, so the metadata JSON has to be a file.
  (cd "$dir" && cargo metadata --format-version 1 --locked --features "$features" --filter-platform wasm32-wasip2 >"$meta_json")
  python3 - "$expect_wasi_auth" "$EVIDENCE" "$meta_json" <<'PY'
import json, sys
expect_auth = sys.argv[1] == "yes"
evidence = sys.argv[2]
meta = json.load(open(sys.argv[3]))
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
    if name in ("wasi-auth", "spin-sdk", "wit-bindgen"):
        continue
    if actual != [wanted[name]]:
        errors.append(f"{name}: resolved {actual}, expected [{wanted[name]}]")
# wasip2 1.0.4 (getrandom on wasm32-wasip2) pins wit-bindgen 0.57.1 with
# default features off. That is not the wasip3 0.7 binding. inter-task-wakeup
# on 0.57.x traps under Spin 4.2.5, so the feature set must stay empty.
wit_nodes = []
for node in meta["resolve"]["nodes"]:
    pkg = by_id[node["id"]]
    if pkg["name"] != "wit-bindgen":
        continue
    parents = sorted({
        by_id[other["id"]]["name"]
        for other in meta["resolve"]["nodes"]
        for dep in other.get("deps", [])
        if dep["pkg"] == node["id"]
    })
    wit_nodes.append((pkg["version"], sorted(node.get("features") or []), parents))
versions = {version for version, _, _ in wit_nodes}
if "0.62.0" not in versions:
    errors.append(f"wit-bindgen 0.62.0 missing: {sorted(versions)}")
for version, features, parents in wit_nodes:
    lines.append(f"  wit-bindgen {version} features={features} parents={parents}")
    if version == "0.62.0":
        if "inter-task-wakeup" in features:
            errors.append("wit-bindgen 0.62.0 enables inter-task-wakeup")
        continue
    if version == "0.57.1":
        if features:
            errors.append(f"wit-bindgen 0.57.1 features must stay empty, got {features}")
        if parents != ["wasip2"]:
            errors.append(f"wit-bindgen 0.57.1 parents {parents}, expected ['wasip2']")
        continue
    errors.append(f"unexpected wit-bindgen {version} features={features} parents={parents}")
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

# `cargo fetch` has no `--features` flag. Metadata resolves the feature
# set and writes Cargo.lock, which the locked checks below read.
for app in check-spin-app check-wasmtime-app; do
  log "resolve ${app}"
  (cd "${WORK}/${app}" && cargo metadata --format-version 1 --features hydrate,ssr,trusted-ingress >"${WORK}/${app}.metadata.json") 2>>"$EVIDENCE"
  assert_resolved "${WORK}/${app}" ssr no
  assert_resolved "${WORK}/${app}" "ssr,trusted-ingress" yes
  log "cargo check trusted-ingress feature ${app}"
  (cd "${WORK}/${app}" && cargo check --locked --target wasm32-wasip2 --no-default-features --features ssr,trusted-ingress)
  log "cargo check hydrate ${app}"
  (cd "${WORK}/${app}" && cargo check --locked --target wasm32-unknown-unknown --no-default-features --features hydrate)
done

SPIN_PID=""

stop_spin() {
  local pid="$1"
  if [[ -z "$pid" ]]; then
    return 0
  fi
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    local _
    for _ in $(seq 1 25); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.2
    done
    if kill -0 "$pid" 2>/dev/null; then
      kill -9 "$pid" 2>/dev/null || true
    fi
    wait "$pid" 2>/dev/null || true
  fi
}

cleanup_spin() {
  stop_spin "$SPIN_PID"
  SPIN_PID=""
}
trap cleanup_spin EXIT

dump_spin_log() {
  local log_file="$1"
  log "---- spin log ----"
  python3 - "$log_file" "$EVIDENCE" "$WORK" <<'PY'
import pathlib, sys
log_path, evidence, work = sys.argv[1:]
text = pathlib.Path(log_path).read_text(encoding="utf-8", errors="replace")
lines = text.splitlines()[-160:]
redacted = "\n".join(lines)
for key_file in pathlib.Path(work).glob("*.ingress.key"):
    secret = key_file.read_text(encoding="ascii", errors="replace").strip()
    if secret:
        redacted = redacted.replace(secret, "<redacted>")
print(redacted)
with open(evidence, "a", encoding="utf-8") as handle:
    handle.write(redacted + "\n")
PY
}

start_spin() {
  local dir="$1"
  local log_file="$2"
  shift 2
  cleanup_spin
  log "spin up $(printf '%q ' "$@")in $(basename "$dir")"
  (
    cd "$dir"
    exec spin up "$@"
  ) >"$log_file" 2>&1 &
  SPIN_PID=$!
}

wait_http() {
  local url="$1"
  local log_file="$2"
  local label="$3"
  local ready=0
  local _
  for _ in $(seq 1 90); do
    if curl -fsS -o /dev/null "$url" 2>/dev/null; then
      ready=1
      break
    fi
    if [[ -n "$SPIN_PID" ]] && ! kill -0 "$SPIN_PID" 2>/dev/null; then
      break
    fi
    sleep 1
  done
  if [[ "$ready" != 1 ]]; then
    log "FAIL ${label} did not serve ${url}"
    dump_spin_log "$log_file"
    exit 1
  fi
}

# nosniff, referrer, and acao are expected counts. -1 skips that count.
# When acao_value is set and the expected count is 1, the value must match.
assert_headers() {
  local file="$1"
  local nosniff="$2"
  local referrer="$3"
  local acao="$4"
  local label="$5"
  local acao_value="${6:-}"
  python3 - "$file" "$nosniff" "$referrer" "$acao" "$label" "$acao_value" "$EVIDENCE" <<'PY'
import sys
path, nosniff, referrer, acao, label, acao_value, evidence = sys.argv[1:]
raw = open(path, encoding="utf-8", errors="replace").read()
lines = raw.splitlines()
block = []
for line in lines[1:]:
    if line.strip() == "":
        break
    block.append(line)
headers = []
for line in block:
    if ":" not in line:
        continue
    name, value = line.split(":", 1)
    headers.append((name.strip().lower(), value.strip()))

def values(name):
    return [value for key, value in headers if key == name]

got = {
    "x-content-type-options": values("x-content-type-options"),
    "referrer-policy": values("referrer-policy"),
    "access-control-allow-origin": values("access-control-allow-origin"),
    "x-request-id": values("x-request-id"),
}
expected = {
    "x-content-type-options": int(nosniff),
    "referrer-policy": int(referrer),
    "access-control-allow-origin": int(acao),
}
errors = []
parts = []
for name, count in expected.items():
    actual = got[name]
    parts.append(f"{name} count={len(actual)} values={actual}")
    if count >= 0 and len(actual) != count:
        errors.append(f"{name}: count {len(actual)} expected {count}")
parts.append(f"x-request-id count={len(got['x-request-id'])}")
if expected["x-content-type-options"] == 1 and got["x-content-type-options"] != ["nosniff"]:
    errors.append(f"nosniff value {got['x-content-type-options']}")
if expected["referrer-policy"] == 1 and got["referrer-policy"] != ["strict-origin-when-cross-origin"]:
    errors.append(f"referrer value {got['referrer-policy']}")
if expected["access-control-allow-origin"] == 1 and acao_value and got["access-control-allow-origin"] != [acao_value]:
    errors.append(f"acao value {got['access-control-allow-origin']} expected [{acao_value}]")
line = f"{label}: " + "; ".join(parts)
print(line)
with open(evidence, "a", encoding="utf-8") as handle:
    handle.write(line + "\n")
    if errors:
        handle.write("FAIL " + label + "\n")
        handle.write(raw)
        if not raw.endswith("\n"):
            handle.write("\n")
if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
PY
}

fetch_headers() {
  local dest_headers="$1"
  local dest_body="$2"
  local url="$3"
  shift 3
  curl -sS -D "$dest_headers" -o "$dest_body" "$@" "$url"
}

http_code() {
  local headers="$1"
  python3 - "$headers" <<'PY'
import sys
line = open(sys.argv[1], encoding="utf-8", errors="replace").readline().strip()
parts = line.split()
if len(parts) < 2 or not parts[1].isdigit():
    print(f"missing status in {line!r}", file=sys.stderr)
    sys.exit(1)
print(parts[1])
PY
}

post_server_fn() {
  local name="$1"
  local base="$2"
  local fn_name="$3"
  local label="$4"
  local nosniff="$5"
  local referrer="$6"
  local acao="$7"
  local acao_value="${8-}"
  if [[ $# -ge 8 ]]; then
    shift 8
  else
    shift "$#"
  fi
  local headers="${WORK}/${name}.${label}.headers"
  local body="${WORK}/${name}.${label}.body"
  fetch_headers "$headers" "$body" "${base}/api/${fn_name}" \
    -X POST \
    -H 'content-type: application/json' \
    -H 'accept: application/json' \
    --data '[]' \
    "$@"
  local code
  code="$(http_code "$headers")"
  log "${label} POST /api/${fn_name} -> ${code} body=$(cat "$body") bytes=$(wc -c <"$body")"
  if [[ "$code" != "200" ]]; then
    log "FAIL ${label} ${fn_name}"
    cat "$headers" | tee -a "$EVIDENCE"
    exit 1
  fi
  assert_headers "$headers" "$nosniff" "$referrer" "$acao" "${label} POST /api/${fn_name}" "$acao_value"
}

check_asset() {
  local name="$1"
  local base="$2"
  local pkg="$3"
  local asset="$4"
  local label="$5"
  local referrer="$6"
  local acao="$7"
  shift 7
  local headers="${WORK}/${name}.${label}.asset.headers"
  local body="${WORK}/${name}.${label}.asset.body"
  local code
  code="$(curl -sS -D "$headers" -o "$body" -w '%{http_code}' "$@" "${base}/pkg/${asset}")"
  log "${label} /pkg/${asset} -> ${code} bytes=$(wc -c <"$body")"
  if [[ "$code" != "200" ]]; then
    log "FAIL ${label} asset status"
    exit 1
  fi
  if ! cmp -s "$pkg" "$body"; then
    log "FAIL ${label} /pkg/${asset} bytes differ from $(wc -c <"$pkg")"
    exit 1
  fi
  log "${label} /pkg/${asset} matches the built file ($(wc -c <"$pkg") bytes)"
  assert_headers "$headers" -1 "$referrer" "$acao" "${label} /pkg/${asset}"
}

serve_one() {
  local name="$1"
  local dir="${WORK}/${name}"
  local log_file="${WORK}/${name}.standard.spin.log"
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
  printf '%s\n' "$pkg" >"${dir}.pkg-path"
  printf '%s\n' "$asset" >"${dir}.pkg-name"
  start_spin "$dir" "$log_file"
  wait_http "http://127.0.0.1:3000/" "$log_file" "${name} standard"
  local home_headers="${WORK}/${name}.standard.home.headers"
  local home_body="${WORK}/${name}.standard.home.body"
  fetch_headers "$home_headers" "$home_body" "http://127.0.0.1:3000/"
  grep -q "$name" "$home_body"
  grep -q "Count Value" "$home_body"
  assert_headers "$home_headers" 1 0 0 "${name} standard GET /"
  local missing_headers="${WORK}/${name}.standard.missing.headers"
  local missing_body="${WORK}/${name}.standard.missing.body"
  fetch_headers "$missing_headers" "$missing_body" "http://127.0.0.1:3000/missing-page"
  local missing
  missing="$(http_code "$missing_headers")"
  log "${name} standard missing-page status ${missing}"
  if [[ "$missing" != "404" ]]; then
    log "FAIL expected 404 for an unknown route"
    exit 1
  fi
  assert_headers "$missing_headers" 1 0 0 "${name} standard GET /missing-page"
  post_server_fn "$name" "http://127.0.0.1:3000" get_count "${name} standard" 1 0 0
  post_server_fn "$name" "http://127.0.0.1:3000" increment_count "${name} standard" 1 0 0
  check_asset "$name" "http://127.0.0.1:3000" "$pkg" "$asset" "${name} standard" 0 0
  cleanup_spin
  log "PASS ${name} standard"
}

MIDDLEWARE_REV="3df96c21a7906b885e67229e9a7c8c01b6497109"

build_secure_defaults() {
  local dest="${WORK}/wasi-http-middleware"
  log "cloning wasi-http-middleware ${MIDDLEWARE_REV}"
  git clone --filter=blob:none --branch gol/stabilize-middleware-contracts-894a \
    https://github.com/codeitlikemiley/wasi-http-middleware.git "$dest"
  git -C "$dest" checkout --detach "$MIDDLEWARE_REV"
  local got
  got="$(git -C "$dest" rev-parse HEAD)"
  if [[ "$got" != "$MIDDLEWARE_REV" ]]; then
    log "FAIL middleware checkout ${got}"
    exit 1
  fi
  local wakeup_status=0
  git -C "$dest" grep -n -I 'inter-task-wakeup' -- '*.toml' '*.rs' >/tmp/middleware-wakeup.txt || wakeup_status=$?
  if [[ "$wakeup_status" -eq 0 ]]; then
    log "FAIL wasi-http-middleware enables or names wit-bindgen inter-task-wakeup"
    cat /tmp/middleware-wakeup.txt | tee -a "$EVIDENCE"
    exit 1
  fi
  if [[ "$wakeup_status" -gt 1 ]]; then
    log "FAIL git grep inter-task-wakeup exited ${wakeup_status}"
    exit 1
  fi
  log "building wasi-http-middleware-secure-defaults"
  if ! (cd "$dest" && cargo build --locked --release --target wasm32-wasip2 -p wasi-http-middleware-secure-defaults) \
    >"${WORK}/middleware-build.log" 2>&1; then
    log "FAIL secure-defaults build"
    tail -n 160 "${WORK}/middleware-build.log" | tee -a "$EVIDENCE"
    exit 1
  fi
  local built="${dest}/target/wasm32-wasip2/release/wasi_http_middleware_secure_defaults.wasm"
  test -f "$built"
  log "secure-defaults.wasm ($(wc -c <"$built") bytes) from ${got}"
  printf '%s\n' "$built" >"${WORK}/secure-defaults.path"
}

serve_middleware() {
  local name="$1"
  local dir="${WORK}/${name}"
  local log_file="${WORK}/${name}.middleware.spin.log"
  local built
  built="$(cat "${WORK}/secure-defaults.path")"
  mkdir -p "${dir}/target/middleware"
  cp "$built" "${dir}/target/middleware/secure-defaults.wasm"
  local pkg asset
  pkg="$(cat "${dir}.pkg-path")"
  asset="$(cat "${dir}.pkg-name")"
  start_spin "$dir" "$log_file" -f spin.middleware.toml
  wait_http "http://127.0.0.1:3000/" "$log_file" "${name} middleware"
  local origin="http://127.0.0.1:3000"
  local home_headers="${WORK}/${name}.middleware.home.headers"
  local home_body="${WORK}/${name}.middleware.home.body"
  fetch_headers "$home_headers" "$home_body" "http://127.0.0.1:3000/"
  assert_headers "$home_headers" 1 1 0 "${name} middleware GET / without Origin"
  local origin_headers="${WORK}/${name}.middleware.origin.headers"
  local origin_body="${WORK}/${name}.middleware.origin.body"
  fetch_headers "$origin_headers" "$origin_body" "http://127.0.0.1:3000/" -H "origin: ${origin}"
  assert_headers "$origin_headers" 1 1 1 "${name} middleware GET / with Origin" "$origin"
  local missing_headers="${WORK}/${name}.middleware.missing.headers"
  local missing_body="${WORK}/${name}.middleware.missing.body"
  fetch_headers "$missing_headers" "$missing_body" "http://127.0.0.1:3000/missing-page" -H "origin: ${origin}"
  local missing
  missing="$(http_code "$missing_headers")"
  log "${name} middleware missing-page status ${missing}"
  if [[ "$missing" != "404" ]]; then
    log "FAIL middleware expected 404"
    exit 1
  fi
  assert_headers "$missing_headers" 1 1 1 "${name} middleware GET /missing-page with Origin" "$origin"
  post_server_fn "$name" "http://127.0.0.1:3000" get_count "${name} middleware" 1 1 0
  post_server_fn "$name" "http://127.0.0.1:3000" increment_count "${name} middleware-origin" 1 1 1 "$origin" \
    -H "origin: ${origin}"
  check_asset "$name" "http://127.0.0.1:3000" "$pkg" "$asset" "${name} middleware" 0 0 \
    -H "origin: ${origin}"
  cleanup_spin
  log "PASS ${name} middleware"
}

expect_status() {
  local headers="$1"
  local expected="$2"
  local label="$3"
  local code
  code="$(http_code "$headers")"
  log "${label} -> ${code}"
  if [[ "$code" != "$expected" ]]; then
    log "FAIL ${label}: expected ${expected}"
    cat "$headers" | tee -a "$EVIDENCE"
    exit 1
  fi
  assert_headers "$headers" 0 0 0 "${label}"
}

serve_trusted() {
  local name="$1"
  local dir="${WORK}/${name}"
  local snake="${name//-/_}"
  local log_file="${WORK}/${name}.ingress.spin.log"
  log "trusted-ingress release build ${name}"
  (
    cd "$dir"
    LEPTOS_OUTPUT_NAME="$snake" cargo build --locked --lib \
      --target wasm32-wasip2 --release \
      --no-default-features --features ssr,trusted-ingress \
      --target-dir target/trusted-ingress
  )
  local wasm="${dir}/target/trusted-ingress/wasm32-wasip2/release/${snake}.wasm"
  test -f "$wasm"
  log "trusted-ingress wasm: ${wasm} ($(wc -c <"$wasm") bytes)"
  local pkg asset
  pkg="$(cat "${dir}.pkg-path")"
  asset="$(cat "${dir}.pkg-name")"
  local base="http://127.0.0.1:3009"

  start_spin "$dir" "$log_file" -f spin.trusted-ingress.toml
  wait_http "${base}/" "$log_file" "${name} trusted-ingress empty key"
  local home_headers="${WORK}/${name}.ingress.home.headers"
  local home_body="${WORK}/${name}.ingress.home.body"
  fetch_headers "$home_headers" "$home_body" "${base}/"
  grep -q "$name" "$home_body"
  assert_headers "$home_headers" 1 0 0 "${name} trusted-ingress anonymous GET /"
  post_server_fn "$name" "$base" get_count "${name} trusted-ingress" 1 0 0
  check_asset "$name" "$base" "$pkg" "$asset" "${name} trusted-ingress" 0 0
  local denied_headers="${WORK}/${name}.ingress.empty-auth.headers"
  local denied_body="${WORK}/${name}.ingress.empty-auth.body"
  fetch_headers "$denied_headers" "$denied_body" "${base}/" -H 'authorization: Bearer not-a-token'
  expect_status "$denied_headers" 503 "${name} trusted-ingress empty key with Authorization"
  cleanup_spin

  local key_file="${WORK}/${name}.ingress.key"
  python3 - "$key_file" <<'PY'
import base64, os, sys
sys.stdout.reconfigure(encoding="utf-8")
open(sys.argv[1], "w", encoding="ascii").write(base64.standard_b64encode(os.urandom(32)).decode("ascii"))
os.chmod(sys.argv[1], 0o600)
PY
  log "${name} trusted-ingress key is 32 decoded bytes; the value is not logged"
  local keyed_log="${WORK}/${name}.ingress.keyed.spin.log"
  start_spin "$dir" "$keyed_log" -f spin.trusted-ingress.toml \
    --variable "trusted_ingress_key=@${key_file}"
  wait_http "${base}/" "$keyed_log" "${name} trusted-ingress with key"
  local keyed_headers="${WORK}/${name}.ingress.keyed.headers"
  local keyed_body="${WORK}/${name}.ingress.keyed.body"
  fetch_headers "$keyed_headers" "$keyed_body" "${base}/"
  assert_headers "$keyed_headers" 1 0 0 "${name} trusted-ingress keyed anonymous GET /"
  local auth_headers="${WORK}/${name}.ingress.auth.headers"
  local auth_body="${WORK}/${name}.ingress.auth.body"
  fetch_headers "$auth_headers" "$auth_body" "${base}/" -H 'authorization: Bearer not-a-token'
  expect_status "$auth_headers" 401 "${name} trusted-ingress Authorization without envelope"
  local cookie_headers="${WORK}/${name}.ingress.cookie.headers"
  local cookie_body="${WORK}/${name}.ingress.cookie.body"
  fetch_headers "$cookie_headers" "$cookie_body" "${base}/" -H 'cookie: session=1'
  expect_status "$cookie_headers" 401 "${name} trusted-ingress Cookie without envelope"
  local bogus_headers="${WORK}/${name}.ingress.bogus.headers"
  local bogus_body="${WORK}/${name}.ingress.bogus.body"
  fetch_headers "$bogus_headers" "$bogus_body" "${base}/" \
    -H 'x-wasi-auth-context: not-an-envelope' \
    -H 'x-request-id: req-1'
  expect_status "$bogus_headers" 401 "${name} trusted-ingress bogus envelope"
  post_server_fn "$name" "$base" increment_count "${name} trusted-ingress-keyed" 1 0 0
  check_asset "$name" "$base" "$pkg" "$asset" "${name} trusted-ingress-keyed" 0 0 \
    -H 'origin: http://127.0.0.1:3009'
  cleanup_spin
  log "PASS ${name} trusted-ingress guest"
}

serve_one check-spin-app
serve_one check-wasmtime-app
build_secure_defaults
serve_middleware check-spin-app
serve_middleware check-wasmtime-app
serve_trusted check-spin-app
serve_trusted check-wasmtime-app

log "PASS generated both templates and served standard, middleware, and trusted-ingress guests on Spin 4.2.5"
log "UNVERIFIED: wac composition, Wasmtime serve, and a live wasi-auth ingress process with PostgreSQL. Tag v0.2.0-alpha.4 is unpublished. A crates.io leptos-wasi-runtime release on wasip3 0.9 is unpublished."
log "evidence: ${EVIDENCE}"
