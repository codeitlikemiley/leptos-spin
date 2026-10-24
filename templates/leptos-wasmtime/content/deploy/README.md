# Deployment profiles

Pick one profile. They are separate manifests and separate Wasm artifacts.

| Profile | Manifest | Guest features | Who applies CORS, security headers, and auth |
|---|---|---|---|
| Standard | `spin.toml` | `ssr` | Nobody in the template. `leptos-wasi-runtime` still sets a single `x-content-type-options: nosniff` on its own responses. |
| Composed middleware | `spin.middleware.toml` | `ssr`, then `deploy/compose-middleware.sh` | The composed components only. Do not enable `trusted-ingress`. |
| Trusted ingress | `spin.trusted-ingress.toml` | `ssr,trusted-ingress` | The native `wasi-auth` ingress. This guest only verifies the HMAC envelope. |

`spin up` and `spin build` read `spin.toml` only.

## 1. Standard Leptos WASI app

```bash
spin build --up
```

The component exports `wasi:http/handler@0.3.0`. `/pkg/...` is a separate fileserver trigger so browser assets are not wrapped by a later policy. The counter is in-memory; durable state stays outside the guest.

Tagged Spin 4.2.5 is what `scripts/check-generated-app.sh` serves. Wasmtime 46.0.1 remains the `leptos_wasi` 0.4.2 correctness reference and is not vendored here.

## 2. Optional composed middleware

Build the standard component, then plug prebuilt middleware around that Wasm file:

```bash
spin build
./deploy/compose-middleware.sh \
  target/wasm32-wasip2/release/{{project-name | snake_case}}.wasm \
  target/wasm32-wasip2/release/{{project-name | snake_case}}-middleware.wasm \
  path/to/request-id.wasm \
  path/to/security-headers.wasm \
  path/to/cors.wasm \
  path/to/authn-policy.wasm
spin up -f spin.middleware.toml
```

The script refuses any input path containing `trusted-ingress`. Security-headers replaces `nosniff` on the way out; it does not ask the guest to add a second copy. CORS environment variables exist only in `spin.middleware.toml`. The guest source does not read them.

Those component binaries are not in this template. Build them from `codeitlikemiley/wasi-http-middleware` at `61b41995812220c69c4a10530efb0cd5f7522840`. The intended final target is a signed `wasi-http-middleware` 0.2.0 release. `wac` 0.10.1 is the locked composer. There is no crates.io crate and no GitHub release asset for those components today, so this profile is opt-in source composition, not a default deploy.

## 3. Trusted ingress

`wasi-auth` 0.1.0-rc.5's native ingress listens on `127.0.0.1:3008` and forwards to this component on `127.0.0.1:3009`. It seals `x-wasi-auth-context` with HMAC-SHA-256 over audience, method, path, and request id (`wasi_auth::http::TrustedContextCodec`). The audience default is `fullstack-app`. The replay window default is 5 seconds.

```bash
spin build -f spin.trusted-ingress.toml
spin up -f spin.trusted-ingress.toml \
  --variable trusted_ingress_key="$AUTH_TRUSTED_INGRESS_KEY_BASE64"
```

The key is a Spin secret variable. The manifest default is empty, and an empty key cannot verify a credentialed request. Do not put the key in git.

The guest rejects a credential or an envelope that does not verify, then strips `x-wasi-auth-context`, `Authorization`, and `Cookie` before Leptos runs. It does not call `apply_response_security` and it does not compose middleware. Anonymous requests with neither a credential nor an envelope still render, so a private misbind does not invent a second login page. Production should keep this port on loopback; the ingress is the public listener and exempts `/pkg/...`.

`wasi-auth` 0.1.0-rc.5 with the `http` feature is the crates.io target. The ingress binary and PostgreSQL are not started by this template.
