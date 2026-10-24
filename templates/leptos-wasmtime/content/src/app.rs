use leptos::form::ActionForm;
use leptos::prelude::*;
use leptos_meta::*;
use leptos_router::components::{Route, Router, Routes};
use leptos_router::path;

#[cfg(feature = "ssr")]
pub fn shell(options: LeptosOptions) -> impl IntoView {
    view! {
        <!DOCTYPE html>
        <html lang="en">
            <head>
                <meta charset="utf-8" />
                <meta name="viewport" content="width=device-width, initial-scale=1" />
                <AutoReload options=options.clone() />
                <HydrationScripts options=options.clone() root="" />
                <MetaTags />
            </head>
            <body>
                <App />
            </body>
        </html>
    }
}

#[component]
pub fn App() -> impl IntoView {
    provide_meta_context();

    let fallback = || view! { "Page not found." }.into_view();

    view! {
        <Stylesheet id="leptos" href="/pkg/{{project-name | snake_case}}.css" />
        <Meta
            name="description"
            content="A website running its server-side as a WASI Component :D"
        />
        <Title text="Welcome to Leptos X WASIp3" />
        <Router>
            <main>
                <Routes fallback>
                    <Route path=path!("") view=HomePage />
                    <Route path=path!("/*any") view=NotFound />
                </Routes>
            </main>
        </Router>
    }
}

#[component]
fn HomePage() -> impl IntoView {
    let increment_action = ServerAction::<IncrementCount>::new();
    let count = Resource::new(
        move || increment_action.version().get(),
        |_| get_count(),
    );

    view! {
        <div class="min-h-screen bg-[#1a2332] flex items-center justify-center p-4">
            <div class="bg-[#263343] rounded-xl shadow-2xl p-8 md:p-12 max-w-md w-full border border-[#3a4a5c]">
                <div class="text-center space-y-8">
                    <div class="space-y-2">
                        <h1 class="text-3xl md:text-4xl font-medium text-white">
                            "{{project-name}}"
                        </h1>
                        <p class="text-[#8b9cb8] text-sm">
                            "Powered by Leptos on a WASI HTTP component"
                        </p>
                    </div>
                    <div class="bg-[#1a2332] rounded-lg p-8 border border-[#3a4a5c]">
                        <div class="text-5xl md:text-6xl font-light text-white tabular-nums" data-testid="count">
                            {move || count.get().map(|result| match result {
                                Ok(value) => value.to_string(),
                                Err(_) => "error".to_string(),
                            }).unwrap_or_else(|| "...".to_string())}
                        </div>
                        <div class="text-[#8b9cb8] text-sm mt-2 uppercase tracking-wider">
                            "Count Value"
                        </div>
                    </div>
                    <ActionForm action=increment_action>
                        <button
                            disabled=move || increment_action.pending().get()
                            class="w-full rounded-lg bg-[#00d4aa] px-6 py-3 text-[#1a2332] font-medium"
                        >
                            "Increment Counter"
                        </button>
                    </ActionForm>
                </div>
            </div>
        </div>
    }
}

#[component]
fn NotFound() -> impl IntoView {
    #[cfg(feature = "ssr")]
    {
        if let Some(response) = use_context::<leptos_wasi::response::ResponseOptions>() {
            response.set_status(leptos_wasi::prelude::StatusCode::NOT_FOUND);
        }
    }

    view! { <h1>"Not Found"</h1> }
}

#[cfg(feature = "ssr")]
fn update_count(increment: bool) -> u32 {
    use std::sync::Mutex;
    static COUNT: Mutex<u32> = Mutex::new(0);
    let mut count = COUNT.lock().unwrap_or_else(|poison| poison.into_inner());
    if increment {
        *count = count.saturating_add(1);
    }
    *count
}

#[server(prefix = "/api", endpoint = "get_count")]
pub async fn get_count() -> Result<u32, ServerFnError<String>> {
    #[cfg(feature = "ssr")]
    {
        return Ok(update_count(false));
    }
    #[cfg(not(feature = "ssr"))]
    Ok(0)
}

#[server(prefix = "/api", endpoint = "increment_count")]
pub async fn increment_count() -> Result<u32, ServerFnError<String>> {
    #[cfg(feature = "ssr")]
    {
        let count = update_count(true);
        println!("incremented count to {count}");
        return Ok(count);
    }
    #[cfg(not(feature = "ssr"))]
    Ok(0)
}

#[server(prefix = "/api", endpoint = "echo_len")]
pub async fn echo_len(value: String) -> Result<u32, ServerFnError<String>> {
    #[cfg(feature = "ssr")]
    {
        return Ok(u32::try_from(value.len()).unwrap_or(u32::MAX));
    }
    #[cfg(not(feature = "ssr"))]
    {
        let _ = value;
        Ok(0)
    }
}
