use leptos_i18n_build::{Config, TranslationsInfos};
use std::error::Error;

fn main() -> Result<(), Box<dyn Error>> {
    let config = Config::new("zh-CN")?
        .add_locale("en")?
        .locales_path("../locales");

    let translations = TranslationsInfos::parse(config)?;

    let out_dir = std::env::var("OUT_DIR")?;
    translations.generate_i18n_module(std::path::Path::new(&out_dir).join("i18n"))?;

    Ok(())
}