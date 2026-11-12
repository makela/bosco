//! The email worker, the IHP app's `Web/Job/EmailOrder.hs` and IHP's job
//! queue: it sends the order email of each job in `email_order_jobs`, which
//! orders put there (both the IHP app's and the Rust site's).
//!
//! It works the table as IHP's job runner does, so either can take a job,
//! and both could run at once:
//! - a job is taken with `FOR UPDATE SKIP LOCKED`, marked running and
//!   locked by this worker, and its attempt counted
//! - a failed one is tried again 30 seconds later, 10 times in all, and is
//!   then left failed, with the error in `last_error`
//! - one left running for 10 minutes (its worker stopped midway) is tried
//!   again, or marked failed after a day
//! - new jobs wake the worker through IHP's trigger and channel
//!   (`job_available_email_order_jobs`), and it looks for jobs every minute
//!   too, in case it missed a notice

use std::future::Future;
use std::time::Duration;

use lettre::transport::smtp::authentication::Credentials;
use lettre::transport::stub::AsyncStubTransport;
use lettre::{AsyncSendmailTransport, AsyncSmtpTransport, AsyncTransport, Message, Tokio1Executor};
use sqlx::PgPool;
use sqlx::postgres::PgListener;
use uuid::Uuid;

use crate::db;
use crate::l10n::Locale;
use crate::mail::{Addresses, order_mail};

/// Tries of a job before it's left failed, IHP's default
pub const MAX_ATTEMPTS: i32 = 10;
/// Seconds between tries, IHP's default
pub const RETRY_AFTER: i32 = 30;
/// Seconds a job may stay running before it's taken as abandoned, IHP's
/// default
pub const STALE_AFTER: i32 = 600;
/// How often to look for jobs without a notice, IHP's default
const POLL: Duration = Duration::from_secs(60);
const CHANNEL: &str = "job_available_email_order_jobs";

/// How the emails go out
pub enum Mailer {
    Smtp(AsyncSmtpTransport<Tokio1Executor>),
    /// The local sendmail, as the IHP app without SMTP_HOST (development)
    Sendmail(AsyncSendmailTransport<Tokio1Executor>),
    /// They don't: the worker only logs them (SEND_EMAILS=0)
    Off,
    /// For tests: keeps them, or fails as told
    Stub(AsyncStubTransport),
}

/// How the SMTP connection is secured, as the module's smtp.encryption
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Encryption {
    StartTls,
    Tls,
    None,
}

impl Encryption {
    pub fn parse(text: &str) -> Result<Self, String> {
        match text {
            "starttls" => Ok(Self::StartTls),
            "tls" => Ok(Self::Tls),
            "none" => Ok(Self::None),
            other => Err(format!(
                "SMTP_ENCRYPTION should be starttls, tls or none, got {other}"
            )),
        }
    }
}

impl Mailer {
    pub fn smtp(
        host: &str,
        port: u16,
        encryption: Encryption,
        login: Option<(String, String)>,
    ) -> Result<Self, lettre::transport::smtp::Error> {
        let builder = match encryption {
            Encryption::StartTls => AsyncSmtpTransport::<Tokio1Executor>::starttls_relay(host)?,
            Encryption::Tls => AsyncSmtpTransport::<Tokio1Executor>::relay(host)?,
            Encryption::None => AsyncSmtpTransport::<Tokio1Executor>::builder_dangerous(host),
        };
        let builder = builder.port(port);
        let builder = match login {
            Some((user, password)) => builder.credentials(Credentials::new(user, password)),
            None => builder,
        };
        Ok(Self::Smtp(builder.build()))
    }

    pub fn sendmail() -> Self {
        Self::Sendmail(AsyncSendmailTransport::new())
    }

    async fn send(&self, message: Message) -> Result<(), String> {
        match self {
            Self::Smtp(smtp) => smtp
                .send(message)
                .await
                .map(drop)
                .map_err(|e| e.to_string()),
            Self::Sendmail(sendmail) => sendmail.send(message).await.map_err(|e| e.to_string()),
            Self::Stub(stub) => stub.send(message).await.map_err(|e| e.to_string()),
            Self::Off => Ok(()),
        }
    }
}

