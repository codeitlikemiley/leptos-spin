mod app;

#[cfg(feature = "ssr")]
mod server;

/// Browser hydration entrypoint. Not part of the server component.
#[cfg(feature = "hydrate")]
#[wasm_bindgen::prelude::wasm_bindgen]
pub fn hydrate() {
    console_error_panic_hook::set_once();
    leptos::mount::hydrate_body(app::App);
}
