# Leptos Spin templates

https://github.com/user-attachments/assets/6596e0f3-80c0-4258-a4e3-f85c41b328b4

This repository contains custom Spin templates for bootstrapping [Leptos](https://leptos.dev) applications running on WASI. It provides two options for WASI runtimes:

1. **`leptos-wasmtime`**: derived from the [`counter` example](https://github.com/codeitlikemiley/leptos_wasi/tree/wasip3/examples/counter) in the `leptos_wasi` repository. A pure WASIp3 Guest component that can be served via standard HTTP triggers using either Wasmtime or Spin.
2. **`leptos-spin`**: derived from the [`spin-counter` example](https://github.com/codeitlikemiley/leptos_wasi/tree/wasip3/examples/spin-counter) in the `leptos_wasi` repository. A WASIp3 component built with the Fermyon `spin-sdk` using key-value triggers.

## Installation

To install these templates from the Git repository:

```bash
spin templates install --git https://github.com/akamai-developers/leptos-spin --upgrade
```

## Creating a New Project

To create a new project using one of the templates, run:

### Option 1: Using the Standard WASIp3 Template (Wasmtime/Spin)
```bash
spin new leptos-wasmtime <project-name>
```

### Option 2: Using the Spin SDK (WASIp3) Template
```bash
spin new leptos-spin <project-name>
```

## Guide: SSR with Leptos WASI & WASIp3

When developing applications with these templates, keep in mind these key architectural patterns required for running Leptos on WASIp3:

### 1. Host Async Task Scheduling
Before executing any async work (such as handling requests or rendering templates), you must initialize the host-level async task spawner. This is done at the very beginning of the handler entrypoint:
```rust
use leptos_wasi::executor::init_wasip3_spawner;

// Initialize host spawner
let _ = init_wasip3_spawner();
```

### 2. Explicit Server Function Registration
Unlike native Leptos applications where server functions (`#[server]`) are registered automatically at compile-time, under the WASI target they must be registered **explicitly** on the handler:
```rust
let wasi_res = Handler::build(req).await?
    .with_server_fn_axum::<GetCount>()
    .with_server_fn_axum::<IncrementCount>()
    // ...
```
If you write a new `#[server]` function, always make sure to call `.with_server_fn_axum::<YourServerFn>()` (or `.with_server_fn::<YourServerFn, _>()` if using the Spin SDK template) on your handler builder.

### 3. Context & Routing
Use `use_context` instead of `expect_context` within your `#[cfg(feature = "ssr")]` blocks during routing to prevent panics, as components are rendered asynchronously.
