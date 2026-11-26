//! Reloading the browser in development, as IHP's dev server did: the dev
//! pages load `static/dev-reload.js`, which asks `/dev/reload` every second
//! and reloads the page when the answer changes. It changes when the site
//! restarts (`just dev` rebuilds and restarts it on a code change) and when
//! a static file changes (Tailwind rewriting `app.css`). Production, which
//! has an asset version (`Site::development`), has neither the route nor
//! the script.

use std::path::Path;
use std::sync::{Arc, OnceLock};
use std::time::{SystemTime, UNIX_EPOCH};

use axum::Router;
use axum::extract::State;
use axum::http::header;
use axum::response::IntoResponse;
use axum::routing::get;

use crate::AppState;

pub fn routes() -> Router<Arc<AppState>> {
    Router::new().route("/dev/reload", get(version))
}

/// This run of the site and its static files: the moment it first answered
/// and the newest file's time
async fn version(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    static STARTED: OnceLock<u128> = OnceLock::new();
    let started = *STARTED.get_or_init(|| nanos(SystemTime::now()));
    let newest = newest(&state.static_dir);
    (
        [(header::CACHE_CONTROL, "no-store")],
        format!("{started}-{newest}"),
    )
}

fn nanos(time: SystemTime) -> u128 {
    time.duration_since(UNIX_EPOCH)
        .map_or(0, |since| since.as_nanos())
}

/// The newest modification time of the files under `dir`
fn newest(dir: &Path) -> u128 {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return 0;
    };
    entries
        .flatten()
        .map(|entry| match entry.file_type() {
            Ok(kind) if kind.is_dir() => newest(&entry.path()),
            _ => entry
                .metadata()
                .and_then(|metadata| metadata.modified())
                .map_or(0, nanos),
        })
        .max()
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn notices_a_changed_file_in_a_subdirectory() {
        let dir = std::env::temp_dir().join(format!("dev-reload-{}", std::process::id()));
        std::fs::create_dir_all(dir.join("vendor")).unwrap();
        let file = dir.join("vendor/app.css");
        std::fs::write(&file, "a").unwrap();
        let set = |secs| {
            std::fs::File::options()
                .write(true)
                .open(&file)
                .unwrap()
                .set_modified(UNIX_EPOCH + std::time::Duration::from_secs(secs))
                .unwrap();
        };
        set(1_000);
        let before = newest(&dir);
        set(2_000);
        let after = newest(&dir);
        std::fs::remove_dir_all(&dir).unwrap();
        assert!(after > before);
        assert_eq!(newest(&dir), 0, "a missing directory");
    }
}
