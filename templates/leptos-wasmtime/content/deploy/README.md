# Deployment profiles

Pick one profile. They are separate manifests and separate Wasm artifacts.

| Profile | Manifest | Guest features | Who applies CORS, security headers, and auth |
|---|---|---|---|
| Standard | `spin.toml` | `ssr` | Nobody in the template. `leptos-wasi-runtime` still sets a single `x-content-type-options: nosniff` on its own responses. |
| HTTP middleware | `spin.middleware.toml` | `ssr` only. Spin 4.2.5 loads `dependencies.middleware`. | Those middleware components only. Do not enable the HMAC ingress feature, and do not also run `wac`. |
| Trusted ingress | `spin.trusted-ingress.toml` | `ssr,trusted-ingress` | The native `wasi-auth` ingress. This guest only verifies the HMAC envelope. |

`spin up` and `spin build` read `spin.toml` only.

## 1. Standard Leptos WASI app

```bash
spin build --up
```

The component exports `wasi:http/handler@0.3.0`. `/pkg/...` is a separate fileserver trigger so browser assets are not wrapped by a later policy. The counter is in-memory; durable state stays outside the guest.

Tagged Spin 4.2.5 is the host for generated-app checks. It serves `wasi:http/handler@0.3.0` and composes native `dependencies.middleware`. Wasmtime 46.0.1 is not vendored here.

## 2. Optional HTTP middleware

On Spin 4.2.5, build the standard component and place middleware Wasm next to it, then start the opt-in manifest:

```bash
spin build
spin up -f spin.middleware.toml
```

`dependencies.middleware` runs request-id, then security-headers, then cors, then authn-policy. `/pkg/...` has no middleware entry. CORS variables live on the cors component. Security-headers replaces `nosniff` on the way out. The guest does not read those variables and does not emit CORS.

The middleware binaries are not in this template. Build components that import and export `wasi:http/handler@0.3.0` from `codeitlikemiley/wasi-http-middleware` after that repo pins `wasip3` `=0.9.0`. Commit `61b41995812220c69c4a10530efb0cd5f7522840` is still `wasip3` 0.7.0. The intended final target is a signed `wasi-http-middleware` 0.2.0 release. There is no crates.io crate and no GitHub release asset today, so this profile is not what `spin up` runs.

`deploy/compose-middleware.sh` is the Wasmtime precompose path (`wac` 0.10.1). It refuses any input path containing `trusted-ingress`. Serve its output with Wasmtime. Do not point `spin.middleware.toml` at that composed file. `make middleware` prints both commands and does not run them.

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
