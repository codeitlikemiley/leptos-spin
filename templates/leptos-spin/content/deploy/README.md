# Deployment profiles

Pick one profile. They are separate manifests and separate Wasm artifacts.

| Profile | Manifest | Guest features | Who applies CORS, security headers, and auth |
|---|---|---|---|
| Standard | `spin.toml` | `ssr` | Nobody in the template. `leptos-wasi-runtime` still sets a single `x-content-type-options: nosniff` on its own responses. |
| HTTP middleware | `spin.middleware.toml` | `ssr` only. One `secure-defaults` component. | That component adds nosniff, referrer policy, and CORS only when absent. The guest does not. |
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

`dependencies.middleware` lists one component, `secure-defaults`, from `codeitlikemiley/wasi-http-middleware` commit `3df96c21a7906b885e67229e9a7c8c01b6497109` (https://github.com/codeitlikemiley/wasi-http-middleware/pull/1). That commit writes `x-content-type-options`, `referrer-policy`, and `Access-Control-*` only when the field is absent. The Leptos guest source does not write those headers. `/pkg/...` has no middleware entry. Do not also attach the split request-id, security-headers, cors, or authn-policy components.

`leptos-wasi-runtime` inserts one `nosniff` when that field is absent. `secure-defaults` leaves that value in place and adds `referrer-policy` and CORS only when the response does not already have them, so each of those headers appears once. The standard profile has no middleware, so that single runtime header is the only one.

The Wasm file is not in this template. The final target is unpublished tag `v0.2.0-alpha.4`. There is no release asset today, so this profile is not what `spin up` runs. Authn mode is `optional`: anonymous requests skip the broker, and a presented credential is verified.

`deploy/compose-middleware.sh` plugs that one component with `wac` 0.10.1 for Wasmtime. It refuses an HMAC ingress artifact and refuses the split chain. Serve its output with Wasmtime. Do not point `spin.middleware.toml` at that composed file.

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
