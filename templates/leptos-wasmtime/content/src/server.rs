#[cfg(feature = "trusted-ingress")]
use std::sync::OnceLock;

use crate::app::{App, EchoLen, GetCount, IncrementCount};
use leptos::config::get_configuration;
use leptos_wasi::wasip3::prelude::{
    Handler, RegistrationError, RouteTable, init_wasip3_spawner,
};
use wasip3::http::types::{ErrorCode, Request, Response};

// `init_wasip3_spawner` is what calls the wasip3 task hook. wasip3 0.8+
// renamed `spawn` to `spawn_local`; that call site lives in leptos_wasi,
// which is why the guest pins a runtime that has already made the rename.
thread_local! {
    static ROUTES: Result<RouteTable, RegistrationError> =
        RouteTable::discover(App, None, || {});
}

struct LeptosServer;

impl wasip3::exports::http::handler::Guest for LeptosServer {
    async fn handle(request: Request) -> Result<Response, ErrorCode> {
        init_wasip3_spawner().map_err(internal_error)?;

        let conf = get_configuration(None).map_err(internal_error)?;
        let leptos_options = conf.leptos_options;
        // `mut` is only required when the trusted-ingress feature rewrites headers.
        #[allow(unused_mut)]
        let mut request = wasip3::http_compat::http_from_wasi_request(request)?;

        // The trusted-ingress feature is a different binary. The default
        // component does not inspect or emit auth, CORS, or security headers.
        #[cfg(feature = "trusted-ingress")]
        if let Err(status) = enforce_trusted_ingress(&mut request) {
            return boundary_response(status);
        }

        let routes = ROUTES.with(Clone::clone).map_err(internal_error)?;

        Handler::build(request)
            .await
            .map_err(handler_error)?
            .static_files_handler("/pkg", serve_static_files)
            .map_err(internal_error)?
            .with_server_fn::<GetCount>()
            .with_server_fn::<IncrementCount>()
            .with_server_fn::<EchoLen>()
            .generate_routes_from(&routes)
            .map_err(internal_error)?
            .handle_with_context(move || crate::app::shell(leptos_options.clone()), || {})
            .await
            .map_err(handler_error)
    }
}

fn handler_error(error: leptos_wasi::wasip3::HandlerError) -> ErrorCode {
    eprintln!("leptos_wasi error: {error}");
    error.into_error_code()
}

fn serve_static_files(path: String) -> Option<leptos_wasi::response::Body> {
    let path = path.trim_start_matches('/');
    let file_path = format!("/site/pkg/{path}");
    match std::fs::read(&file_path) {
        Ok(bytes) => Some(leptos_wasi::response::Body::Sync(bytes.into())),
        Err(_) => None,
    }
}

fn internal_error(error: impl std::fmt::Display) -> ErrorCode {
    eprintln!("leptos_wasi error: {error}");
    ErrorCode::InternalError(None)
}

#[cfg(feature = "trusted-ingress")]
fn enforce_trusted_ingress<B>(
    request: &mut http::Request<B>,
) -> Result<(), http::StatusCode> {
    use wasi_auth::http::{accept_signed_trusted_context, strip_untrusted_auth_metadata};

    // Anonymous requests never load the key. A credential or an envelope does,
    // so a missing key fails closed before the HMAC check.
    if !trusted_material_present(request.headers()) {
        strip_untrusted_auth_metadata(request.headers_mut());
        return Ok(());
    }

    let codec = ingress_codec().map_err(|()| http::StatusCode::SERVICE_UNAVAILABLE)?;
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|_| http::StatusCode::SERVICE_UNAVAILABLE)?
        .as_secs();
    // Verifies the HMAC binding and consumes the envelope so a second
    // presentation in this process is rejected. The function also strips the
    // envelope and caller credentials before Leptos runs.
    accept_signed_trusted_context(codec, request, now)
        .map(|_| ())
        .map_err(|_| http::StatusCode::UNAUTHORIZED)
}

#[cfg(feature = "trusted-ingress")]
fn trusted_material_present(headers: &http::HeaderMap) -> bool {
    headers.contains_key(wasi_auth::http::AUTH_CONTEXT_HEADER)
        || headers.contains_key(http::header::AUTHORIZATION)
        || headers.contains_key(http::header::PROXY_AUTHORIZATION)
        || headers.get_all(http::header::COOKIE).iter().any(|value| {
            value.to_str().is_ok_and(|text| {
                text.split(';').any(|part| {
                    let name = part
                        .trim()
                        .split_once('=')
                        .map(|(name, _)| name.trim())
                        .unwrap_or("");
                    name == "__Host-session" || name == "wasi_auth_dev_session"
                })
            })
        })
}

#[cfg(feature = "trusted-ingress")]
fn ingress_codec() -> Result<&'static wasi_auth::http::TrustedContextCodec, ()> {
    use wasi_auth::http::TrustedContextCodec;

    static CODEC: OnceLock<Result<TrustedContextCodec, ()>> = OnceLock::new();
    match CODEC.get_or_init(load_ingress_codec) {
        Ok(codec) => Ok(codec),
        Err(()) => Err(()),
    }
}

#[cfg(feature = "trusted-ingress")]
fn load_ingress_codec() -> Result<wasi_auth::http::TrustedContextCodec, ()> {
    use base64::Engine as _;
    use wasi_auth::http::TrustedContextCodec;

    let encoded = std::env::var("AUTH_TRUSTED_INGRESS_KEY_BASE64").map_err(|_| ())?;
    let key_bytes = base64::engine::general_purpose::STANDARD
        .decode(encoded.trim())
        .map_err(|_| ())?;
    let key: [u8; 32] = key_bytes.try_into().map_err(|_| ())?;
    let audience = std::env::var("AUTH_TRUSTED_INGRESS_AUDIENCE")
        .unwrap_or_else(|_| "fullstack-app".to_string());
    let mut codec = TrustedContextCodec::new(audience, key).map_err(|_| ())?;
    if let Ok(raw) = std::env::var("AUTH_TRUSTED_INGRESS_MAX_AGE_SECONDS") {
        let max_age: u64 = raw.trim().parse().map_err(|_| ())?;
        codec = codec.with_max_age_seconds(max_age).map_err(|_| ())?;
    }
    Ok(codec)
}

#[cfg(feature = "trusted-ingress")]
fn boundary_response(status: http::StatusCode) -> Result<Response, ErrorCode> {
    let mut response = http::Response::new(http_body_util::Full::new(bytes::Bytes::new()));
    *response.status_mut() = status;
    response.headers_mut().insert(
        http::header::CACHE_CONTROL,
        http::HeaderValue::from_static("no-store"),
    );
    response.headers_mut().insert(
        http::header::CONTENT_LENGTH,
        http::HeaderValue::from_static("0"),
    );
    wasip3::http_compat::http_into_wasi_response(response)
}

wasip3::http::service::export!(LeptosServer);
