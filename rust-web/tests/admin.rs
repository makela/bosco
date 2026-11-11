//! The admin's login and logout against a real PostgreSQL, as in `site.rs`:
//! what IHP's sessions controller does, with IHP's session cookie. Run with
//! `./test.sh`.

use std::path::PathBuf;
use std::sync::Arc;

use axum::Router;
use axum::body::Body;
use axum::http::{HeaderMap, HeaderValue, Method, Request, Response, StatusCode, header};
use bosco_web::l10n::Locale;
use bosco_web::session::{self, FLASH_ERROR, FLASH_SUCCESS, Key, REDIRECT_AFTER_LOGIN, Session};
use bosco_web::{AppState, Site, app};
use http_body_util::BodyExt;
use sqlx::PgPool;
use tower::ServiceExt;
use uuid::Uuid;

type TestResult = Result<(), Box<dyn std::error::Error>>;

const IHP_SCHEMA: &str = r#"
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE TYPE JOB_STATUS AS ENUM ('job_status_not_started', 'job_status_running', 'job_status_failed', 'job_status_timed_out', 'job_status_succeeded', 'job_status_retry');
"#;

/// "salasana", hashed by IHP (pwstore-fast)
const SALASANA: &str =
    "sha256|17|MDEyMzQ1Njc4OWFiY2RlZg==|pjd4FtSmTigPFEAxWJsMLlyZhWffudNA3BVqtAMHHmg=";

fn key() -> Key {
    Key::from_bytes(&(0..96).collect::<Vec<u8>>()).unwrap()
}

/// The schema and an admin, Admin@Example.com with the password "salasana"
async fn admin(db: &PgPool) -> Result<Uuid, Box<dyn std::error::Error>> {
    sqlx::raw_sql(IHP_SCHEMA).execute(db).await?;
    sqlx::raw_sql(include_str!("../../Application/Schema.sql"))
        .execute(db)
        .await?;
    Ok(sqlx::query_scalar(
        "INSERT INTO users (email, password_hash, is_admin)
         VALUES ('Admin@Example.com', $1, true) RETURNING id",
    )
    .bind(SALASANA)
    .fetch_one(db)
    .await?)
}

fn site(db: PgPool, demo: bool) -> Router {
    app(Arc::new(AppState {
        db,
        site: Site {
            locale: Locale::Fi,
            demo,
            stylesheet: "/app.css".into(),
            asset_version: Some("v1".into()),
        },
        static_dir: PathBuf::from(concat!(env!("CARGO_MANIFEST_DIR"), "/../static")),
        session_key: key(),
        secure_cookies: false,
    }))
}

/// A request, with the session as its cookie
async fn send(
    app: &Router,
    method: Method,
    uri: &str,
    session: &Session,
    form: &[(&str, &str)],
) -> Result<Response<Body>, Box<dyn std::error::Error>> {
    let body = form
        .iter()
        .map(|(name, value)| format!("{name}={}", value.replace('@', "%40")))
        .collect::<Vec<_>>()
        .join("&");
    let request = Request::builder()
        .method(method)
        .uri(uri)
        .header(header::CONTENT_TYPE, "application/x-www-form-urlencoded")
        .header(
            header::COOKIE,
            format!("{}={}", session::COOKIE, session.encrypt(&key())),
        )
        .body(Body::from(body))?;
    Ok(app.clone().oneshot(request).await?)
}

async fn login(
    app: &Router,
    session: &Session,
    email: &str,
    password: &str,
) -> Result<Response<Body>, Box<dyn std::error::Error>> {
    send(
        app,
        Method::POST,
        "/admin/CreateSession",
        session,
        &[("email", email), ("password", password)],
    )
    .await
}

/// The session the response saved; `before` if it saved none
fn session_after(response: &Response<Body>, before: &Session) -> Session {
    let Some(set) = response.headers().get(header::SET_COOKIE) else {
        return before.clone();
    };
    let value = set.to_str().unwrap().split(';').next().unwrap();
    let mut headers = HeaderMap::new();
    headers.insert(header::COOKIE, HeaderValue::from_str(value).unwrap());
    Session::from_headers(&key(), &headers)
}

