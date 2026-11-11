//! Makes an admin login, or one with other roles: the IHP app's
//! `Application/Script/CreateUser.hs`. The email and password come from the
//! environment, so they never end up in a repository or the shell's history:
//!
//! ```sh
//! read -rs ADMIN_PASSWORD && export ADMIN_PASSWORD
//! ADMIN_EMAIL=you@example.com bosco-create-user
//! ```
//!
//! On a server, `bosco-<name>-create-user` runs it for the instance, see the
//! NixOS module. Its settings:
//!
//! - `DATABASE_URL`: the database
//! - `ADMIN_EMAIL`, `ADMIN_PASSWORD`: the login's
//! - `ROLES`: comma-separated, `admin` when not given, e.g.
//!   `ROLES=deliverer,promoter` for a delivery person who is also a promoter.
//!   See `src/permission.rs` for what each may do.

use std::env;

use bosco_web::{db, password, permission, settings::setting};
use sqlx::postgres::PgPoolOptions;

/// A setting that must be given, checked before anything is done
fn required(name: &str) -> Result<String, String> {
    match env::var(name) {
        Ok(value) if !value.trim().is_empty() => Ok(value),
        _ => Err(format!(
            "Set {name}, see bosco-create-user's source or the README"
        )),
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let roles = permission::parse_roles(&setting("ROLES", "admin"))?;
    let email = required("ADMIN_EMAIL")?;
    let password = required("ADMIN_PASSWORD")?;
    let database_url = env::var("DATABASE_URL").map_err(|_| "DATABASE_URL is not set")?;
    let db = PgPoolOptions::new()
        .max_connections(1)
        .connect(&database_url)
        .await?;
    if db::login_exists(&db, &email).await? {
        return Err(format!("A user {email} exists already").into());
    }
    let hash = password::hash(&password);
    db::create_login(&db, &email, &hash, roles).await?;
    let names: Vec<&str> = [
        ("admin", roles.admin),
        ("deliverer", roles.deliverer),
        ("promoter", roles.promoter),
    ]
    .into_iter()
    .filter_map(|(name, has)| has.then_some(name))
    .collect();
    println!("Created {email} with the roles {}", names.join(", "));
    Ok(())
}
