# Leptos Spin templates

This repository contains custom Spin templates for bootstrapping [Leptos](https://leptos.dev) applications running on WASI. It provides two options for WASI runtimes:

1. **`leptos-wasmtime`**: derived from the `counter` example. A pure WASIp3 Guest component that can be served via standard HTTP triggers using either Wasmtime or Spin.
2. **`leptos-spin`**: derived from the `spin-counter` example. A component built with the Fermyon `spin-sdk` using key-value triggers.

## Installation

You can install these templates locally:

```bash
spin templates install --from /Volumes/goldcoders/leptos-spin
```

Or from a Git repository once pushed:

```bash
spin templates install --git https://github.com/codeitlikemiley/leptos-spin
```

## Creating a New Project

To create a new project using one of the templates, run:

### Option 1: Using the Wasmtime (WASIp3) Template
```bash
spin new leptos-wasmtime <project-name>
```

### Option 2: Using the Spin SDK Template
```bash
spin new leptos-spin <project-name>
```

## Local Development & Testing

By default, the template Cargo dependencies fetch `leptos_wasi` from crates.io. If you are developing features inside `leptos_wasi` locally and want the template to use your local copy, edit the generated `Cargo.toml` to use the commented-out path dependency:

```toml
# leptos_wasi = { path = "../leptos_wasi", default-features = false, features = ["wasip3"], optional = true }
```