pub struct Worker {
    pub db: PgPool,
    pub locale: Locale,
    pub mailer: Mailer,
    /// Who the emails are from, and where replies go
    pub addresses: Addresses,
    /// Marks the jobs this worker has taken (`locked_by`)
    pub id: Uuid,
}

/// What became of a job
#[derive(Debug, PartialEq, Eq)]
pub enum Outcome {
    Succeeded,
    /// Failed, to be tried again
    Retry(String),
    /// Failed for the last time
    Failed(String),
}

impl Worker {
    pub fn new(db: PgPool, locale: Locale, mailer: Mailer) -> Self {
        Self {
            db,
            locale,
            mailer,
            addresses: Addresses::default(),
            id: Uuid::new_v4(),
        }
    }

    /// Takes the next job that is due, if any, and does it
    pub async fn run_next(&self) -> sqlx::Result<Option<(Uuid, Outcome)>> {
        let Some((job, order_id, attempts)): Option<(Uuid, Uuid, i32)> = sqlx::query_as(
            "UPDATE email_order_jobs
             SET status = 'job_status_running', locked_at = NOW(), locked_by = $1,
                 attempts_count = attempts_count + 1
             WHERE id IN (
                 SELECT id FROM email_order_jobs
                 WHERE (status = 'job_status_not_started' OR status = 'job_status_retry')
                   AND locked_by IS NULL AND run_at <= NOW()
                 ORDER BY created_at LIMIT 1 FOR UPDATE SKIP LOCKED)
             RETURNING id, order_id, attempts_count",
        )
        .bind(self.id)
        .fetch_optional(&self.db)
        .await?
        else {
            return Ok(None);
        };

        let outcome = match self.perform(order_id).await {
            Ok(()) => {
                sqlx::query(
                    "UPDATE email_order_jobs
                     SET status = 'job_status_succeeded', locked_by = NULL, updated_at = NOW()
                     WHERE id = $1",
                )
                .bind(job)
                .execute(&self.db)
                .await?;
                tracing::info!(%job, %order_id, "sent the order email");
                Outcome::Succeeded
            }
            Err(error) => {
                let retry = attempts < MAX_ATTEMPTS;
                sqlx::query(
                    "UPDATE email_order_jobs
                     SET status = $2::job_status, locked_by = NULL, updated_at = NOW(),
                         last_error = $3,
                         run_at = CASE WHEN $4 THEN NOW() + make_interval(secs => $5)
                                       ELSE run_at END
                     WHERE id = $1",
                )
                .bind(job)
                .bind(if retry {
                    "job_status_retry"
                } else {
                    "job_status_failed"
                })
                .bind(&error)
                .bind(retry)
                .bind(f64::from(RETRY_AFTER))
                .execute(&self.db)
                .await?;
                tracing::warn!(%job, %order_id, attempts, retry, "the order email failed: {error}");
                if retry {
                    Outcome::Retry(error)
                } else {
                    Outcome::Failed(error)
                }
            }
        };
        Ok(Some((job, outcome)))
    }

    /// Sends the order's email
    async fn perform(&self, order_id: Uuid) -> Result<(), String> {
        let invoice = db::invoice(&self.db, order_id)
            .await
            .map_err(|e| e.to_string())?
            .ok_or_else(|| format!("no order {order_id}"))?;
        let instruction = db::payment_instruction(&self.db)
            .await
            .map_err(|e| e.to_string())?;
        if let Mailer::Off = self.mailer {
            tracing::info!(
                "Emails are off for this instance: not sending order {order_id} to {}",
                invoice.order.customer.email
            );
            return Ok(());
        }
        let message = order_mail(
            &self.addresses,
            self.locale,
            &invoice,
            instruction.as_deref(),
        )?;
        self.mailer.send(message).await
    }

