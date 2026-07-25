//! Logto OIDC integration for the Axum SSR server.
//!
//! Implements the Authorization Code Flow with PKCE against Logto's OIDC
//! endpoints. Sessions are held in the in-memory store exposed by
//! `app::auth::SESSIONS`, keyed by the `openpicl_sid` cookie.

use axum::extract::Query;
use axum::http::{header, HeaderMap, StatusCode};
use axum::response::{IntoResponse, Redirect, Response};
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use once_cell::sync::Lazy;
use rand::Rng;
use serde::Deserialize;
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::sync::RwLock;

use app::auth::{AuthSession, UserInfo};

const SESSION_COOKIE: &str = "openpicl_sid";
const SCOPES: &str = "openid profile email";

pub struct AuthConfig {
    pub endpoint: String,
    pub client_id: String,
    pub client_secret: String,
    pub redirect_uri: String,
    pub post_logout_uri: String,
}

impl AuthConfig {
    pub fn from_env() -> Self {
        Self {
            endpoint: env_or("LOGTO_ENDPOINT", "https://ufrjei.logto.app"),
            client_id: env_or("LOGTO_APP_ID", "17trhj5ohcsqrgh6ht241"),
            // The secret is the only value without a safe default. Fail with a
            // clear message at the first request (not at server start) so a
            // misconfigured instance still boots and serves the public pages,
            // and the error is visible in logs rather than a bare panic.
            client_secret: std::env::var("LOGTO_APP_SECRET").unwrap_or_else(|_| {
                log::error!(
                    "LOGTO_APP_SECRET is not set — Logto login will fail until it is provided"
                );
                String::new()
            }),
            // Default to the local dev server (leptos site-addr is 127.0.0.1:3000).
            // In production set LOGTO_REDIRECT_URI / LOGTO_POST_LOGOUT_URI to the
            // Zeabur URL (https://open-picl.zeabur.app[/callback]).
            redirect_uri: env_or("LOGTO_REDIRECT_URI", "http://localhost:3000/callback"),
            post_logout_uri: env_or("LOGTO_POST_LOGOUT_URI", "http://localhost:3000"),
        }
    }
}

fn env_or(key: &str, default: &str) -> String {
    std::env::var(key).unwrap_or_else(|_| default.to_string())
}

static CONFIG: Lazy<AuthConfig> = Lazy::new(AuthConfig::from_env);

/// Pending OAuth state -> PKCE verifier, kept only between /login and /callback.
struct Pending {
    code_verifier: String,
}

static PENDING: Lazy<RwLock<HashMap<String, Pending>>> =
    Lazy::new(|| RwLock::new(HashMap::new()));

fn random_token(n: usize) -> String {
    let mut rng = rand::rng();
    let bytes: Vec<u8> = (0..n).map(|_| rng.random::<u8>()).collect();
    URL_SAFE_NO_PAD.encode(&bytes)
}

/// Returns (code_verifier, code_challenge) for PKCE S256.
fn generate_pkce() -> (String, String) {
    let verifier = random_token(32);
    let mut hasher = Sha256::new();
    hasher.update(verifier.as_bytes());
    let challenge = URL_SAFE_NO_PAD.encode(hasher.finalize());
    (verifier, challenge)
}

fn parse_cookie<'a>(headers: &'a HeaderMap, name: &str) -> Option<&'a str> {
    let raw = headers.get(header::COOKIE)?.to_str().ok()?;
    let prefix = format!("{name}=");
    for pair in raw.split(';') {
        let pair = pair.trim();
        if let Some(rest) = pair.strip_prefix(prefix.as_str()) {
            return Some(rest);
        }
    }
    None
}

/// GET /login - redirect to Logto authorization endpoint with PKCE.
pub async fn login() -> Response {
    let cfg = &*CONFIG;
    let (verifier, challenge) = generate_pkce();
    let state = random_token(16);

    PENDING
        .write()
        .unwrap()
        .insert(state.clone(), Pending { code_verifier: verifier });

    let url = format!(
        "{endpoint}/oidc/auth?response_type=code&client_id={client_id}&redirect_uri={redirect_uri}&scope={scope}&state={state}&code_challenge={challenge}&code_challenge_method=S256",
        endpoint = cfg.endpoint,
        client_id = urlencoding::encode(&cfg.client_id),
        redirect_uri = urlencoding::encode(&cfg.redirect_uri),
        scope = urlencoding::encode(SCOPES),
        state = urlencoding::encode(&state),
        challenge = urlencoding::encode(&challenge),
    );
    Redirect::to(&url).into_response()
}

