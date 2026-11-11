//! Runs the public site. Its settings, from the environment:
//!
//! - `DATABASE_URL`: the IHP app's database, e.g.
//!   `postgresql:///bosco_fi?host=/run/postgresql`
//! - `ADDR`: where to listen, `127.0.0.1:8002` by default
//! - `APP_LOCALE`: fi, en or fr, as for the IHP app
//! - `APP_DEMO`: 1 for a public demo
//! - `STATIC_DIR`: the IHP app's `static/`, `../static` by default
//! - `STYLESHEET`: the stylesheet's URL, `/app.css` (the IHP app's dev
//!   build, see `devenv up`) by default

use std::env;
use std::sync::Arc;

use bosco_web::{AppState, Site, app, l10n::Locale};
use sqlx::postgres::PgPoolOptions;
use tracing_subscriber::EnvFilter;

fn setting(name: &str, default: &str) -> String {
    env::var(name).unwrap_or_else(|_| default.to_string())
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| EnvFilter::new("info,tower_http=info")),
        )
        .init();

    let locale = Locale::parse(&setting("APP_LOCALE", ""))?;
    let demo = match setting("APP_DEMO", "").as_str() {
        "1" | "true" => true,
        "" | "0" | "false" => false,
        other => return Err(format!("APP_DEMO should be 1 or 0, got {other}").into()),
    };
    let database_url = env::var("DATABASE_URL").map_err(|_| "DATABASE_URL is not set")?;
    let addr = setting("ADDR", "127.0.0.1:8002");

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
        },
        static_dir: setting("STATIC_DIR", "../static").into(),
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
