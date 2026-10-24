# {{project-name}}

Generated from the `leptos-wasmtime` template. The same final `wasi:http/handler@0.3.0` component runs under Wasmtime 46.0.1 or Spin 4.2.5. The default manifest does not compose middleware and does not enable the trusted-ingress feature.

## Prerequisites

- Rust 1.99.0 (`rust-toolchain.toml`). The declared library MSRV is 1.94.
- Targets: `wasm32-wasip2`, `wasm32-unknown-unknown`
- `cargo-leptos` 0.3.7
- `wasm-bindgen-cli` 0.2.129 (must match the crate pin)
- Wasmtime 46.0.1 (`make wasmtime`) or Spin 4.2.5 (`make spin`)

## Run

```bash
make spin
# or
make wasmtime
```

Open `http://127.0.0.1:3000`. Server functions are `POST /api/get_count` and `POST /api/increment_count`. Static client assets are under `/pkg/`.

## Other profiles

See [deploy/README.md](deploy/README.md). `make middleware` and `make trusted-ingress` only print the opt-in commands. They do not stack CORS, security headers, or auth on top of each other.
