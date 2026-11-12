//! The email worker against a real PostgreSQL, as in `site.rs`: a job is
//! worked as IHP's job runner works it. Run with `./test.sh`.

use std::time::Duration;

use bosco_web::db::{self, NewCustomer, Product};
use bosco_web::l10n::Locale;
use bosco_web::worker::{MAX_ATTEMPTS, Mailer, Outcome, Worker};
use lettre::transport::stub::AsyncStubTransport;
use sqlx::PgPool;
use uuid::Uuid;

type TestResult = Result<(), Box<dyn std::error::Error>>;

/// What IHP put in a database before the app's schema
const IHP_SCHEMA: &str = include_str!("../../db/IHPSchema.sql");

/// The schema, a product and payment instructions
async fn shop(db: &PgPool) -> Result<Product, Box<dyn std::error::Error>> {
    sqlx::raw_sql(IHP_SCHEMA).execute(db).await?;
    sqlx::raw_sql(include_str!("../../Application/Schema.sql"))
        .execute(db)
        .await?;
    let producer: Uuid = sqlx::query_scalar(
        "INSERT INTO producers (name, subject, description)
         VALUES ('Bosco Falconeria', '', '') RETURNING id",
    )
    .fetch_one(db)
    .await?;
    sqlx::query("INSERT INTO payment_instructions (text) VALUES ('Pay to FI12 3456')")
        .execute(db)
        .await?;
    Ok(sqlx::query_as(
        "INSERT INTO products (producer_id, name, description, package, price)
         VALUES ($1, 'Olive oil', '', '3 l', 5100)
         RETURNING id, producer_id, name, description, package, price, ordering",
    )
    .bind(producer)
    .fetch_one(db)
    .await?)
}

/// An order, made as the site makes them, with its email job
async fn order(db: &PgPool, product: &Product) -> sqlx::Result<Uuid> {
    let customer = NewCustomer {
        first_name: "Anna".into(),
        last_name: "Virtanen".into(),
        email: "anna@example.com".into(),
        phone: "040 123 4567".into(),
        street_address: "Testikatu 1".into(),
        postal_code: "00100".into(),
        city: "Helsinki".into(),
        ..NewCustomer::default()
    };
    db::create_order(db, &customer, &[(product, 2)], true).await
}

#[derive(Debug, sqlx::FromRow)]
struct Job {
    id: Uuid,
    status: String,
    attempts_count: i32,
    locked_by: Option<Uuid>,
    last_error: Option<String>,
    /// Seconds from now to run_at
    due_in: f64,
}

async fn jobs(db: &PgPool) -> sqlx::Result<Vec<Job>> {
    sqlx::query_as(
        "SELECT id, status::text, attempts_count, locked_by, last_error,
                EXTRACT(EPOCH FROM run_at - NOW())::float8 AS due_in
         FROM email_order_jobs ORDER BY created_at",
    )
    .fetch_all(db)
    .await
}

fn worker(db: &PgPool, mailer: Mailer) -> Worker {
    Worker::new(db.clone(), Locale::En, mailer)
}

#[sqlx::test(migrations = false)]
async fn sends_the_order_email(db: PgPool) -> TestResult {
    let product = shop(&db).await?;
    order(&db, &product).await?;
    let stub = AsyncStubTransport::new_ok();
    let worker = worker(&db, Mailer::Stub(stub.clone()));

    let (job, outcome) = worker.run_next().await?.ok_or("no job")?;
    assert_eq!(outcome, Outcome::Succeeded);
    let [done] = &jobs(&db).await?[..] else {
        panic!("one job")
    };
    assert_eq!(done.id, job);
    assert_eq!(done.status, "job_status_succeeded");
    assert_eq!(done.attempts_count, 1);
    assert_eq!(done.locked_by, None);

    let sent = stub.messages().await;
    let [(envelope, message)] = &sent[..] else {
        panic!("one email")
    };
    assert_eq!(envelope.to()[0].to_string(), "anna@example.com");
    assert!(message.contains("Subject: Bosco Falconeria Olive Oil Order"));
    assert!(message.contains("Pay to FI12 3456"), "{message}");

    assert!(worker.run_next().await?.is_none(), "nothing left");
    Ok(())
}

#[sqlx::test(migrations = false)]
async fn takes_the_oldest_job_first(db: PgPool) -> TestResult {
    let product = shop(&db).await?;
    let first = order(&db, &product).await?;
    order(&db, &product).await?;
    let worker = worker(&db, Mailer::Stub(AsyncStubTransport::new_ok()));
    let (job, _) = worker.run_next().await?.ok_or("no job")?;
    let order_id: Uuid = sqlx::query_scalar("SELECT order_id FROM email_order_jobs WHERE id = $1")
        .bind(job)
        .fetch_one(&db)
        .await?;
    assert_eq!(order_id, first);
    Ok(())
}

