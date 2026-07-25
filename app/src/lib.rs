use leptos::prelude::*;
use leptos_meta::{provide_meta_context, MetaTags, Stylesheet, Title};
use leptos_router::{
    path,
    components::{Route, Router, Routes},
    StaticSegment,
};

mod components;
mod pages;
pub mod auth;

use crate::components::Navbar;
use crate::pages::HomePage;

include!(concat!(env!("OUT_DIR"), "/i18n/mod.rs"));
use i18n::*;

pub fn shell(options: LeptosOptions) -> impl IntoView {
    view! {
        <!DOCTYPE html>
        <html lang="en">
            <head>
                <meta charset="utf-8"/>
                <meta name="viewport" content="width=device-width, initial-scale=1"/>
                <AutoReload options=options.clone()/>
                <HydrationScripts options/>
                <MetaTags/>
            </head>
            <body>
                <App/>
            </body>
        </html>
    }
}

#[component]
pub fn App() -> impl IntoView {
    // Provides context that manages stylesheets, titles, meta tags, etc.
    provide_meta_context();

    view! {
        <Stylesheet id="leptos" href="/pkg/open-picl.css"/>

        // sets the document title
        <Title text="OpenPICL | Open Photon Intelligence Comprehensive Laboratory"/>

        // content for this welcome page
        <I18nContextProvider>
            <Router>
                <Suspense fallback=move || view! { <div>Loading...</div> }>
                    <Navbar />
                </Suspense>

                <main>
                    <Routes fallback=|| "Page not found.".into_view()>
                        <Route path=StaticSegment("") view=HomePage/>
                        <Route path=path!("/home") view=HomePage/>
                    </Routes>
                </main>
            </Router>
        </I18nContextProvider>
    }
}
