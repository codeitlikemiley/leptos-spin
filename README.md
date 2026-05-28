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