    /// Jobs left running by a worker that stopped: tried again, or, after a
    /// day, marked failed
    pub async fn recover_stale(&self) -> sqlx::Result<()> {
        sqlx::query(
            "UPDATE email_order_jobs
             SET status = 'job_status_retry', locked_by = NULL, locked_at = NULL, run_at = NOW()
             WHERE status = 'job_status_running'
               AND locked_at < NOW() - make_interval(secs => $1)
               AND locked_at > NOW() - interval '1 day'",
        )
        .bind(f64::from(STALE_AFTER))
        .execute(&self.db)
        .await?;
        sqlx::query(
            "UPDATE email_order_jobs
             SET status = 'job_status_failed', locked_by = NULL, locked_at = NULL,
                 last_error = 'Stale job: worker likely crashed'
             WHERE status = 'job_status_running' AND locked_at < NOW() - interval '1 day'",
        )
        .execute(&self.db)
        .await?;
        Ok(())
    }

    /// Does every job that is due
    async fn run_due(&self) {
        loop {
            match self.run_next().await {
                Ok(Some(_)) => {}
                Ok(None) => return,
                Err(error) => {
                    tracing::error!("taking a job: {error}");
                    tokio::time::sleep(Duration::from_secs(1)).await;
                    return;
                }
            }
        }
    }

    /// Works the queue until `shutdown`, finishing the job at hand first
    pub async fn run(self, shutdown: impl Future<Output = ()>) -> sqlx::Result<()> {
        // IHP's trigger, the same as its worker installs, so orders wake this
        // one even where IHP's worker has never run
        if let Err(error) = sqlx::raw_sql(NOTIFY_TRIGGER).execute(&self.db).await {
            tracing::warn!("couldn't install the job trigger, looking every minute: {error}");
        }
        let mut listener = PgListener::connect_with(&self.db).await?;
        listener.listen(CHANNEL).await?;
        tracing::info!(worker = %self.id, "waiting for jobs");

        let mut poll = tokio::time::interval(POLL);
        let mut stale = tokio::time::interval(Duration::from_secs((STALE_AFTER / 2) as u64));
        tokio::pin!(shutdown);
        loop {
            self.run_due().await;
            tokio::select! {
                () = &mut shutdown => return Ok(()),
                notice = listener.recv() => {
                    if let Err(error) = notice {
                        tracing::error!("listening for jobs: {error}");
                        tokio::time::sleep(Duration::from_secs(1)).await;
                    }
                }
                _ = poll.tick() => {}
                _ = stale.tick() => {
                    if let Err(error) = self.recover_stale().await {
                        tracing::error!("recovering stale jobs: {error}");
                    }
                }
            }
        }
    }
}

/// IHP's `createNotificationTriggerSQL` for this table, word for word
const NOTIFY_TRIGGER: &str = r#"DO $$
BEGIN
    CREATE OR REPLACE FUNCTION notify_job_queued_email_order_jobs() RETURNS TRIGGER AS $BODY$BEGIN
    PERFORM pg_notify('job_available_email_order_jobs', '');
    RETURN new;
END;
$BODY$ language plpgsql;
    DROP TRIGGER IF EXISTS did_insert_job_email_order_jobs ON email_order_jobs;
    CREATE TRIGGER did_insert_job_email_order_jobs AFTER INSERT ON "email_order_jobs" FOR EACH ROW WHEN (NEW.status = 'job_status_not_started' OR NEW.status = 'job_status_retry') EXECUTE PROCEDURE notify_job_queued_email_order_jobs();
    DROP TRIGGER IF EXISTS did_update_job_email_order_jobs ON email_order_jobs;
    CREATE TRIGGER did_update_job_email_order_jobs AFTER UPDATE ON "email_order_jobs" FOR EACH ROW WHEN (NEW.status = 'job_status_not_started' OR NEW.status = 'job_status_retry') EXECUTE PROCEDURE notify_job_queued_email_order_jobs();
EXCEPTION
    WHEN SQLSTATE 'XX000' THEN null; -- 'tuple concurrently updated': another connection installed it first
END; $$"#;
