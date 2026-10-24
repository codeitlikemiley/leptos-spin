# Leptos Spin templates

Spin templates for a Leptos application exported as a final `wasi:http/handler@0.3.0` component.

The target guest set is Leptos 0.8.22, `server_fn` 0.8.13, `wasip3` 0.9.0 (`wit-bindgen` 0.62.0), and `wasm-bindgen` 0.2.129. `spin-sdk` is an optional git pin at `3cf30012b50a1afb750dac3d28aa6da4a32c3468` and is not linked into the standard component. `TESTED_DEPENDENCIES.toml` records which of those pins Cargo actually resolved. The declared MSRV is 1.94. This repository pins and tests toolchain 1.99.0, not floating stable.

`leptos-wasi-runtime` is git pin `87e1476938c2b23d598a3fcc74a7acb094aac855` (version 0.4.2, `wasip3` 0.9, `spawn_local`). The final target is a crates.io `leptos-wasi-runtime` release on `wasip3` 0.9. The `wasm32-wasip2` target also links `wasip2` 1.0.4, which pins `wit-bindgen` 0.57.1 with no features. Do not enable `inter-task-wakeup` on that 0.57.x crate.

| Template | What `spin new` creates |
|---|---|
| `leptos-spin` | Spin-first app. `spin build --up` serves the standard profile. |
| `leptos-wasmtime` | The same component shape, plus a Makefile for Wasmtime 46.0.1 or Spin. |

Both generated apps have three deployment profiles. Only the standard profile is what `spin up` runs:

1. **Standard.** `spin.toml`. No middleware pipeline and no HMAC verifier.
2. **HTTP middleware.** `spin.middleware.toml`. Opt-in. One `secure-defaults` component from `wasi-http-middleware` `3df96c21a7906b885e67229e9a7c8c01b6497109` writes nosniff, referrer policy, and CORS only when that field is absent, so it does not replace the runtime's single nosniff. The guest does not write those headers. Final target is unpublished tag `v0.2.0-alpha.4`. `deploy/compose-middleware.sh` is the Wasmtime plug of that same component and must not be combined with the Spin manifest.
3. **Trusted ingress.** `spin.trusted-ingress.toml`. A separate guest built with `ssr,trusted-ingress` that verifies `wasi-auth` 0.1.0-rc.5 HMAC envelopes and does not compose middleware.

`/pkg/...` is always a separate fileserver trigger so client assets are not wrapped by auth.

## Install

From this checkout:

```bash
spin templates install --dir . --upgrade
spin new my-app -t leptos-spin
```

From the fork:

```bash
spin templates install --git https://github.com/codeitlikemiley/leptos-spin --upgrade
```

The intended upstream home for the generic template update is `spinframework/leptos-spin`.

## Check a generated app

Requires Rust 1.99.0, `cargo-leptos` 0.3.7, `wasm-bindgen-cli` 0.2.129, and Spin 4.2.5.

```bash
./scripts/check-generated-app.sh
```

The script runs `spin new` for both templates, checks the three manifests cannot double-apply CORS, security headers, or auth, resolves the lockfile, and typechecks the trusted-ingress feature. It then builds the standard component and serves it, builds `secure-defaults` from `wasi-http-middleware` `3df96c21a7906b885e67229e9a7c8c01b6497109` and serves `spin.middleware.toml`, and builds and serves the trusted-ingress guest on `127.0.0.1:3009`. Each run curls `/`, a missing route, both server functions, and a `/pkg` asset, and counts `x-content-type-options`, `referrer-policy`, and `access-control-allow-origin`. It does not start `wac`, Wasmtime, or the `wasi-auth` ingress process.
