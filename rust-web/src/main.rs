//! Runs the public site. Its settings, from the environment:
//!
//! - `DATABASE_URL`: the IHP app's database, e.g.
//!   `postgresql:///bosco_fi?host=/run/postgresql`
//! - `ADDR`: where to listen, `127.0.0.1:8003` by default
//! - `APP_LOCALE`: fi, en or fr, as for the IHP app
//! - `APP_DEMO`: 1 for a public demo
//! - `STATIC_DIR`: the IHP app's `static/`, `../static` by default
//! - `STYLESHEET`: the stylesheet's URL, `/app.css` (the IHP app's dev
//!   build, see `devenv up`) by default
//! - `ASSET_VERSION`: in production, the IHP app's static files' version,
//!   which the admin's addresses of them have (`IHP_ASSET_VERSION`)
//! - `IHP_SESSION_SECRET_FILE`: the IHP app's session key, by default
//!   `../Config/client_session_key.aes` as in its development; made if
//!   there's none, as IHP does
//! - `IHP_BASEURL`: the IHP app's, e.g. `https://bosco.makela.in`: with
//!   https, the session cookie is only sent over HTTPS

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
    let session_key = Key::load_or_create(
        setting(
            "IHP_SESSION_SECRET_FILE",
            "../Config/client_session_key.aes",
        )
        .as_ref(),
    )?;
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
            stylesheet: setting("STYLESHEET", "/app.css"),
            asset_version,
        },
        static_dir: setting("STATIC_DIR", "../static").into(),
        session_key,
        secure_cookies: setting("IHP_BASEURL", "").starts_with("https://"),
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
