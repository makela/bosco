//! Sends the order emails, as the IHP app's RunJobs does, see
//! `bosco_web::worker`. Its settings, from the environment:
//!
//! - `DATABASE_URL`: the IHP app's database, as for `bosco-web`
//! - `APP_LOCALE`: fi, en or fr, the emails' language
//! - `SEND_EMAILS`: 0 to only log the emails; 1 by default
//! - `APP_DEMO`: 1 for a public demo, which mustn't send emails
//! - `SMTP_HOST`: the SMTP server; without it, the local `sendmail`
//! - `SMTP_PORT` (587 by default), `SMTP_ENCRYPTION` (starttls, tls or
//!   none; starttls by default), `SMTP_USER` and `SMTP_PASSWORD_FILE`
//! - `MAIL_FROM`: who the emails are from, `postmaster@localhost` by
//!   default; `MAIL_REPLY_TO`: where replies go, none by default. Either an
//!   address or "Some Name <someone@example.com>"

use std::fs;
use std::io::IsTerminal;

use bosco_web::l10n::Locale;
use bosco_web::mail::Addresses;
use bosco_web::settings::{flag, setting};
use bosco_web::worker::{Encryption, Mailer, Worker};
use sqlx::postgres::PgPoolOptions;
use tokio::signal::unix::{SignalKind, signal};
use tracing_subscriber::EnvFilter;

fn mailer() -> Result<Mailer, Box<dyn std::error::Error>> {
    if !flag("SEND_EMAILS", true)? {
        return Ok(Mailer::Off);
    }
    if flag("APP_DEMO", false)? {
        return Err("a demo (APP_DEMO=1) needs SEND_EMAILS=0".into());
    }
    let host = setting("SMTP_HOST", "");
    if host.is_empty() {
        return Ok(Mailer::sendmail());
    }
    let port = setting("SMTP_PORT", "587")
        .parse()
        .map_err(|_| "SMTP_PORT should be a port number")?;
    let encryption = Encryption::parse(&setting("SMTP_ENCRYPTION", "starttls"))?;
    let login = match (setting("SMTP_USER", ""), setting("SMTP_PASSWORD_FILE", "")) {
        (user, _) if user.is_empty() => None,
        (_, file) if file.is_empty() => return Err("SMTP_USER needs SMTP_PASSWORD_FILE".into()),
        (user, file) => {
            let password =
                fs::read_to_string(&file).map_err(|e| format!("SMTP_PASSWORD_FILE {file}: {e}"))?;
            Some((user, password.trim().to_string()))
        }
    };
    Ok(Mailer::smtp(&host, port, encryption, login)?)
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| EnvFilter::new("info,sqlx::postgres::notice=warn")),
        )
        // Colours only in a terminal, not in the journal
        .with_ansi(std::io::stdout().is_terminal())
        .init();

    let locale = Locale::parse(&setting("APP_LOCALE", ""))?;
    let mailer = mailer()?;
    let addresses = Addresses::parse(
        std::env::var("MAIL_FROM").ok().as_deref(),
        std::env::var("MAIL_REPLY_TO").ok().as_deref(),
    )?;
    let database_url = std::env::var("DATABASE_URL").map_err(|_| "DATABASE_URL is not set")?;
    let db = PgPoolOptions::new()
        .max_connections(3)
        .connect(&database_url)
        .await?;

    // systemd stops it with SIGTERM; the job at hand is finished first
    let mut terminate = signal(SignalKind::terminate())?;
    let shutdown = async move {
        tokio::select! {
            _ = terminate.recv() => {}
            _ = tokio::signal::ctrl_c() => {}
        }
        tracing::info!("stopping");
    };
    let mut worker = Worker::new(db, locale, mailer);
    worker.addresses = addresses;
    worker.run(shutdown).await?;
    Ok(())
}
