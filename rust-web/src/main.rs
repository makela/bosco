//! Runs the public site. Its settings, from the environment:
//!
//! - `DATABASE_URL`: the IHP app's database, e.g.
//!   `postgresql:///bosco_fi?host=/run/postgresql`
//! - `ADDR`: where to listen, `127.0.0.1:8003` by default
//! - `APP_LOCALE`: fi, en or fr, as for the IHP app
//! - `APP_DEMO`: 1 for a public demo
//! - `SEND_EMAILS`: 0 when the instance sends no emails, as the admin's
//!   order pages then say
//! - `STATIC_DIR`: the stylesheet, scripts and images, `../static` by
//!   default, where `just dev` builds the stylesheet; in production
//!   nix/rust-static.nix's
//! - `ASSET_VERSION`: in production, the static files' version, which the
//!   stylesheet's and scripts' addresses have
//! - `IHP_SESSION_SECRET_FILE`: the session cookies' key, by default
//!   `../.dev/session.aes`, where `just dev` keeps the development state;
//!   made if there's none. The name is the IHP app's, whose key it was
//! - `IHP_BASEURL`: the instance's address, e.g. `https://example.com`: the
//!   pages' og:url, and with https, the session cookie is only sent over
//!   HTTPS

use std::env;
use std::io::IsTerminal;
use std::sync::Arc;

use bosco_web::session::Key;
use bosco_web::settings::{flag, setting};
use bosco_web::{AppState, Site, app, l10n::Locale};
use sqlx::postgres::PgPoolOptions;
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| EnvFilter::new("info,tower_http=info")),
        )
        // Colours only in a terminal, not in the journal
        .with_ansi(std::io::stdout().is_terminal())
        .init();

    let locale = Locale::parse(&setting("APP_LOCALE", ""))?;
    let demo = flag("APP_DEMO", false)?;
    let database_url = env::var("DATABASE_URL").map_err(|_| "DATABASE_URL is not set")?;
    let addr = setting("ADDR", "127.0.0.1:8003");
    let session_key =
        Key::load_or_create(setting("IHP_SESSION_SECRET_FILE", "../.dev/session.aes").as_ref())?;
    let asset_version = Some(setting("ASSET_VERSION", "")).filter(|v| !v.is_empty());

    let db = PgPoolOptions::new()
        .max_connections(5)
        .connect(&database_url)
        .await?;
    let state = Arc::new(AppState {
        db,
        site: Site {
            locale,
            demo,
            asset_version,
            base_url: Some(setting("IHP_BASEURL", "")).filter(|url| !url.is_empty()),
        },
        static_dir: setting("STATIC_DIR", "../static").into(),
        session_key,
        secure_cookies: setting("IHP_BASEURL", "").starts_with("https://"),
        emails_enabled: flag("SEND_EMAILS", true)?,
    });

    let listener = tokio::net::TcpListener::bind(&addr).await?;
    tracing::info!("listening on http://{addr}");
    axum::serve(listener, app(state))
        .with_graceful_shutdown(async {
            let _ = tokio::signal::ctrl_c().await;
        })
        .await?;
    Ok(())
}
