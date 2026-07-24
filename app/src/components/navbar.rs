use leptos::prelude::*;
use leptos_router::components::A;

#[component]
pub fn Navbar() -> impl IntoView {
    // 语言下拉菜单状态
    let (lang_open, set_lang_open) = signal(false);
    // 主题下拉菜单状态
    let (theme_open, set_theme_open) = signal(false);
    // 当前选中的语言
    let (current_lang, set_current_lang) = signal("简体中文".to_string());
    // 当前选中的主题
    let (current_theme, set_current_theme) = signal("浅色".to_string());

    // 点击外部关闭下拉菜单
    view! {
        <nav class="navbar">
            {/* 左侧区域 */}
            <div class="navbar-left">
                <div class="logo-wrapper">
                    <A href="/">
                        <img src="/logo.png" alt="OpenPICL Logo" />
                    </A>
                </div>
                <div class="nav-links">
                    <A href="/home">主页</A>
                    <a href="https://docs.openpicl.com" target="_blank" rel="noopener noreferrer">文档</a>
                    <a href="https://github.com/IGIPME/OpenPICL" target="_blank" rel="noopener noreferrer">GitHub</a>
                </div>
            </div>

            {/* 右侧区域 */}
            <div class="navbar-right">
                {/* 语言下拉菜单 */}
                <div class="dropdown"
                    on:mouseenter=move |_| set_lang_open.set(true)
                    on:mouseleave=move |_| set_lang_open.set(false)
                >
                    <button class="dropdown-trigger" on:click=move |_| {
                        set_lang_open.update(|v| *v = !*v);
                    }>
                        {move || current_lang.get()}
                    </button>
                    <div class="dropdown-menu" class:open=move || lang_open.get()>
                        <button on:click=move |_| {
                            set_current_lang.set("简体中文".to_string());
                            set_lang_open.set(false);
                        } class:active=move || current_lang.get() == "简体中文">
                            简体中文
                        </button>
                        <button on:click=move |_| {
                            set_current_lang.set("English".to_string());
                            set_lang_open.set(false);
                        } class:active=move || current_lang.get() == "English">
                            English
                        </button>
                    </div>
                </div>

                {/* 主题下拉菜单 */}
                <div class="dropdown"
                    on:mouseenter=move |_| set_theme_open.set(true)
                    on:mouseleave=move |_| set_theme_open.set(false)
                >
                    <button class="dropdown-trigger" on:click=move |_| {
                        set_theme_open.update(|v| *v = !*v);
                    }>
                        {move || current_theme.get()}
                    </button>
                    <div class="dropdown-menu" class:open=move || theme_open.get()>
                        <button on:click=move |_| {
                            set_current_theme.set("浅色".to_string());
                            set_theme_open.set(false);
                        } class:active=move || current_theme.get() == "浅色">
                            浅色
                        </button>
                        <button on:click=move |_| {
                            set_current_theme.set("深色".to_string());
                            set_theme_open.set(false);
                        } class:active=move || current_theme.get() == "深色">
                            深色
                        </button>
                        <button on:click=move |_| {
                            set_current_theme.set("跟随系统".to_string());
                            set_theme_open.set(false);
                        } class:active=move || current_theme.get() == "跟随系统">
                            跟随系统
                        </button>
                    </div>
                </div>

                {/* 登录按钮 */}
                <button class="login-btn">
                    <A href="/login">登录</A>
                </button>
            </div>
        </nav>
    }
}