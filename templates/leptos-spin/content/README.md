# {{project-name}}

Generated from the `leptos-spin` template. The server is a final `wasi:http/handler@0.3.0` component built with `leptos-wasi-runtime` 0.4.2 and `wasip3` 0.7.0. `spin up` runs that component with no middleware and no trusted ingress.

## Prerequisites

- Rust 1.99.0 (`rust-toolchain.toml`). The library MSRV is 1.93.0.
- Targets: `wasm32-wasip2`, `wasm32-unknown-unknown`
- `cargo-leptos` 0.3.7
- `wasm-bindgen-cli` 0.2.126 (must match the crate pin)
- Spin 4.2.5 for `spin up`. Wasmtime 46.0.1 is the upstream correctness reference.

## Standard app

```bash
spin build --up
```

Open `http://127.0.0.1:3000`. Server functions are `POST /api/get_count` and `POST /api/increment_count`. Static client assets are `GET /pkg/{{project-name | snake_case}}.js` and the matching `.wasm` and `.css` files.

## Other profiles

See [deploy/README.md](deploy/README.md). Middleware composition and the HMAC trusted ingress are separate manifests. Do not enable both: the ingress already applies authentication, CORS, and security headers.