fn location(response: &Response<Body>) -> &str {
    response.headers()[header::LOCATION].to_str().unwrap()
}

async fn text(response: Response<Body>) -> Result<String, Box<dyn std::error::Error>> {
    Ok(String::from_utf8(
        response.into_body().collect().await?.to_bytes().to_vec(),
    )?)
}

#[derive(Debug, PartialEq, sqlx::FromRow)]
struct Login {
    failed_login_attempts: i32,
    locked: bool,
}

async fn state_of(db: &PgPool, user: Uuid) -> sqlx::Result<Login> {
    sqlx::query_as(
        "SELECT failed_login_attempts, locked_at IS NOT NULL AS locked FROM users WHERE id = $1",
    )
    .bind(user)
    .fetch_one(db)
    .await
}

#[sqlx::test(migrations = false)]
async fn the_login_page_is_the_ihp_apps(db: PgPool) -> TestResult {
    admin(&db).await?;
    let response = send(
        &site(db, false),
        Method::GET,
        "/admin/NewSession",
        &Session::default(),
        &[],
    )
    .await?;
    assert_eq!(response.status(), StatusCode::OK);
    assert!(response.headers().get(header::SET_COOKIE).is_none());
    let page = text(response).await?;
    assert!(page.contains("<title>Manage Bosco Falconeria</title>"));
    assert!(page.contains(r#"<link rel="stylesheet" href="/static/app.css?v=v1">"#));
    assert!(page.contains(r#"<script src="/static/prod.js?v=v1"></script>"#));
    assert!(page.contains(r#"<form method="POST" action="/admin/CreateSession">"#));
    assert!(page.contains(
        r#"<input name="email" value="" type="email" class="form-control" placeholder="E-Mail" required="required" autofocus="autofocus">"#
    ));
    assert!(!page.contains("demo"), "{page}");
    Ok(())
}

#[sqlx::test(migrations = false)]
async fn a_demos_login_page_has_its_logins(db: PgPool) -> TestResult {
    admin(&db).await?;
    let response = send(
        &site(db, true),
        Method::GET,
        "/admin/NewSession",
        &Session::default(),
        &[],
    )
    .await?;
    let page = text(response).await?;
    assert!(page.contains("<title>[Demo] Manage Bosco Falconeria</title>"));
    assert!(page.contains(r#"<meta name="robots" content="noindex, nofollow">"#));
    assert!(page.contains(r#"<div class="demo-ribbon" aria-hidden="true">DEMO</div>"#));
    assert!(page.contains(
        r#"<form method="POST" action="/admin/DemoLogin?role=orders"><button type="submit" class="btn-small">Delivery person</button></form>"#
    ));
    Ok(())
}

/// IHP sends to the login page with a message, which shows once
#[sqlx::test(migrations = false)]
async fn shows_the_ihp_apps_message_once(db: PgPool) -> TestResult {
    admin(&db).await?;
    let app = site(db, false);
    let mut session = Session::default();
    session.set_text(FLASH_SUCCESS, "Please log in to access this page");
    let response = send(&app, Method::GET, "/admin/NewSession", &session, &[]).await?;
    let after = session_after(&response, &session);
    assert!(text(response).await?.contains(
        r#"<div class="bg-green-100 border border-green-500 text-green-900 px-4 py-3 rounded relative">Please log in to access this page</div>"#
    ));
    assert_eq!(after.get_text(FLASH_SUCCESS), None);
    Ok(())
}

#[sqlx::test(migrations = false)]
async fn logs_in_whatever_the_emails_case(db: PgPool) -> TestResult {
    let user = admin(&db).await?;
    sqlx::query("UPDATE users SET failed_login_attempts = 3")
        .execute(&db)
        .await?;
    let app = site(db.clone(), false);
    let response = login(&app, &Session::default(), "admin@EXAMPLE.com", "salasana").await?;
    assert_eq!(response.status(), StatusCode::SEE_OTHER);
    // IHP's afterLoginRedirectPath, when no admin page sent here
    assert_eq!(location(&response), "/");
    let session = session_after(&response, &Session::default());
    assert_eq!(session.user_id(), Some(user));
    assert_eq!(
        state_of(&db, user).await?,
        Login {
            failed_login_attempts: 0,
            locked: false
        }
    );
    Ok(())
}

/// The admin page IHP sent to the login page is where the login goes
#[sqlx::test(migrations = false)]
async fn goes_back_to_the_page_asked_for(db: PgPool) -> TestResult {
    admin(&db).await?;
    let app = site(db, false);
    let mut session = Session::default();
    session.set_text(REDIRECT_AFTER_LOGIN, "/admin/Orders?page=2");
    let response = login(&app, &session, "admin@example.com", "salasana").await?;
    assert_eq!(location(&response), "/admin/Orders?page=2");
    let after = session_after(&response, &session);
    assert_eq!(after.get_text(REDIRECT_AFTER_LOGIN), None);
    Ok(())
}

#[sqlx::test(migrations = false)]
async fn a_wrong_password_is_counted(db: PgPool) -> TestResult {
    let user = admin(&db).await?;
    let app = site(db.clone(), false);
    let response = login(&app, &Session::default(), "admin@example.com", "Salasana").await?;
    assert_eq!(response.status(), StatusCode::FOUND);
    assert_eq!(location(&response), "/admin/NewSession");
    let session = session_after(&response, &Session::default());
    assert_eq!(session.user_id(), None);
    assert_eq!(
        session.get_text(FLASH_ERROR).as_deref(),
        Some("Invalid Credentials")
    );
    assert_eq!(
        state_of(&db, user).await?,
        Login {
            failed_login_attempts: 1,
            locked: false
        }
    );

    // The message on the login page
    let response = send(&app, Method::GET, "/admin/NewSession", &session, &[]).await?;
    assert!(text(response).await?.contains(
        r#"<div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded relative">Invalid Credentials</div>"#
    ));
    Ok(())
}

#[sqlx::test(migrations = false)]
async fn an_unknown_email_is_the_same_message(db: PgPool) -> TestResult {
    admin(&db).await?;
    let response = login(
        &site(db, false),
        &Session::default(),
        "nobody@example.com",
        "salasana",
    )
    .await?;
    assert_eq!(response.status(), StatusCode::FOUND);
    let session = session_after(&response, &Session::default());
    assert_eq!(
        session.get_text(FLASH_ERROR).as_deref(),
        Some("Invalid Credentials")
    );
    Ok(())
}

#[sqlx::test(migrations = false)]
async fn locks_for_an_hour_after_10_wrong_passwords(db: PgPool) -> TestResult {
    let user = admin(&db).await?;
    let app = site(db.clone(), false);
    for _ in 0..9 {
        login(&app, &Session::default(), "admin@example.com", "wrong").await?;
    }
    assert_eq!(
        state_of(&db, user).await?,
        Login {
            failed_login_attempts: 9,
            locked: false
        }
    );
    login(&app, &Session::default(), "admin@example.com", "wrong").await?;
    assert_eq!(
        state_of(&db, user).await?,
        Login {
            failed_login_attempts: 10,
            locked: true
        }
    );

    // Even the right password
    let response = login(&app, &Session::default(), "admin@example.com", "salasana").await?;
    assert_eq!(response.status(), StatusCode::FOUND);
    let session = session_after(&response, &Session::default());
    assert_eq!(session.user_id(), None);
    assert_eq!(
        session.get_text(FLASH_ERROR).as_deref(),
        Some("User is locked")
    );

    // An hour later the right one logs in; a wrong one would lock again at
    // once, as in IHP, the count being past 10
    sqlx::query("UPDATE users SET locked_at = NOW() - interval '61 minutes'")
        .execute(&db)
        .await?;
    login(&app, &Session::default(), "admin@example.com", "wrong").await?;
    assert_eq!(
        state_of(&db, user).await?,
        Login {
            failed_login_attempts: 11,
            locked: true
        }
    );
    sqlx::query("UPDATE users SET locked_at = NOW() - interval '61 minutes'")
        .execute(&db)
        .await?;
    let response = login(&app, &Session::default(), "admin@example.com", "salasana").await?;
    assert_eq!(response.status(), StatusCode::SEE_OTHER);
    assert_eq!(state_of(&db, user).await?.failed_login_attempts, 0);
    Ok(())
}

#[sqlx::test(migrations = false)]
async fn without_a_password_is_a_bad_request(db: PgPool) -> TestResult {
    admin(&db).await?;
    let response = send(
        &site(db, false),
        Method::POST,
        "/admin/CreateSession",
        &Session::default(),
        &[("email", "admin@example.com")],
    )
    .await?;
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    Ok(())
}

/// The admin's logout link POSTs `_method=DELETE`; the rest of the session
/// stays
#[sqlx::test(migrations = false)]
async fn logs_out(db: PgPool) -> TestResult {
    let user = admin(&db).await?;
    let app = site(db, false);
    let mut session = Session::default();
    session.login(user);
    session.set_text(b"other", "kept");
    for (method, form) in [
        (Method::POST, &[("_method", "DELETE")][..]),
        (Method::DELETE, &[]),
    ] {
        let response = send(&app, method, "/admin/DeleteSession", &session, form).await?;
        assert_eq!(response.status(), StatusCode::SEE_OTHER);
        assert_eq!(location(&response), "/admin/NewSession");
        let after = session_after(&response, &session);
        assert_eq!(after.user_id(), None);
        assert_eq!(after.get_text(b"other").as_deref(), Some("kept"));
    }
    for method in [Method::GET, Method::POST] {
        let response = send(&app, method, "/admin/DeleteSession", &session, &[]).await?;
        assert_eq!(response.status(), StatusCode::METHOD_NOT_ALLOWED);
    }
    Ok(())
}

#[sqlx::test(migrations = false)]
async fn a_demo_logs_in_with_a_button(db: PgPool) -> TestResult {
    admin(&db).await?;
    let app = site(db.clone(), true);
    let response = send(
        &app,
        Method::POST,
        "/admin/DemoLogin?role=orders",
        &Session::default(),
        &[],
    )
    .await?;
    assert_eq!(response.status(), StatusCode::FOUND);
    assert_eq!(location(&response), "/admin/Welcome");
    let session = session_after(&response, &Session::default());
    let (id, hash, admin, deliverer): (Uuid, String, bool, bool) = sqlx::query_as(
        "SELECT id, password_hash, is_admin, is_deliverer FROM users WHERE email = 'orders@demo.invalid'",
    )
    .fetch_one(&db)
    .await?;
    assert_eq!(session.user_id(), Some(id));
    assert!(hash.starts_with("sha256|17|"));
    assert!(!admin && deliverer);

    // Its roles back, and unlocked, whatever was done to it
    sqlx::query(
        "UPDATE users SET is_deliverer = false, is_admin = true, locked_at = NOW(),
                          failed_login_attempts = 12
         WHERE id = $1",
    )
    .bind(id)
    .execute(&db)
    .await?;
    let response = send(
        &app,
        Method::POST,
        "/admin/DemoLogin?role=orders",
        &Session::default(),
        &[],
    )
    .await?;
    assert_eq!(
        session_after(&response, &Session::default()).user_id(),
        Some(id)
    );
    let row: (bool, bool, bool, i32) = sqlx::query_as(
        "SELECT is_admin, is_deliverer, locked_at IS NULL, failed_login_attempts FROM users WHERE id = $1",
    )
    .bind(id)
    .fetch_one(&db)
    .await?;
    assert_eq!(row, (false, true, true, 0));
    Ok(())
}

#[sqlx::test(migrations = false)]
async fn only_a_demo_has_demo_logins(db: PgPool) -> TestResult {
    admin(&db).await?;
    for (demo, uri, status) in [
        (false, "/admin/DemoLogin?role=admin", StatusCode::NOT_FOUND),
        (true, "/admin/DemoLogin?role=root", StatusCode::NOT_FOUND),
        (true, "/admin/DemoLogin", StatusCode::BAD_REQUEST),
    ] {
        let response = send(
            &site(db.clone(), demo),
            Method::POST,
            uri,
            &Session::default(),
            &[],
        )
        .await?;
        assert_eq!(response.status(), status, "{uri}");
        assert!(response.headers().get(header::SET_COOKIE).is_none());
    }
    let users: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM users")
        .fetch_one(&db)
        .await?;
    assert_eq!(users, 1);
    Ok(())
}
