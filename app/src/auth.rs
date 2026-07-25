use cfg_if::cfg_if;

#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct UserInfo {
    pub sub: String,
    pub name: Option<String>,
    pub email: Option<String>,
    pub picture: Option<String>,
}

#[cfg(feature = "ssr")]
#[derive(Clone, Debug)]
pub struct AuthSession {
    pub user: UserInfo,
    pub id_token: Option<String>,
}

cfg_if! {
    if #[cfg(feature = "ssr")] {
        use once_cell::sync::Lazy;
        use std::collections::HashMap;
        use std::sync::RwLock;

        /// In-memory session store keyed by the `openpicl_sid` cookie value.
        /// Sufficient for single-instance dev; replace with Redis/DB for production.
        pub static SESSIONS: Lazy<RwLock<HashMap<String, AuthSession>>> =
            Lazy::new(|| RwLock::new(HashMap::new()));

        pub fn get_user_by_cookie_value(sid: &str) -> Option<UserInfo> {
            SESSIONS.read().ok()?.get(sid).map(|s| s.user.clone())
        }

        pub fn current_user_from_headers(headers: &http::HeaderMap) -> Option<UserInfo> {
            let raw = headers.get(http::header::COOKIE)?.to_str().ok()?;
            for pair in raw.split(';') {
                let pair = pair.trim();
                if let Some(sid) = pair.strip_prefix("openpicl_sid=") {
                    return get_user_by_cookie_value(sid);
                }
            }
            None
        }
    }
}

#[leptos::server(GetCurrentUser)]
pub async fn get_current_user() -> Result<Option<UserInfo>, leptos::server_fn::ServerFnError> {
    #[cfg(feature = "ssr")]
    {
        use leptos_axum::extract;
        let headers: http::HeaderMap = extract().await?;
        Ok(current_user_from_headers(&headers))
    }
    #[cfg(not(feature = "ssr"))]
    {
        #[allow(unreachable_code)]
        Ok(None)
    }
}
