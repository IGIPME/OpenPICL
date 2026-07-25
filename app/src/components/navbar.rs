use leptos::prelude::*;
use leptos_router::components::A;
use leptos_i18n::t;
use crate::i18n::use_i18n;
use crate::i18n::Locale;

#[component]
pub fn Navbar() -> impl IntoView {
    let i18n = use_i18n();

    let user = Resource::new_blocking(|| (), move |()| async {
        crate::auth::get_current_user().await.ok().flatten()
    });

    let (lang_open, set_lang_open) = signal(false);
    let (theme_open, set_theme_open) = signal(false);
    let current_lang = move || {
        let locale = i18n.get_locale();
        match locale {
            Locale::en => i18n.get_keys().lang_en().into_view(),
            Locale::zh_CN => i18n.get_keys().lang_zh().into_view(),
        }
    };
    let (current_theme, set_current_theme) = signal("light".to_string());
    let current_theme_name = move || {
        let theme = current_theme.get();
        match theme.as_str() {
            "light" => i18n.get_keys().theme_light().into_view(),
            "dark" => i18n.get_keys().theme_dark().into_view(),
            "system" => i18n.get_keys().theme_system().into_view(),
            _ => i18n.get_keys().theme_light().into_view(),
        }
    };

    view! {
        <nav class="navbar">
            <div class="navbar-left">
                <div class="logo-wrapper">
                    <A href="/">
                        <img src="/logo.png" alt="OpenPICL Logo" />
                    </A>
                </div>
                <div class="nav-links">
                    <A href="/home">
                        {t!(i18n, nav_home)}
                    </A>
                    <a href="https://docs.openpicl.com" target="_blank" rel="noopener noreferrer">
                        {t!(i18n, nav_docs)}
                    </a>
                    <a href="https://github.com/IGIPME/OpenPICL" target="_blank" rel="noopener noreferrer">
                        {t!(i18n, nav_github)}
                    </a>
                </div>
            </div>

            <div class="navbar-right">
                <div class="dropdown">
                    <button class="dropdown-trigger" on:click=move |_| {
                        set_lang_open.update(|v| *v = !*v);
                        set_theme_open.set(false);
                    }>
                        {current_lang}
                    </button>
                    <div class="dropdown-menu" class:open=move || lang_open.get()>
                        <button
                            on:click=move |_| {
                                i18n.set_locale(Locale::zh_CN);
                                set_lang_open.set(false);
                            } class:active=move || i18n.get_locale() == Locale::zh_CN
                        >
                            {move || i18n.get_keys().lang_zh().into_view()}
                        </button>
                        <button
                            on:click=move |_| {
                                i18n.set_locale(Locale::en);
                                set_lang_open.set(false);
                            } class:active=move || i18n.get_locale() == Locale::en
                        >
                            {move || i18n.get_keys().lang_en().into_view()}
                        </button>
                    </div>
                </div>

                <div class="dropdown">
                    <button class="dropdown-trigger" on:click=move |_| {
                        set_theme_open.update(|v| *v = !*v);
                        set_lang_open.set(false);
                    }>
                        {current_theme_name}
                    </button>
                    <div class="dropdown-menu" class:open=move || theme_open.get()>
                        <button on:click=move |_| {
                            set_current_theme.set("light".to_string());
                            set_theme_open.set(false);
                        } class:active=move || current_theme.get() == "light">
                            {move || i18n.get_keys().theme_light().into_view()}
                        </button>
                        <button on:click=move |_| {
                            set_current_theme.set("dark".to_string());
                            set_theme_open.set(false);
                        } class:active=move || current_theme.get() == "dark">
                            {move || i18n.get_keys().theme_dark().into_view()}
                        </button>
                        <button on:click=move |_| {
                            set_current_theme.set("system".to_string());
                            set_theme_open.set(false);
                        } class:active=move || current_theme.get() == "system">
                            {move || i18n.get_keys().theme_system().into_view()}
                        </button>
                    </div>
                </div>

                {move || match user.get() {
                    Some(Some(u)) => view! {
                        <span class="user-name">
                            {u.name.clone().unwrap_or_else(|| u.email.clone().unwrap_or(u.sub.clone()))}
                        </span>
                        <a class="logout-btn" href="/logout">
                            {t!(i18n, nav_logout)}
                        </a>
                    }.into_any(),
                    _ => view! {
                        <a class="login-btn" href="/login">
                            {t!(i18n, nav_login)}
                        </a>
                    }.into_any(),
                }}                
            </div>
        </nav>
    }
}
