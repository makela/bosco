//! The IHP app's static files (`static/`, or its built `bosco-static`):
//! the stylesheets, the scripts, the logo and the favicon, at `/…` and, as
//! the IHP app serves them, at `/static/…`.
//!
//! In the Nix store every file has the same date, so a date says nothing
//! about whether it changed: the files carry a hash of their content as
//! their ETag instead, and no date. An address with a version
//! (`/static/prod.css?v=…`, which changes with every build) may be kept
//! for a year, as the IHP app let it; one without, such as the logo's,
//! is asked about again each time, and a file that hasn't changed is a
//! 304 without its content.

use std::path::{Component, Path, PathBuf};

use axum::body::Body;
use axum::http::{HeaderMap, HeaderValue, StatusCode, Uri, header};
use axum::response::{IntoResponse, Response};
use base64::Engine;
use base64::engine::general_purpose::STANDARD as BASE64;
use sha2::{Digest, Sha256};

/// The file the address names in `dir`, if there's one: `/static/` or not,
/// and nothing outside `dir`
fn file_of(dir: &Path, uri_path: &str) -> Option<PathBuf> {
    let path = uri_path.strip_prefix("/static").unwrap_or(uri_path);
    let mut file = dir.to_path_buf();
    for part in path.split('/').filter(|part| !part.is_empty()) {
        let part = percent_decode(part)?;
        match Path::new(&part).components().collect::<Vec<_>>()[..] {
            [Component::Normal(name)] => file.push(name),
            _ => return None,
        }
    }
    file.is_file().then_some(file)
}

fn percent_decode(text: &str) -> Option<String> {
    let bytes = text.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' {
            let hex = std::str::from_utf8(bytes.get(i + 1..i + 3)?).ok()?;
            out.push(u8::from_str_radix(hex, 16).ok()?);
            i += 3;
        } else {
            out.push(bytes[i]);
            i += 1;
        }
    }
    String::from_utf8(out).ok()
}

/// The response for a static file, or None when there's no such file
pub async fn serve(dir: &Path, uri: &Uri, headers: &HeaderMap) -> Option<Response> {
    let file = file_of(dir, uri.path())?;
    let content = tokio::fs::read(&file).await.ok()?;
    let etag = format!("\"{}\"", BASE64.encode(&Sha256::digest(&content)[..16]));
    let versioned = uri
        .query()
        .is_some_and(|query| query.split('&').any(|item| item.starts_with("v=")));
    let cache = if versioned {
        "public, max-age=31536000, immutable"
    } else {
        "no-cache"
    };
    let unchanged = headers
        .get_all(header::IF_NONE_MATCH)
        .iter()
        .filter_map(|value| value.to_str().ok())
        .flat_map(|value| value.split(','))
        .any(|tag| tag.trim().trim_start_matches("W/") == etag);
    let mut response = if unchanged {
        StatusCode::NOT_MODIFIED.into_response()
    } else {
        let kind = mime_guess::from_path(&file).first_or_octet_stream();
        let mut response = Body::from(content).into_response();
        response.headers_mut().insert(
            header::CONTENT_TYPE,
            HeaderValue::from_str(kind.as_ref()).expect("a MIME type is a header value"),
        );
        response
    };
    let headers = response.headers_mut();
    headers.insert(
        header::ETAG,
        HeaderValue::from_str(&etag).expect("base64 is a header value"),
    );
    headers.insert(header::CACHE_CONTROL, HeaderValue::from_static(cache));
    Some(response)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dir() -> PathBuf {
        PathBuf::from(concat!(env!("CARGO_MANIFEST_DIR"), "/../static"))
    }

    #[test]
    fn finds_files_at_both_addresses_and_nothing_outside() {
        assert!(file_of(&dir(), "/img/logo.jpg").is_some());
        assert_eq!(
            file_of(&dir(), "/static/img/logo.jpg"),
            file_of(&dir(), "/img/logo.jpg")
        );
        assert!(file_of(&dir(), "/static/img/../img/logo.jpg").is_none());
        assert!(file_of(&dir(), "/%2e%2e/flake.nix").is_none());
        assert!(file_of(&dir(), "/img").is_none(), "a directory");
        assert!(file_of(&dir(), "/nothing.css").is_none());
    }

    #[tokio::test]
    async fn caches_by_content_and_version() {
        let uri = |text: &str| text.parse::<Uri>().unwrap();
        let first = serve(&dir(), &uri("/img/logo.jpg"), &HeaderMap::new())
            .await
            .unwrap();
        assert_eq!(first.status(), StatusCode::OK);
        assert_eq!(first.headers()[header::CONTENT_TYPE], "image/jpeg");
        assert_eq!(first.headers()[header::CACHE_CONTROL], "no-cache");
        assert!(first.headers().get(header::LAST_MODIFIED).is_none());
        let etag = first.headers()[header::ETAG].clone();

        let mut asking = HeaderMap::new();
        asking.insert(header::IF_NONE_MATCH, etag);
        let again = serve(&dir(), &uri("/static/img/logo.jpg?v=abc"), &asking)
            .await
            .unwrap();
        assert_eq!(again.status(), StatusCode::NOT_MODIFIED);
        assert_eq!(
            again.headers()[header::CACHE_CONTROL],
            "public, max-age=31536000, immutable"
        );
    }
}
