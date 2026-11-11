//! Runs the database's new migrations, as IHP's `migrate` (ihp-migrate):
//! each `<revision>….sql` in the migration directory not yet in
//! `schema_migrations` and newer than `MINIMUM_REVISION`, oldest first,
//! each in a transaction of its own with its revision recorded. It stops at
//! the first that fails, where IHP's went on to fail the rest. Its settings:
//!
//! - `DATABASE_URL`: the database
//! - `IHP_MIGRATION_DIR`: the migrations, `../Application/Migration/` by
//!   default
//! - `MINIMUM_REVISION`: older migrations are taken as part of the schema
//!   already, for a database made from an older Schema.sql

use std::collections::HashSet;
use std::env;
use std::path::Path;

use bosco_web::settings::setting;
use sqlx::postgres::PgPoolOptions;

/// A migration: its revision, the number its file name starts with
#[derive(Debug, PartialEq, Eq)]
struct Migration {
    revision: i64,
    file: String,
}

/// The migrations in the directory, oldest first; an error for two with
/// the same revision
fn migrations(dir: &Path) -> Result<Vec<Migration>, String> {
    let entries = std::fs::read_dir(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
    let mut migrations: Vec<Migration> = entries
        .filter_map(|entry| entry.ok()?.file_name().into_string().ok())
        .filter(|file| file.ends_with(".sql"))
        .filter_map(|file| {
            let digits: String = file.chars().take_while(char::is_ascii_digit).collect();
            Some(Migration {
                revision: digits.parse().ok()?,
                file,
            })
        })
        .collect();
    migrations.sort_by(|a, b| a.revision.cmp(&b.revision).then(a.file.cmp(&b.file)));
    let duplicates: Vec<String> = migrations
        .windows(2)
        .filter(|pair| pair[0].revision == pair[1].revision)
        .map(|pair| format!("  {}: {}, {}", pair[0].revision, pair[0].file, pair[1].file))
        .collect();
    if !duplicates.is_empty() {
        return Err(format!(
            "Multiple migrations use the same timestamp. Each migration filename needs a unique numeric prefix:\n{}",
            duplicates.join("\n")
        ));
    }
    Ok(migrations)
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let database_url = env::var("DATABASE_URL").map_err(|_| "DATABASE_URL not set")?;
    let dir = setting("IHP_MIGRATION_DIR", "../Application/Migration/");
    let minimum: i64 = match setting("MINIMUM_REVISION", "").trim() {
        "" => 0,
        text => text
            .parse()
            .map_err(|_| format!("MINIMUM_REVISION isn't a number: {text}"))?,
    };
    let migrations = migrations(Path::new(&dir))?;
    let db = PgPoolOptions::new()
        .max_connections(1)
        .connect(&database_url)
        .await?;
    sqlx::query("CREATE TABLE IF NOT EXISTS schema_migrations (revision BIGINT NOT NULL UNIQUE)")
        .execute(&db)
        .await?;
    let done: HashSet<i64> = sqlx::query_scalar("SELECT revision FROM schema_migrations")
        .fetch_all(&db)
        .await?
        .into_iter()
        .collect();
    for migration in migrations
        .iter()
        .filter(|m| m.revision > minimum && !done.contains(&m.revision))
    {
        let path = Path::new(&dir).join(&migration.file);
        let sql = std::fs::read_to_string(&path).map_err(|e| format!("{}: {e}", path.display()))?;
        let mut tx = db.begin().await?;
        sqlx::raw_sql(sqlx::AssertSqlSafe(sql))
            .execute(&mut *tx)
            .await
            .map_err(|e| format!("{}: {e}", migration.file))?;
        sqlx::query("INSERT INTO schema_migrations (revision) VALUES ($1)")
            .bind(migration.revision)
            .execute(&mut *tx)
            .await?;
        tx.commit().await?;
        println!("Migrated {}", migration.file);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_the_migrations_by_their_revision() {
        let dir = std::env::temp_dir().join(format!("bosco-migrate-test-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        for file in [
            "20.sql",
            "3-add-x.sql",
            "notes.txt",
            "README.sql",
            "100.sql",
        ] {
            std::fs::write(dir.join(file), "").unwrap();
        }
        let found = migrations(&dir).unwrap();
        assert_eq!(
            found
                .iter()
                .map(|m| (m.revision, m.file.as_str()))
                .collect::<Vec<_>>(),
            [(3, "3-add-x.sql"), (20, "20.sql"), (100, "100.sql")]
        );
        std::fs::write(dir.join("20-again.sql"), "").unwrap();
        assert!(
            migrations(&dir)
                .unwrap_err()
                .contains("20: 20-again.sql, 20.sql")
        );
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
