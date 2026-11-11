//! Resets a public demo's data: the catalog from the fixtures, fake payment
//! details and a few seasons of made-up orders (`src/demo_data.rs`), as the
//! IHP app's `Application/Script/ResetDemo.hs`. Logins are kept. The NixOS
//! module runs it every night on an instance with demo = true and
//! rustWeb.enable. Its settings:
//!
//! - `DATABASE_URL`: the demo's database
//! - `APP_DEMO`: must be 1: it refuses to run otherwise, so it can't empty a
//!   real shop
//! - `APP_FIXTURES`: the fixtures file, `../Application/Fixtures.sql` by
//!   default

use std::env;

use bosco_web::demo_data::{reset, seed_for};
use bosco_web::settings::{flag, setting};
use sqlx::postgres::PgPoolOptions;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Checked before anything is done
    if !flag("APP_DEMO", false)? {
        return Err(
            "APP_DEMO is off: this would empty a real shop's orders. Not resetting.".into(),
        );
    }
    let path = setting("APP_FIXTURES", "../Application/Fixtures.sql");
    let fixtures = std::fs::read_to_string(&path).map_err(|e| format!("{path}: {e}"))?;
    let database_url = env::var("DATABASE_URL").map_err(|_| "DATABASE_URL is not set")?;
    let db = PgPoolOptions::new()
        .max_connections(1)
        .connect(&database_url)
        .await?;
    let now = chrono::Utc::now();
    let count = reset(&db, &fixtures, seed_for(now), now).await?;
    println!("Reset the demo: {count} orders");
    Ok(())
}
