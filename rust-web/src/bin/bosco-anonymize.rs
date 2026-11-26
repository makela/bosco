//! Clears the customers past the accounting period, as the privacy notice
//! promises (`db::anonymize_due`): 10 years from the end of their newest
//! order's year. The NixOS module runs it every night. Its setting:
//!
//! - `DATABASE_URL`: the instance's database

use std::env;

use sqlx::postgres::PgPoolOptions;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let database_url = env::var("DATABASE_URL").map_err(|_| "DATABASE_URL is not set")?;
    let db = PgPoolOptions::new()
        .max_connections(1)
        .connect(&database_url)
        .await?;
    let count = bosco_web::db::anonymize_due(&db).await?;
    println!("Anonymized {count} customers past the accounting period");
    Ok(())
}
