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
        emails_enabled: true,
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

/// A login with these roles, as the session has it after logging in
async fn user_with(
    db: &PgPool,
    email: &str,
    roles: (bool, bool, bool),
) -> Result<Session, Box<dyn std::error::Error>> {
    let id: Uuid = sqlx::query_scalar(
        "INSERT INTO users (email, password_hash, is_admin, is_deliverer, is_promoter)
         VALUES ($1, 'x', $2, $3, $4) RETURNING id",
    )
    .bind(email)
    .bind(roles.0)
    .bind(roles.1)
    .bind(roles.2)
    .fetch_one(db)
    .await?;
    let mut session = Session::default();
    session.login(id);
    Ok(session)
}

/// The menu's links on the welcome page
fn links(page: &str) -> Vec<&str> {
    page.split("<li><a href=\"")
        .skip(1)
        .filter_map(|rest| rest.split('"').next())
        .collect()
}

#[sqlx::test(migrations = false)]
async fn the_welcome_page_shows_what_the_roles_allow(db: PgPool) -> TestResult {
    admin(&db).await?;
    let app = site(db.clone(), false);
    let all = [
        "/admin/OrderedProducts",
        "/admin/Customers",
        "/admin/EmailsForDeliveryInfo",
        "/admin/EmailsForNewsLetter",
        "/admin/Orders",
        "/admin/PaymentInstructions",
        "/admin/Producers",
        "/admin/Products",
        "/admin/WelcomeMessages",
    ];
    for (email, roles, expected) in [
        ("boss@example.com", (true, false, false), &all[..]),
        (
            "driver@example.com",
            (false, true, false),
            &["/admin/Orders"][..],
        ),
        (
            "promo@example.com",
            (false, false, true),
            &[
                "/admin/OrderedProducts",
                "/admin/EmailsForDeliveryInfo",
                "/admin/EmailsForNewsLetter",
                "/admin/Orders",
                "/admin/Producers",
                "/admin/Products",
            ][..],
        ),
        ("nobody@example.com", (false, false, false), &[][..]),
    ] {
        let session = user_with(&db, email, roles).await?;
        for uri in ["/admin/", "/admin/Welcome"] {
            let response = send(&app, Method::GET, uri, &session, &[]).await?;
            assert_eq!(response.status(), StatusCode::OK);
            let page = text(response).await?;
            assert_eq!(links(&page), expected, "{email} {uri}");
            assert!(page.contains(
                r#"<a class="js-delete js-delete-no-confirm back-button float-right p-2" href="/admin/DeleteSession">Logout</a>"#
            ));
            assert!(page.contains(r#"href="/admin/NewPassword">Change password</a>"#));
            assert_eq!(
                page.contains("<li>Your login has no role yet: ask an admin for one.</li>"),
                expected.is_empty(),
                "{email}"
            );
        }
    }
    Ok(())
}

/// A demo's logins have no password to change
#[sqlx::test(migrations = false)]
async fn a_demo_login_has_no_password_to_change(db: PgPool) -> TestResult {
    admin(&db).await?;
    let app = site(db.clone(), true);
    let response = send(
        &app,
        Method::POST,
        "/admin/DemoLogin?role=admin",
        &Session::default(),
        &[],
    )
    .await?;
    let session = session_after(&response, &Session::default());
    let page = text(send(&app, Method::GET, "/admin/Welcome", &session, &[]).await?).await?;
    assert!(page.contains(">Logout</a>"));
    assert!(!page.contains("Change password"), "{page}");
    assert!(page.contains(r#"<div class="demo-ribbon""#));
    Ok(())
}

/// As IHP's `ensureIsUser`: to the login page, with a message, and back
/// here after logging in
#[sqlx::test(migrations = false)]
async fn the_welcome_page_needs_a_login(db: PgPool) -> TestResult {
    admin(&db).await?;
    let app = site(db.clone(), false);
    let response = send(
        &app,
        Method::GET,
        "/admin/Welcome?x=1",
        &Session::default(),
        &[],
    )
    .await?;
    assert_eq!(response.status(), StatusCode::FOUND);
    assert_eq!(location(&response), "/admin/NewSession");
    let session = session_after(&response, &Session::default());
    assert_eq!(
        session.get_text(FLASH_SUCCESS).as_deref(),
        Some("Please log in to access this page")
    );
    let response = login(&app, &session, "admin@example.com", "salasana").await?;
    assert_eq!(location(&response), "/admin/Welcome?x=1");

    // A login that was deleted since is no login
    let mut gone = Session::default();
    gone.login(Uuid::from_u128(7));
    let response = send(&app, Method::GET, "/admin/", &gone, &[]).await?;
    assert_eq!(response.status(), StatusCode::FOUND);
    assert_eq!(location(&response), "/admin/NewSession");
    let after = session_after(&response, &gone);
    assert_eq!(
        after.get_text(REDIRECT_AFTER_LOGIN).as_deref(),
        Some("/admin/")
    );
    Ok(())
}

/// An order of the customer at that time, with a line of the given price,
/// handled as given
async fn listed_order(
    db: &PgPool,
    first_name: &str,
    ordered_at: &str,
    price: i32,
    handled: &str,
) -> sqlx::Result<Uuid> {
    let customer: Uuid = sqlx::query_scalar(
        "INSERT INTO customers (first_name, last_name, email, phone, street_address,
                                postal_code, city, reverse_name)
         VALUES ($1, 'Aalto', 'x@example.com', '040', 'Katu 1', '00100', 'Helsinki',
                 'aalto ' || lower($1))
         RETURNING id",
    )
    .bind(first_name)
    .fetch_one(db)
    .await?;
    let order: Uuid = sqlx::query_scalar(
        "INSERT INTO orders (customer_id, ordered_at) VALUES ($1, $2::timestamptz) RETURNING id",
    )
    .bind(customer)
    .bind(ordered_at)
    .fetch_one(db)
    .await?;
    let handle = match handled {
        "paid_at" => "UPDATE orders SET paid_at = NOW() WHERE id = $1",
        "invoiced_at" => "UPDATE orders SET invoiced_at = NOW() WHERE id = $1",
        "cancelled_at" => "UPDATE orders SET cancelled_at = NOW() WHERE id = $1",
        _ => "SELECT $1::uuid",
    };
    sqlx::query(handle).bind(order).execute(db).await?;
    let producer: Uuid = sqlx::query_scalar(
        "INSERT INTO producers (name, subject, description) VALUES ('P', '', '') RETURNING id",
    )
    .fetch_one(db)
    .await?;
    let product: Uuid = sqlx::query_scalar(
        "INSERT INTO products (producer_id, name, description, package, price)
         VALUES ($1, 'Oil', '', '1 l', $2) RETURNING id",
    )
    .bind(producer)
    .bind(price)
    .fetch_one(db)
    .await?;
    sqlx::query(
        "INSERT INTO ordered_products (order_id, product_id, quantity, unit_price)
         VALUES ($1, $2, 2, $3)",
    )
    .bind(order)
    .bind(product)
    .bind(price)
    .execute(db)
    .await?;
    Ok(order)
}

/// The list's customers, in its order
fn customers(page: &str) -> Vec<String> {
    page.split("</a></td><td>")
        .skip(1)
        .filter_map(|rest| rest.split("</td>").next())
        .map(str::to_string)
        .collect()
}

#[sqlx::test(migrations = false)]
async fn lists_a_years_orders(db: PgPool) -> TestResult {
    admin(&db).await?;
    let session = user_with(&db, "boss@example.com", (true, false, false)).await?;
    listed_order(&db, "Old", "2025-06-01 12:00:00+00", 1000, "").await?;
    let cecilia = listed_order(&db, "Cecilia", "2026-01-15 12:00:00+00", 300, "").await?;
    listed_order(&db, "Bertta", "2026-02-01 12:00:00+00", 500, "paid_at").await?;
    listed_order(&db, "Aino", "2026-03-01 12:00:00+00", 100, "invoiced_at").await?;
    listed_order(&db, "Gone", "2026-04-01 12:00:00+00", 100, "cancelled_at").await?;
    let app = site(db.clone(), false);
    let page = |uri: &'static str| {
        let app = app.clone();
        let session = session.clone();
        async move { text(send(&app, Method::GET, uri, &session, &[]).await?).await }
    };

    // The last year with orders, by name; cancelled ones left out
    let list = page("/admin/Orders").await?;
    assert_eq!(
        customers(&list),
        ["Aino Aalto", "Bertta Aalto", "Cecilia Aalto"]
    );
    assert!(list.contains("<p>3 orders</p>"));
    assert!(list.contains("<option>2025</option><option selected=\"selected\">2026</option>"));
    // Prices, and the button for the unpaid ones
    assert!(list.contains("<td>10\u{a0}€</td>"), "{list}");
    assert!(list.contains(&format!(
        r#"<form method="POST" action="/admin/UpdateMarkPaidOrder?orderId={cecilia}">"#
    )));
    assert_eq!(list.matches("Mark as paid").count(), 2);
    assert!(list.contains(r#"href="/admin/NewOrder">New</a>"#));

    assert_eq!(
        customers(&page("/admin/Orders?year=2025").await?),
        ["Old Aalto"]
    );
    assert_eq!(
        customers(&page("/admin/Orders?ordering=price&orderDir=descending").await?),
        ["Bertta Aalto", "Cecilia Aalto", "Aino Aalto"]
    );
    assert_eq!(
        customers(&page("/admin/Orders?excludePaid=on&excludeInvoiced=on").await?),
        ["Cecilia Aalto"]
    );
    assert_eq!(
        customers(&page("/admin/Orders?q=%20BERTTA").await?),
        ["Bertta Aalto"]
    );
    let none = page("/admin/Orders?year=1999").await?;
    assert!(none.contains("<p>0 orders</p>") && !none.contains("<table"));
    let response = send(&app, Method::GET, "/admin/Orders?year=abc", &session, &[]).await?;
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    Ok(())
}

/// A delivery person sees the orders but can't mark them paid; a login
/// without a role may not see them; someone not logged in logs in first
#[sqlx::test(migrations = false)]
async fn the_orders_are_for_those_who_may_see_them(db: PgPool) -> TestResult {
    admin(&db).await?;
    listed_order(&db, "Cecilia", "2026-01-15 12:00:00+00", 300, "").await?;
    let app = site(db.clone(), false);

    let driver = user_with(&db, "driver@example.com", (false, true, false)).await?;
    let list = text(send(&app, Method::GET, "/admin/Orders", &driver, &[]).await?).await?;
    assert_eq!(customers(&list), ["Cecilia Aalto"]);
    assert!(!list.contains("Mark as paid"));
    assert!(list.contains(r#"href="/admin/NewOrder">New</a>"#));

    let promoter = user_with(&db, "promo@example.com", (false, false, true)).await?;
    let list = text(send(&app, Method::GET, "/admin/Orders", &promoter, &[]).await?).await?;
    assert!(!list.contains("NewOrder") && !list.contains("Mark as paid"));

    let nobody = user_with(&db, "nobody@example.com", (false, false, false)).await?;
    let response = send(&app, Method::GET, "/admin/Orders", &nobody, &[]).await?;
    assert_eq!(response.status(), StatusCode::FORBIDDEN);
    assert!(text(response).await?.contains("<h1>Access denied</h1>"));

    let response = send(
        &app,
        Method::GET,
        "/admin/Orders?q=x",
        &Session::default(),
        &[],
    )
    .await?;
    assert_eq!(response.status(), StatusCode::FOUND);
    let session = session_after(&response, &Session::default());
    assert_eq!(
        session.get_text(REDIRECT_AFTER_LOGIN).as_deref(),
        Some("/admin/Orders?q=x")
    );
    Ok(())
}

/// The forms and links of an order page's next steps
fn steps(page: &str) -> Vec<&str> {
    [
        "Send invoice",
        "Mark as invoiced",
        "Mark as paid",
        "Mark as delivered",
        "Cancel order",
    ]
    .into_iter()
    .filter(|step| {
        page.contains(&format!("value=\"{step}\"")) || page.contains(&format!(">{step}</a>"))
    })
    .collect()
}

#[sqlx::test(migrations = false)]
async fn an_orders_page_has_the_steps_the_roles_allow(db: PgPool) -> TestResult {
    admin(&db).await?;
    let order = listed_order(&db, "Cecilia", "2026-01-15 12:00:00+00", 300, "").await?;
    let app = site(db.clone(), false);
    let uri = format!("/admin/ShowOrder?orderId={order}");
    let boss = user_with(&db, "boss@example.com", (true, false, false)).await?;
    let driver = user_with(&db, "driver@example.com", (false, true, false)).await?;
    let page = |session: Session| {
        let (app, uri) = (app.clone(), uri.clone());
        async move { text(send(&app, Method::GET, &uri, &session, &[]).await?).await }
    };

    let shown = page(boss.clone()).await?;
    assert!(
        shown.contains("<p>Cecilia Aalto</p><p>x@example.com</p>"),
        "{shown}"
    );
    assert!(shown.contains(r#"<td class="normal">Oil (1 l)</td><td>2</td>"#));
    assert!(shown.contains(r#"<a class="hover:text-gray-700" href="/admin/Orders">Orders</a>"#));
    assert!(shown.contains(r#"<p id="email-history">The invoice hasn't been emailed.</p>"#));
    assert_eq!(
        steps(&shown),
        [
            "Send invoice",
            "Mark as invoiced",
            "Mark as paid",
            "Mark as delivered",
            "Cancel order"
        ]
    );
    assert_eq!(steps(&page(driver.clone()).await?), ["Mark as delivered"]);

    // Paid: no more paying or cancelling; the emails as they went
    sqlx::query("UPDATE orders SET paid_at = NOW()")
        .execute(&db)
        .await?;
    sqlx::query(
        "INSERT INTO email_order_jobs (order_id, status, last_error)
         VALUES ($1, 'job_status_succeeded', NULL), ($1, 'job_status_retry', 'SMTP <down>')",
    )
    .bind(order)
    .execute(&db)
    .await?;
    let shown = page(boss.clone()).await?;
    assert_eq!(
        steps(&shown),
        ["Send invoice", "Mark as invoiced", "Mark as delivered"]
    );
    assert!(shown.contains("<h2>Invoice emails</h2><ul><li>Emailed <time"));
    assert!(shown.contains("</time>, trying again: SMTP &lt;down&gt;</li>"));
    assert!(!shown.contains("Emails are off"));

    sqlx::query("UPDATE orders SET cancelled_at = NOW()")
        .execute(&db)
        .await?;
    let shown = page(boss).await?;
    assert_eq!(steps(&shown), Vec::<&str>::new());
    assert!(shown.contains("<p>Cancelled <time"));
    Ok(())
}

/// Each button: the row, the message, and where it goes
#[sqlx::test(migrations = false)]
async fn the_buttons_mark_the_order(db: PgPool) -> TestResult {
    admin(&db).await?;
    let order = listed_order(&db, "Cecilia", "2026-01-15 12:00:00+00", 300, "").await?;
    let app = site(db.clone(), false);
    let boss = user_with(&db, "boss@example.com", (true, false, false)).await?;
    let show = format!("/admin/ShowOrder?orderId={order}");
    let done = |column: &'static str| {
        let db = db.clone();
        async move {
            let sql = match column {
                "invoiced" => "SELECT invoiced_at IS NOT NULL FROM orders",
                "paid" => "SELECT paid_at IS NOT NULL FROM orders",
                "delivered" => "SELECT delivered_at IS NOT NULL FROM orders",
                _ => "SELECT cancelled_at IS NOT NULL FROM orders",
            };
            sqlx::query_scalar::<_, bool>(sql).fetch_one(&db).await
        }
    };
    let press = |method: Method, action: &str, form: &'static [(&'static str, &'static str)]| {
        let (app, boss) = (app.clone(), boss.clone());
        let uri = format!("/admin/{action}?orderId={order}");
        async move { send(&app, method, &uri, &boss, form).await }
    };

    let response = press(Method::POST, "UpdateInvoiceOrder", &[]).await?;
    assert_eq!(
        (response.status(), location(&response)),
        (StatusCode::FOUND, show.as_str())
    );
    assert_eq!(
        session_after(&response, &boss)
            .get_text(FLASH_SUCCESS)
            .as_deref(),
        Some("Order invoiced")
    );
    assert!(done("invoiced").await?);

    let response = press(Method::POST, "UpdateMarkPaidOrder", &[]).await?;
    assert_eq!(location(&response), "/admin/Orders");
    assert!(done("paid").await?);

    let response = press(Method::POST, "UpdateDeliverOrder", &[]).await?;
    assert_eq!(location(&response), show);
    assert!(done("delivered").await?);

    let response = press(Method::POST, "UpdateSendInvoiceOrder", &[]).await?;
    assert_eq!(location(&response), show);
    assert_eq!(
        session_after(&response, &boss)
            .get_text(FLASH_SUCCESS)
            .as_deref(),
        Some("Invoice queued for sending to x@example.com")
    );
    let jobs: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM email_order_jobs WHERE status = 'job_status_not_started'",
    )
    .fetch_one(&db)
    .await?;
    assert_eq!(jobs, 1);

    // Cancelling is a DELETE, from the page's js-delete link
    let response = press(Method::POST, "DeleteCancelOrder", &[]).await?;
    assert_eq!(response.status(), StatusCode::METHOD_NOT_ALLOWED);
    assert!(!done("cancelled").await?);
    let response = press(Method::POST, "DeleteCancelOrder", &[("_method", "DELETE")]).await?;
    assert_eq!(location(&response), "/admin/Orders");
    assert_eq!(
        session_after(&response, &boss)
            .get_text(FLASH_SUCCESS)
            .as_deref(),
        Some("Order cancelled")
    );
    assert!(done("cancelled").await?);

    // A cancelled order's invoice isn't sent
    let response = press(Method::POST, "UpdateSendInvoiceOrder", &[]).await?;
    assert_eq!(
        session_after(&response, &boss)
            .get_text(FLASH_ERROR)
            .as_deref(),
        Some("A cancelled order's invoice can't be sent")
    );
    let jobs: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM email_order_jobs")
        .fetch_one(&db)
        .await?;
    assert_eq!(jobs, 1);
    Ok(())
}

/// Marking paid from the list goes back to the list as it was
#[sqlx::test(migrations = false)]
async fn marking_paid_goes_back_to_the_page_it_was_on(db: PgPool) -> TestResult {
    admin(&db).await?;
    let order = listed_order(&db, "Cecilia", "2026-01-15 12:00:00+00", 300, "").await?;
    let boss = user_with(&db, "boss@example.com", (true, false, false)).await?;
    let request = Request::post(format!("/admin/UpdateMarkPaidOrder?orderId={order}"))
        .header(
            header::COOKIE,
            format!("{}={}", session::COOKIE, boss.encrypt(&key())),
        )
        .header(
            header::REFERER,
            "https://tilaus.example.fi/admin/Orders?year=2026&q=cec",
        )
        .body(Body::empty())?;
    let response = site(db, false).oneshot(request).await?;
    assert_eq!(location(&response), "/admin/Orders?year=2026&q=cec");
    Ok(())
}

#[sqlx::test(migrations = false)]
async fn the_order_pages_check_who_and_what(db: PgPool) -> TestResult {
    admin(&db).await?;
    let order = listed_order(&db, "Cecilia", "2026-01-15 12:00:00+00", 300, "").await?;
    let app = site(db.clone(), false);
    let driver = user_with(&db, "driver@example.com", (false, true, false)).await?;
    let boss = user_with(&db, "boss@example.com", (true, false, false)).await?;
    let unknown = Uuid::from_u128(9);
    for (session, method, uri, status) in [
        (
            &boss,
            Method::GET,
            "/admin/ShowOrder".to_string(),
            StatusCode::BAD_REQUEST,
        ),
        (
            &boss,
            Method::GET,
            "/admin/ShowOrder?orderId=xyz".to_string(),
            StatusCode::BAD_REQUEST,
        ),
        (
            &boss,
            Method::GET,
            format!("/admin/ShowOrder?orderId={unknown}"),
            StatusCode::NOT_FOUND,
        ),
        (
            &boss,
            Method::POST,
            format!("/admin/UpdateMarkPaidOrder?orderId={unknown}"),
            StatusCode::NOT_FOUND,
        ),
        (
            &boss,
            Method::GET,
            format!("/admin/UpdateMarkPaidOrder?orderId={order}"),
            StatusCode::METHOD_NOT_ALLOWED,
        ),
        (
            &driver,
            Method::POST,
            format!("/admin/UpdateMarkPaidOrder?orderId={order}"),
            StatusCode::FORBIDDEN,
        ),
        (
            &driver,
            Method::POST,
            format!("/admin/UpdateInvoiceOrder?orderId={order}"),
            StatusCode::FORBIDDEN,
        ),
        (
            &driver,
            Method::POST,
            format!("/admin/UpdateSendInvoiceOrder?orderId={order}"),
            StatusCode::FORBIDDEN,
        ),
        (
            &driver,
            Method::DELETE,
            format!("/admin/DeleteCancelOrder?orderId={order}"),
            StatusCode::FORBIDDEN,
        ),
        (
            &driver,
            Method::POST,
            format!("/admin/UpdateDeliverOrder?orderId={order}"),
            StatusCode::FOUND,
        ),
    ] {
        let response = send(&app, method, &uri, session, &[]).await?;
        assert_eq!(response.status(), status, "{uri}");
    }
    let row: (bool, bool, bool, bool, i64) = sqlx::query_as(
        "SELECT invoiced_at IS NULL, paid_at IS NULL, cancelled_at IS NULL, delivered_at IS NOT NULL,
                (SELECT COUNT(*) FROM email_order_jobs) FROM orders",
    )
    .fetch_one(&db)
    .await?;
    assert_eq!(
        row,
        (true, true, true, true, 0),
        "only the delivery was marked"
    );
    Ok(())
}

/// The customer's fields of the order form, filled in
const CUSTOMER: [(&str, &str); 8] = [
    ("firstName", " Matti "),
    ("lastName", "Meikäläinen"),
    ("billingName", ""),
    ("email", "matti%40example.com"),
    ("phone", "040 123 4567"),
    ("streetAddress", "Katu 1"),
    ("postalCode", "00100"),
    ("city", "Helsinki"),
];

/// A disabled product of a disabled producer, which the admin can still
/// take an order of
async fn disabled_product(db: &PgPool) -> sqlx::Result<Uuid> {
    sqlx::query_scalar(
        "WITH p AS (INSERT INTO producers (name, subject, description, enabled)
                    VALUES ('Zeta Oy', '', '', false) RETURNING id)
         INSERT INTO products (producer_id, name, description, package, price, enabled)
         SELECT id, 'Zetaöljy', '', '1 l', 1500, false FROM p RETURNING id",
    )
    .fetch_one(db)
    .await
}

#[sqlx::test(migrations = false)]
async fn the_admin_takes_an_order_of_anything_without_an_email(db: PgPool) -> TestResult {
    admin(&db).await?;
    let zeta = disabled_product(&db).await?;
    let app = site(db.clone(), false);
    let driver = user_with(&db, "driver@example.com", (false, true, false)).await?;

    let form = text(send(&app, Method::GET, "/admin/NewOrder", &driver, &[]).await?).await?;
    assert!(form.contains(r#"<form method="POST" action="/admin/CreateOrder">"#));
    assert!(form.contains("<h2>Zeta Oy</h2>") && form.contains(&format!(r#"name="{zeta}""#)));
    assert!(
        form.contains("<title>Manage Bosco Falconeria</title>"),
        "the admin's layout"
    );

    let quantity = zeta.to_string();
    let mut fields: Vec<(&str, &str)> = CUSTOMER.to_vec();
    fields.push((&quantity, "2"));
    let response = send(&app, Method::POST, "/admin/CreateOrder", &driver, &fields).await?;
    assert_eq!(response.status(), StatusCode::FOUND);
    let (order, first_name, lines, jobs): (Uuid, String, i64, i64) = sqlx::query_as(
        "SELECT orders.id, first_name,
                (SELECT SUM(quantity * unit_price) FROM ordered_products WHERE order_id = orders.id),
                (SELECT COUNT(*) FROM email_order_jobs)
         FROM orders JOIN customers ON customers.id = orders.customer_id",
    )
    .fetch_one(&db)
    .await?;
    assert_eq!(
        location(&response),
        format!("/admin/ShowOrder?orderId={order}")
    );
    assert_eq!(
        session_after(&response, &driver)
            .get_text(FLASH_SUCCESS)
            .as_deref(),
        Some("Order created")
    );
    assert_eq!((first_name.as_str(), lines, jobs), ("Matti", 3000, 0));
    Ok(())
}

#[sqlx::test(migrations = false)]
async fn the_admins_order_form_says_what_is_missing(db: PgPool) -> TestResult {
    admin(&db).await?;
    let zeta = disabled_product(&db).await?;
    let app = site(db.clone(), false);
    let boss = user_with(&db, "boss@example.com", (true, false, false)).await?;
    let quantity = zeta.to_string();

    // No products: the form again, filled in, saying so
    let mut fields: Vec<(&str, &str)> = CUSTOMER.to_vec();
    fields.push((&quantity, "0"));
    let response = send(&app, Method::POST, "/admin/CreateOrder", &boss, &fields).await?;
    assert_eq!(response.status(), StatusCode::OK);
    let page = text(response).await?;
    assert!(page.contains(r#"<div class="unavailable-notice" role="alert">"#));
    assert!(page.contains(r#"value="Meikäläinen""#));

    // A missing name: the form again, with the quantity kept
    let mut fields: Vec<(&str, &str)> = CUSTOMER
        .iter()
        .filter(|(k, _)| *k != "firstName")
        .copied()
        .collect();
    fields.push((&quantity, "2"));
    let page = text(send(&app, Method::POST, "/admin/CreateOrder", &boss, &fields).await?).await?;
    assert!(page.contains("is-invalid"));
    assert!(page.contains(&format!(r#"name="{zeta}" value="2""#)));

    let mut fields: Vec<(&str, &str)> = CUSTOMER.to_vec();
    fields.push((&quantity, "abc"));
    let response = send(&app, Method::POST, "/admin/CreateOrder", &boss, &fields).await?;
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);

    let promoter = user_with(&db, "promo@example.com", (false, false, true)).await?;
    for (method, uri) in [
        (Method::GET, "/admin/NewOrder"),
        (Method::POST, "/admin/CreateOrder"),
    ] {
        let response = send(&app, method, uri, &promoter, &CUSTOMER).await?;
        assert_eq!(response.status(), StatusCode::FORBIDDEN);
    }
    let orders: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM orders")
        .fetch_one(&db)
        .await?;
    assert_eq!(orders, 0);
    Ok(())
}

#[sqlx::test(migrations = false)]
async fn all_ordered_products_per_year(db: PgPool) -> TestResult {
    admin(&db).await?;
    listed_order(&db, "Old", "2024-06-01 12:00:00+00", 1000, "").await?;
    listed_order(&db, "New", "2026-02-01 12:00:00+00", 500, "").await?;
    listed_order(&db, "Gone", "2026-03-01 12:00:00+00", 700, "cancelled_at").await?;
    // Of the same product, ordered in two years
    sqlx::query(
        "INSERT INTO ordered_products (order_id, product_id, quantity, unit_price)
         SELECT o.id, p.id, 5, 100 FROM orders o, products p
         WHERE o.ordered_at > '2026-01-01' AND o.cancelled_at IS NULL AND p.price = 1000",
    )
    .execute(&db)
    .await?;
    let app = site(db.clone(), false);
    let promoter = user_with(&db, "promo@example.com", (false, false, true)).await?;
    let page =
        text(send(&app, Method::GET, "/admin/OrderedProducts", &promoter, &[]).await?).await?;
    // Newest year first, a year without orders too; the cancelled order's
    // product isn't there
    assert!(
        page.contains("<tr><th></th><th>2026</th><th>2025</th><th>2024</th></tr>"),
        "{page}"
    );
    assert!(page.contains("<tr><td>Oil (1 l)</td><td>5</td><td>0</td><td>2</td></tr>"));
    assert!(page.contains("<tr><td>Oil (1 l)</td><td>2</td><td>0</td><td>0</td></tr>"));
    assert_eq!(page.matches("<td>Oil (1 l)</td>").count(), 2);
    assert_eq!(
        page.matches(r#"<th colspan="4">P</th>"#).count(),
        2,
        "one per producer"
    );

    let driver = user_with(&db, "driver@example.com", (false, true, false)).await?;
    let response = send(&app, Method::GET, "/admin/OrderedProducts", &driver, &[]).await?;
    assert_eq!(response.status(), StatusCode::FORBIDDEN);
    Ok(())
}

#[sqlx::test(migrations = false)]
async fn welcome_messages_are_written_changed_and_deleted(db: PgPool) -> TestResult {
    admin(&db).await?;
    let app = site(db.clone(), false);
    let boss = user_with(&db, "boss@example.com", (true, false, false)).await?;

    // A new one opens ordering unless unticked; the checkbox comes before
    // its hidden "off"
    let form = text(send(&app, Method::GET, "/admin/NewWelcomeMessage", &boss, &[]).await?).await?;
    assert!(form.contains(r#"id="welcomeMessage_isOrderingEnabled" checked="checked"><input type="hidden" name="isOrderingEnabled" value="off">"#));
    assert!(form.contains(">Create Welcomemessage</button>"));
    let response = send(
        &app,
        Method::POST,
        "/admin/CreateWelcomeMessage",
        &boss,
        &[
            ("text", "Tervetuloa"),
            ("isOrderingEnabled", "on"),
            ("isOrderingEnabled", "off"),
        ],
    )
    .await?;
    let (id, open): (Uuid, bool) =
        sqlx::query_as("SELECT id, is_ordering_enabled FROM welcome_messages")
            .fetch_one(&db)
            .await?;
    assert!(open);
    assert_eq!(
        location(&response),
        format!("/admin/ShowWelcomeMessage?welcomeMessageId={id}")
    );
    assert_eq!(
        session_after(&response, &boss)
            .get_text(FLASH_SUCCESS)
            .as_deref(),
        Some("WelcomeMessage created")
    );

    // Unticked, it sends only "off"; the text stays when not sent
    let update = format!("/admin/UpdateWelcomeMessage?welcomeMessageId={id}");
    send(
        &app,
        Method::POST,
        &update,
        &boss,
        &[("isOrderingEnabled", "off")],
    )
    .await?;
    let row: (String, bool) =
        sqlx::query_as("SELECT text, is_ordering_enabled FROM welcome_messages")
            .fetch_one(&db)
            .await?;
    assert_eq!(row, ("Tervetuloa".to_string(), false));

    let shown = text(
        send(
            &app,
            Method::GET,
            &format!("/admin/ShowWelcomeMessage?welcomeMessageId={id}"),
            &boss,
            &[],
        )
        .await?,
    )
    .await?;
    assert!(shown.contains("<p>Tervetuloa</p>"));
    let edit = text(
        send(
            &app,
            Method::GET,
            &format!("/admin/EditWelcomeMessage?welcomeMessageId={id}"),
            &boss,
            &[],
        )
        .await?,
    )
    .await?;
    assert!(edit.contains(r#"class="js-delete back-button">Delete</a>"#));
    assert!(edit.contains(">Save Welcomemessage</button>"));

    let delete = format!("/admin/DeleteWelcomeMessage?welcomeMessageId={id}");
    let response = send(&app, Method::POST, &delete, &boss, &[("_method", "DELETE")]).await?;
    assert_eq!(location(&response), "/admin/WelcomeMessages");
    let left: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM welcome_messages")
        .fetch_one(&db)
        .await?;
    assert_eq!(left, 0);
    Ok(())
}

/// More than a page: IHP's pagination under the list
#[sqlx::test(migrations = false)]
async fn long_lists_are_paged(db: PgPool) -> TestResult {
    admin(&db).await?;
    sqlx::query(
        "INSERT INTO welcome_messages (text, published_at)
         SELECT 'Viesti ' || n, '2025-01-01'::timestamptz + n * interval '1 day'
         FROM generate_series(1, 55) n",
    )
    .execute(&db)
    .await?;
    let app = site(db.clone(), false);
    let boss = user_with(&db, "boss@example.com", (true, false, false)).await?;
    let first = text(send(&app, Method::GET, "/admin/WelcomeMessages", &boss, &[]).await?).await?;
    assert_eq!(first.matches("ShowWelcomeMessage").count(), 50);
    assert!(first.contains(r#"<a href="/admin/WelcomeMessages?page=2" class="relative inline-flex items-center px-4 py-2 border text-sm font-medium bg-white border-gray-300 text-gray-500 hover:bg-gray-50">2</a>"#));
    // Newest first: the oldest on the second page
    let second = text(
        send(
            &app,
            Method::GET,
            "/admin/WelcomeMessages?page=2",
            &boss,
            &[],
        )
        .await?,
    )
    .await?;
    assert_eq!(second.matches("ShowWelcomeMessage").count(), 5);
    assert!(second.contains(r#"datetime="2025-01-02T00:00:00Z""#));
    let response = send(
        &app,
        Method::GET,
        "/admin/WelcomeMessages?page=x",
        &boss,
        &[],
    )
    .await?;
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    Ok(())
}

/// On a demo only ordering opens and closes: the welcome text and the
/// payment details stay
#[sqlx::test(migrations = false)]
async fn a_demo_keeps_its_texts(db: PgPool) -> TestResult {
    admin(&db).await?;
    let welcome: Uuid = sqlx::query_scalar(
        "INSERT INTO welcome_messages (text, is_ordering_enabled) VALUES ('Demo', true) RETURNING id",
    )
    .fetch_one(&db)
    .await?;
    let payment: Uuid =
        sqlx::query_scalar("INSERT INTO payment_instructions (text) VALUES ('Fake') RETURNING id")
            .fetch_one(&db)
            .await?;
    let app = site(db.clone(), true);
    let boss = user_with(&db, "boss@example.com", (true, false, false)).await?;

    let update = format!("/admin/UpdateWelcomeMessage?welcomeMessageId={welcome}");
    send(
        &app,
        Method::POST,
        &update,
        &boss,
        &[("text", "Oma tili"), ("isOrderingEnabled", "off")],
    )
    .await?;
    let row: (String, bool) =
        sqlx::query_as("SELECT text, is_ordering_enabled FROM welcome_messages")
            .fetch_one(&db)
            .await?;
    assert_eq!(row, ("Demo".to_string(), false));
    let edit = text(
        send(
            &app,
            Method::GET,
            &format!("/admin/EditWelcomeMessage?welcomeMessageId={welcome}"),
            &boss,
            &[],
        )
        .await?,
    )
    .await?;
    assert!(edit.contains(r#"disabled="disabled">Demo</textarea>"#));
    assert!(!edit.contains("js-delete"));

    for (method, uri) in [
        (Method::GET, "/admin/NewWelcomeMessage".to_string()),
        (Method::POST, "/admin/CreateWelcomeMessage".to_string()),
        (
            Method::DELETE,
            format!("/admin/DeleteWelcomeMessage?welcomeMessageId={welcome}"),
        ),
    ] {
        let response = send(&app, method, &uri, &boss, &[("text", "x")]).await?;
        assert_eq!(location(&response), "/admin/WelcomeMessages", "{uri}");
        assert!(
            session_after(&response, &boss)
                .get_text(FLASH_ERROR)
                .is_some()
        );
    }
    for (method, uri) in [
        (
            Method::GET,
            format!("/admin/EditPaymentInstruction?paymentInstructionId={payment}"),
        ),
        (
            Method::POST,
            format!("/admin/UpdatePaymentInstruction?paymentInstructionId={payment}"),
        ),
        (Method::POST, "/admin/CreatePaymentInstruction".to_string()),
    ] {
        let response = send(&app, method, &uri, &boss, &[("text", "Oma tili")]).await?;
        assert_eq!(location(&response), "/admin/PaymentInstructions", "{uri}");
    }
    let texts: Vec<String> = sqlx::query_scalar(
        "SELECT text FROM welcome_messages UNION ALL SELECT text FROM payment_instructions",
    )
    .fetch_all(&db)
    .await?;
    assert_eq!(texts, ["Demo", "Fake"]);
    Ok(())
}

#[sqlx::test(migrations = false)]
async fn the_texts_are_for_admins(db: PgPool) -> TestResult {
    admin(&db).await?;
    let app = site(db.clone(), false);
    let promoter = user_with(&db, "promo@example.com", (false, false, true)).await?;
    for uri in ["/admin/WelcomeMessages", "/admin/NewPaymentInstruction"] {
        let response = send(&app, Method::GET, uri, &promoter, &[]).await?;
        assert_eq!(response.status(), StatusCode::FORBIDDEN, "{uri}");
    }
    let response = send(
        &app,
        Method::POST,
        "/admin/CreatePaymentInstruction",
        &promoter,
        &[("text", "x")],
    )
    .await?;
    assert_eq!(response.status(), StatusCode::FORBIDDEN);
    let response = send(
        &app,
        Method::GET,
        "/admin/ShowPaymentInstruction?paymentInstructionId=x",
        &promoter,
        &[],
    )
    .await?;
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    Ok(())
}
