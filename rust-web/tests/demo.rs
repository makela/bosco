//! The demo's nightly reset against a real PostgreSQL, as in `site.rs`. Its
//! orders are the same as the IHP app's ResetDemo made for the same day and
//! time, which was checked side by side; here, what they are like.

use bosco_web::demo_data::{reset, seed_for};
use chrono::{DateTime, Utc};
use sqlx::PgPool;

type TestResult = Result<(), Box<dyn std::error::Error>>;

const IHP_SCHEMA: &str = r#"
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE TYPE JOB_STATUS AS ENUM ('job_status_not_started', 'job_status_running', 'job_status_failed', 'job_status_timed_out', 'job_status_succeeded', 'job_status_retry');
"#;

const FIXTURES: &str = include_str!("../../Application/Fixtures.sql");

async fn schema(db: &PgPool) -> TestResult {
    sqlx::raw_sql(IHP_SCHEMA).execute(db).await?;
    sqlx::raw_sql(include_str!("../../Application/Schema.sql"))
        .execute(db)
        .await?;
    Ok(())
}

async fn count(db: &PgPool, sql: &'static str) -> sqlx::Result<i64> {
    sqlx::query_scalar(sql).fetch_one(db).await
}

#[sqlx::test(migrations = false)]
async fn resets_the_demo(db: PgPool) -> TestResult {
    schema(&db).await?;
    // A login, kept; an order and a text change of the day before, gone
    sqlx::query("INSERT INTO users (email, password_hash) VALUES ('admin@demo.invalid', 'x')")
        .execute(&db)
        .await?;
    let now: DateTime<Utc> = "2026-11-11T15:04:05Z".parse()?;
    let orders = reset(&db, FIXTURES, seed_for(now), now).await?;
    assert!((100..130).contains(&orders), "{orders}");
    assert_eq!(
        count(&db, "SELECT COUNT(*) FROM orders").await?,
        orders as i64
    );
    assert_eq!(count(&db, "SELECT COUNT(*) FROM users").await?, 1);
    assert!(count(&db, "SELECT COUNT(*) FROM products").await? > 10);
    let payment: String = sqlx::query_scalar("SELECT text FROM payment_instructions")
        .fetch_one(&db)
        .await?;
    assert!(payment.contains("IBAN FI00 0000"));
    // Four seasons, the newest still being handled, nothing from the future
    let seasons: Vec<i32> = sqlx::query_scalar(
        "SELECT DISTINCT EXTRACT(YEAR FROM ordered_at)::int4 FROM orders ORDER BY 1",
    )
    .fetch_all(&db)
    .await?;
    assert_eq!(seasons, [2023, 2024, 2025, 2026]);
    assert!(count(&db, "SELECT COUNT(*) FROM orders WHERE paid_at IS NULL AND cancelled_at IS NULL AND ordered_at > '2026-11-01'").await? > 0);
    assert_eq!(
        count(&db, "SELECT COUNT(*) FROM orders WHERE greatest(ordered_at, invoiced_at, paid_at, delivered_at, cancelled_at) > '2026-11-11T15:04:05Z'").await?,
        0
    );
    // Five subscribers without orders
    assert_eq!(
        count(&db, "SELECT COUNT(*) FROM customers c WHERE NOT EXISTS (SELECT 1 FROM orders WHERE customer_id = c.id)").await?,
        5
    );

    // Again, the same day: the same orders, replacing the others
    let before: Vec<String> =
        sqlx::query_scalar("SELECT email || ordered_at FROM orders JOIN customers ON customers.id = customer_id ORDER BY 1")
            .fetch_all(&db)
            .await?;
    reset(&db, FIXTURES, seed_for(now), now).await?;
    let after: Vec<String> =
        sqlx::query_scalar("SELECT email || ordered_at FROM orders JOIN customers ON customers.id = customer_id ORDER BY 1")
            .fetch_all(&db)
            .await?;
    assert_eq!(before, after);
    Ok(())
}
