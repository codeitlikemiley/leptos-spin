# Leptos Spin templates

https://github.com/user-attachments/assets/6596e0f3-80c0-4258-a4e3-f85c41b328b4

This repository contains custom Spin templates for bootstrapping [Leptos](https://leptos.dev) applications running on WASI. It provides two options for WASI runtimes:

1. **`leptos-wasmtime`**: derived from the `counter` example in the [`leptos_wasi`](https://github.com/codeitlikemiley/leptos_wasi) repository. A pure WASIp3 Guest component that can be served via standard HTTP triggers using either Wasmtime or Spin.
2. **`leptos-spin`**: derived from the `spin-counter` example in the [`leptos_wasi`](https://github.com/codeitlikemiley/leptos_wasi) repository. A component built with the Fermyon `spin-sdk` using key-value triggers.

## Installation

### Option 1: Local Installation (For Development/Rapid Testing)
Installing from a local directory is ideal during development when you are making changes to the templates and want to test them immediately without pushing to GitHub:

```bash
spin templates install --dir /Volumes/goldcoders/leptos-spin --upgrade
```

### Option 2: Remote Installation (From Git)
Once template changes are pushed, you can install the templates from the Git repository:

```bash
spin templates install --git https://github.com/codeitlikemiley/leptos-spin --upgrade
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

## Dependency Configuration

By default, the template Cargo dependencies fetch `leptos_wasi` from the GitHub repository and `wasip3` branch:

```toml
leptos_wasi = { git = "https://github.com/codeitlikemiley/leptos_wasi", branch = "wasip3", default-features = false, features = ["wasip3"], optional = true }
```
