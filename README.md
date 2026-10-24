# Leptos Spin templates

Spin templates for a Leptos application exported as a final `wasi:http/handler@0.3.0` component.

The guest dependency set is the one locked by [`leptos-wasi-runtime` 0.4.2](https://crates.io/crates/leptos-wasi-runtime): Leptos 0.8.20, `wasip3` 0.7.0, and `wasm-bindgen` 0.2.126. `TESTED_DEPENDENCIES.toml` is the pin `scripts/check-generated-app.sh` checks after Cargo resolves a freshly generated app. Rust's library MSRV is 1.93.0. This repository pins and tests toolchain 1.99.0, not floating stable.

| Template | What `spin new` creates |
|---|---|
| `leptos-spin` | Spin-first app. `spin build --up` serves the standard profile. |
| `leptos-wasmtime` | The same component shape, plus a Makefile for Wasmtime 46.0.1 or Spin. |

Both generated apps have three deployment profiles. Only the standard profile is what `spin up` runs:

1. **Standard.** `spin.toml`. No composed middleware and no HMAC verifier.
2. **Composed middleware.** `spin.middleware.toml` plus `deploy/compose-middleware.sh`. Opt-in. The script refuses a trusted-ingress artifact.
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

Requires Rust 1.99.0, `cargo-leptos` 0.3.7, `wasm-bindgen-cli` 0.2.126, and Spin 4.2.5.

```bash
./scripts/check-generated-app.sh
```

The script runs `spin new` for both templates, checks the three manifests cannot double-apply CORS, security headers, or auth, resolves the lockfile, typechecks the trusted-ingress feature, builds the standard component, and curls `/`, a missing route, both server functions, and a `/pkg` asset. It does not start `wac`, Wasmtime, or the `wasi-auth` ingress.