#[derive(Deserialize)]
pub struct CallbackParams {
    code: String,
    state: String,
}

/// GET /callback - validate state, exchange code, fetch userinfo, set session.
pub async fn callback(Query(params): Query<CallbackParams>) -> Result<Response, (StatusCode, String)> {
    let cfg = &*CONFIG;

    let pending = PENDING
        .write()
        .unwrap()
        .remove(&params.state)
        .ok_or((StatusCode::BAD_REQUEST, "invalid or expired state".to_string()))?;

    let token_url = format!("{}/oidc/token", cfg.endpoint);
    let token_res: serde_json::Value = reqwest::Client::new()
        .post(&token_url)
        .form(&[
            ("grant_type", "authorization_code"),
            ("code", params.code.as_str()),
            ("redirect_uri", cfg.redirect_uri.as_str()),
            ("client_id", cfg.client_id.as_str()),
            ("client_secret", cfg.client_secret.as_str()),
            ("code_verifier", pending.code_verifier.as_str()),
        ])
        .send()
        .await
        .map_err(|e| (StatusCode::BAD_GATEWAY, format!("token request failed: {e}")))?
        .json()
        .await
        .map_err(|e| (StatusCode::BAD_GATEWAY, format!("token decode failed: {e}")))?;

    let access_token = token_res["access_token"]
        .as_str()
        .ok_or((StatusCode::BAD_GATEWAY, "missing access_token".to_string()))?;
    let id_token = token_res["id_token"].as_str().map(String::from);

    let userinfo: serde_json::Value = reqwest::Client::new()
        .get(format!("{}/oidc/me", cfg.endpoint))
        .bearer_auth(access_token)
        .send()
        .await
        .map_err(|e| (StatusCode::BAD_GATEWAY, format!("userinfo request failed: {e}")))?
        .json()
        .await
        .map_err(|e| (StatusCode::BAD_GATEWAY, format!("userinfo decode failed: {e}")))?;

    let user = UserInfo {
        sub: userinfo["sub"].as_str().unwrap_or("").to_string(),
        name: userinfo["name"].as_str().map(String::from),
        email: userinfo["email"].as_str().map(String::from),
        picture: userinfo["picture"].as_str().map(String::from),
    };

    let sid = random_token(24);
    app::auth::SESSIONS
        .write()
        .unwrap()
        .insert(sid.clone(), AuthSession { user, id_token });

    let cookie = format!("{SESSION_COOKIE}={sid}; Path=/; HttpOnly; SameSite=Lax; Max-Age=86400");
    let mut response = Redirect::to("/").into_response();
    response
        .headers_mut()
        .insert(header::SET_COOKIE, cookie.parse().unwrap());
    Ok(response)
}

/// GET /logout - clear local session, redirect to Logto end-session endpoint.
pub async fn logout(headers: HeaderMap) -> Response {
    let cfg = &*CONFIG;
    let mut id_token_hint: Option<String> = None;

    if let Some(sid) = parse_cookie(&headers, SESSION_COOKIE) {
        if let Some(session) = app::auth::SESSIONS.write().unwrap().remove(sid) {
            id_token_hint = session.id_token;
        }
    }

    let mut url = format!(
        "{endpoint}/oidc/session/end?post_logout_redirect_uri={post_logout}",
        endpoint = cfg.endpoint,
        post_logout = urlencoding::encode(&cfg.post_logout_uri),
    );
    if let Some(hint) = id_token_hint {
        url.push_str("&id_token_hint=");
        url.push_str(&urlencoding::encode(&hint));
    }

    let clear_cookie = format!("{SESSION_COOKIE}=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0");
    let mut response = Redirect::to(&url).into_response();
    response
        .headers_mut()
        .insert(header::SET_COOKIE, clear_cookie.parse().unwrap());
    response
}
