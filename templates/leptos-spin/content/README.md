# {{project-name}}

Generated from the `leptos-spin` template. The server is a final `wasi:http/handler@0.3.0` component. The target guest stack is Leptos 0.8.22, `wasip3` 0.9.0, and `wasm-bindgen` 0.2.129. `spin up` runs that component with no middleware and no trusted ingress.

## Prerequisites

- Rust 1.99.0 (`rust-toolchain.toml`). The declared library MSRV is 1.94.
- Targets: `wasm32-wasip2`, `wasm32-unknown-unknown`
- `cargo-leptos` 0.3.7
- `wasm-bindgen-cli` 0.2.129 (must match the crate pin)
- Spin 4.2.5 for `spin up`

## Standard app

```bash
spin build --up
```

Open `http://127.0.0.1:3000`. Server functions are `POST /api/get_count` and `POST /api/increment_count`. Static client assets are `GET /pkg/{{project-name | snake_case}}.js` and the matching `.wasm` and `.css` files.

## Other profiles

See [deploy/README.md](deploy/README.md). Middleware composition and the HMAC trusted ingress are separate manifests. Do not enable both: the ingress already applies authentication, CORS, and security headers.