#[sqlx::test(migrations = false)]
async fn a_failed_email_is_tried_again_30_seconds_later(db: PgPool) -> TestResult {
    let product = shop(&db).await?;
    order(&db, &product).await?;
    let worker = worker(&db, Mailer::Stub(AsyncStubTransport::new_error()));

    let (_, outcome) = worker.run_next().await?.ok_or("no job")?;
    assert_eq!(outcome, Outcome::Retry("stub error".into()));
    let [job] = &jobs(&db).await?[..] else {
        panic!("one job")
    };
    assert_eq!(job.status, "job_status_retry");
    assert_eq!(job.last_error.as_deref(), Some("stub error"));
    assert_eq!(job.locked_by, None);
    assert!((25.0..=30.0).contains(&job.due_in), "due in {}", job.due_in);
    assert!(worker.run_next().await?.is_none(), "not due yet");
    Ok(())
}

#[sqlx::test(migrations = false)]
async fn gives_up_after_10_tries(db: PgPool) -> TestResult {
    let product = shop(&db).await?;
    order(&db, &product).await?;
    sqlx::query("UPDATE email_order_jobs SET status = 'job_status_retry', attempts_count = $1")
        .bind(MAX_ATTEMPTS - 1)
        .execute(&db)
        .await?;
    let worker = worker(&db, Mailer::Stub(AsyncStubTransport::new_error()));

    let (_, outcome) = worker.run_next().await?.ok_or("no job")?;
    assert_eq!(outcome, Outcome::Failed("stub error".into()));
    let [job] = &jobs(&db).await?[..] else {
        panic!("one job")
    };
    assert_eq!(job.status, "job_status_failed");
    assert_eq!(job.attempts_count, 10);
    assert!(worker.run_next().await?.is_none());
    Ok(())
}

#[sqlx::test(migrations = false)]
async fn with_emails_off_only_logs_it(db: PgPool) -> TestResult {
    let product = shop(&db).await?;
    order(&db, &product).await?;
    let (_, outcome) = worker(&db, Mailer::Off).run_next().await?.ok_or("no job")?;
    assert_eq!(outcome, Outcome::Succeeded);
    assert_eq!(jobs(&db).await?[0].status, "job_status_succeeded");
    Ok(())
}

#[sqlx::test(migrations = false)]
async fn leaves_a_job_another_worker_has(db: PgPool) -> TestResult {
    let product = shop(&db).await?;
    order(&db, &product).await?;
    sqlx::query(
        "UPDATE email_order_jobs
         SET status = 'job_status_running', locked_by = $1, locked_at = NOW()",
    )
    .bind(Uuid::from_u128(1))
    .execute(&db)
    .await?;
    let worker = worker(&db, Mailer::Stub(AsyncStubTransport::new_ok()));
    assert!(worker.run_next().await?.is_none());
    Ok(())
}

#[sqlx::test(migrations = false)]
async fn takes_back_jobs_a_stopped_worker_left(db: PgPool) -> TestResult {
    let product = shop(&db).await?;
    let recent = order(&db, &product).await?;
    let stale = order(&db, &product).await?;
    let ancient = order(&db, &product).await?;
    for (order_id, locked) in [
        (recent, "1 minute"),
        (stale, "11 minutes"),
        (ancient, "2 days"),
    ] {
        sqlx::query(
            "UPDATE email_order_jobs
             SET status = 'job_status_running', locked_by = $2,
                 locked_at = NOW() - $3::interval
             WHERE order_id = $1",
        )
        .bind(order_id)
        .bind(Uuid::from_u128(1))
        .bind(locked)
        .execute(&db)
        .await?;
    }
    worker(&db, Mailer::Off).recover_stale().await?;

    let statuses: Vec<String> =
        sqlx::query_scalar("SELECT status::text FROM email_order_jobs ORDER BY created_at")
            .fetch_all(&db)
            .await?;
    assert_eq!(
        statuses,
        [
            "job_status_running",
            "job_status_retry",
            "job_status_failed"
        ]
    );
    Ok(())
}

/// The worker running, as the service runs it: a new order wakes it at once
/// through IHP's trigger, not at its next look a minute later
#[sqlx::test(migrations = false)]
async fn a_new_order_wakes_the_worker(db: PgPool) -> TestResult {
    let product = shop(&db).await?;
    let stub = AsyncStubTransport::new_ok();
    let (stop, stopped) = tokio::sync::oneshot::channel::<()>();
    let running = tokio::spawn(worker(&db, Mailer::Stub(stub.clone())).run(async {
        let _ = stopped.await;
    }));
    // Waits until it listens, which is when it has installed the trigger
    for _ in 0..50 {
        let listening: bool = sqlx::query_scalar(
            "SELECT EXISTS (SELECT 1 FROM pg_stat_activity WHERE query LIKE 'LISTEN%')",
        )
        .fetch_one(&db)
        .await?;
        if listening {
            break;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }

    order(&db, &product).await?;
    for _ in 0..50 {
        if jobs(&db).await?[0].status == "job_status_succeeded" {
            break;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    assert_eq!(jobs(&db).await?[0].status, "job_status_succeeded");
    assert_eq!(stub.messages().await.len(), 1);

    stop.send(()).map_err(|()| "stopped already")?;
    running.await??;
    Ok(())
}
