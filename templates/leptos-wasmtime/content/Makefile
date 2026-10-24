# Build the same component for Wasmtime or Spin.
.PHONY: help spin wasmtime middleware trusted-ingress clean

help:
	@echo "  make spin              - standard profile (spin.toml) via Spin"
	@echo "  make wasmtime          - standard profile via Wasmtime serve"
	@echo "  make middleware        - print the opt-in composition command"
	@echo "  make trusted-ingress   - print the opt-in HMAC ingress command"
	@echo "  make clean             - remove build artifacts"

spin:
	spin build --up

wasmtime:
	cargo leptos build --release --frontend-only
	LEPTOS_OUTPUT_NAME={{project-name | snake_case}} cargo build --lib --target wasm32-wasip2 --release --no-default-features --features ssr --target-dir target/wasmtime
	wasmtime serve \
		-W component-model-async=y \
		-S p3=y \
		-S cli=y \
		-S http=y \
		--dir=./target/site::/site \
		--env=LEPTOS_OUTPUT_NAME={{project-name | snake_case}} \
		--env=LEPTOS_SITE_ROOT=/site \
		--env=LEPTOS_SITE_PKG_DIR=pkg \
		--addr 127.0.0.1:3000 \
		target/wasmtime/wasm32-wasip2/release/{{project-name | snake_case}}.wasm

middleware:
	@echo "Opt-in only. Build the standard component, then compose. Do not use a trusted-ingress artifact."
	@echo "./deploy/compose-middleware.sh target/wasm32-wasip2/release/{{project-name | snake_case}}.wasm target/wasm32-wasip2/release/{{project-name | snake_case}}-middleware.wasm <request-id.wasm> <security-headers.wasm> <cors.wasm> <authn-policy.wasm>"
	@echo "spin up -f spin.middleware.toml"

trusted-ingress:
	@echo "Opt-in only. This profile does not compose middleware."
	@echo "spin build -f spin.trusted-ingress.toml"
	@echo "spin up -f spin.trusted-ingress.toml --variable trusted_ingress_key=$$AUTH_TRUSTED_INGRESS_KEY_BASE64"

clean:
	cargo clean
	rm -rf target/site target/wasmtime target/trusted-ingress
