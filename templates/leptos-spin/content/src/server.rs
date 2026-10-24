#[cfg(feature = "trusted-ingress")]
use std::sync::OnceLock;

use crate::app::{App, GetCount, IncrementCount};
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
    use wasi_auth::http::{
        AUTH_CONTEXT_HEADER, REQUEST_ID_HEADER, strip_untrusted_auth_metadata,
    };

    let has_envelope = request.headers().contains_key(AUTH_CONTEXT_HEADER);
    let has_credential = request.headers().contains_key(http::header::AUTHORIZATION)
        || request.headers().contains_key(http::header::COOKIE);
    if !has_envelope && !has_credential {
        strip_untrusted_auth_metadata(request.headers_mut());
        return Ok(());
    }

    let codec = ingress_codec().map_err(|()| http::StatusCode::SERVICE_UNAVAILABLE)?;
    let envelope = single_header(request.headers(), &AUTH_CONTEXT_HEADER)
        .ok_or(http::StatusCode::UNAUTHORIZED)?;
    let request_id = single_header(request.headers(), &REQUEST_ID_HEADER)
        .ok_or(http::StatusCode::UNAUTHORIZED)?;
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|_| http::StatusCode::SERVICE_UNAVAILABLE)?
        .as_secs();
    codec
        .open(
            envelope,
            request.method(),
            request.uri().path(),
            request_id,
            now,
        )
        .map_err(|_| http::StatusCode::UNAUTHORIZED)?;

    // The ingress already authenticated. Drop the envelope and credentials so
    // application code cannot authenticate a second time from wire headers.
    strip_untrusted_auth_metadata(request.headers_mut());
    request.headers_mut().remove(http::header::AUTHORIZATION);
    request.headers_mut().remove(http::header::COOKIE);
    Ok(())
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
fn single_header<'a>(
    headers: &'a http::HeaderMap,
    name: &http::HeaderName,
) -> Option<&'a str> {
    let mut values = headers.get_all(name).iter();
    let value = values.next()?.to_str().ok()?;
    if values.next().is_some() || value.is_empty() {
        return None;
    }
    Some(value)
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
