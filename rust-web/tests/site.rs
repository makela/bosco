//! The public site against a real PostgreSQL: each test gets a database of
//! its own (`sqlx::test`) with IHP's base schema and the IHP app's
//! `Application/Schema.sql`, so the tables are the ones the IHP app uses.
//! Mostly the IHP app's own tests of `Web/` (Test/Web), ported. Run with
//! `./test.sh`, which starts a throwaway PostgreSQL.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;

use axum::Router;
use axum::body::Body;
use axum::http::{Request, Response, StatusCode, header};
use bosco_web::l10n::Locale;
use bosco_web::{AppState, Site, app};
use http_body_util::BodyExt;
use sqlx::PgPool;
use tower::ServiceExt;
use uuid::Uuid;

type TestResult = Result<(), Box<dyn std::error::Error>>;

/// What IHP itself puts in a database before the app's schema
const IHP_SCHEMA: &str = r#"
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE TYPE JOB_STATUS AS ENUM ('job_status_not_started', 'job_status_running', 'job_status_failed', 'job_status_timed_out', 'job_status_succeeded', 'job_status_retry');
"#;

async fn schema(db: &PgPool) -> TestResult {
    sqlx::raw_sql(IHP_SCHEMA).execute(db).await?;
    sqlx::raw_sql(include_str!("../../Application/Schema.sql"))
        .execute(db)
        .await?;
    Ok(())
}

fn site(db: PgPool, demo: bool) -> Router {
    app(Arc::new(AppState {
        db,
        site: Site {
            locale: Locale::Fi,
            demo,
            stylesheet: "/app.css".into(),
        },
        static_dir: PathBuf::from(concat!(env!("CARGO_MANIFEST_DIR"), "/../static")),
    }))
}

struct Catalog {
    oil: Uuid,
    honey: Uuid,
    chocolate: Uuid,
    quetzal: Uuid,
}

/// An open shop: Bosco Falconeria's oil and honey, and Quetzal's chocolate
async fn shop(db: &PgPool) -> Result<Catalog, Box<dyn std::error::Error>> {
    schema(db).await?;
    welcome(db, "Tervetuloa **tilaamaan**", true).await?;
    let bosco = producer(db, "Bosco Falconeria", "Sisilia").await?;
    let quetzal = producer(db, "Quetzal", "Modica").await?;
    Ok(Catalog {
        oil: product(db, bosco, "Oliiviöljyä", "3 l", 5100).await?,
        honey: product(db, bosco, "Hunajaa", "250 g", 1010).await?,
        chocolate: product(db, quetzal, "Chilisuklaa", "60 g", 410).await?,
        quetzal,
    })
}

async fn welcome(db: &PgPool, text: &str, open: bool) -> TestResult {
    sqlx::query("INSERT INTO welcome_messages (text, is_ordering_enabled) VALUES ($1, $2)")
        .bind(text)
        .bind(open)
        .execute(db)
        .await?;
    Ok(())
}

async fn producer(db: &PgPool, name: &str, description: &str) -> sqlx::Result<Uuid> {
    sqlx::query_scalar(
        "INSERT INTO producers (name, subject, description) VALUES ($1, '', $2) RETURNING id",
    )
    .bind(name)
    .bind(description)
    .fetch_one(db)
    .await
}

async fn product(
    db: &PgPool,
    producer: Uuid,
    name: &str,
    package: &str,
    price: i32,
) -> sqlx::Result<Uuid> {
    sqlx::query_scalar(
        "INSERT INTO products (producer_id, name, description, package, price)
         VALUES ($1, $2, '', $3, $4) RETURNING id",
    )
    .bind(producer)
    .bind(name)
    .bind(package)
    .bind(price)
    .fetch_one(db)
    .await
}

async fn count(db: &PgPool, sql: &'static str) -> sqlx::Result<i64> {
    sqlx::query_scalar(sql).fetch_one(db).await
}

async fn get(app: &Router, uri: &str) -> Result<Response<Body>, Box<dyn std::error::Error>> {
    Ok(app
        .clone()
        .oneshot(Request::get(uri).body(Body::empty())?)
        .await?)
}

async fn get_with_cookie(
    app: &Router,
    uri: &str,
    cookie: &str,
) -> Result<Response<Body>, Box<dyn std::error::Error>> {
    Ok(app
        .clone()
        .oneshot(
            Request::get(uri)
                .header(header::COOKIE, cookie)
                .body(Body::empty())?,
        )
        .await?)
}

async fn post(
    app: &Router,
    uri: &str,
    fields: &[(&str, &str)],
) -> Result<Response<Body>, Box<dyn std::error::Error>> {
    let body = fields
        .iter()
        .map(|(k, v)| format!("{}={}", encode(k), encode(v)))
        .collect::<Vec<_>>()
        .join("&");
    Ok(app
        .clone()
        .oneshot(
            Request::post(uri)
                .header(header::CONTENT_TYPE, "application/x-www-form-urlencoded")
                .body(Body::from(body))?,
        )
        .await?)
}

fn encode(text: &str) -> String {
    text.bytes()
        .map(|b| match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' => (b as char).to_string(),
            b' ' => "+".to_string(),
            _ => format!("%{b:02X}"),
        })
        .collect()
}

async fn body(response: Response<Body>) -> Result<String, Box<dyn std::error::Error>> {
    Ok(String::from_utf8(
        response.into_body().collect().await?.to_bytes().to_vec(),
    )?)
}

fn location(response: &Response<Body>) -> &str {
    response
        .headers()
        .get(header::LOCATION)
        .and_then(|v| v.to_str().ok())
        .unwrap_or("")
}

/// The flash cookie a redirect sets, as the browser sends it back
fn flash_cookie(response: &Response<Body>) -> String {
    response
        .headers()
        .get_all(header::SET_COOKIE)
        .iter()
        .filter_map(|v| v.to_str().ok())
        .find(|c| c.starts_with("flash="))
        .and_then(|c| c.split(';').next())
        .unwrap_or("")
        .to_string()
}

/// A complete order's fields, with `changes` instead of the defaults
fn order_fields<'a>(
    email: &'a str,
    changes: &[(&'a str, &'a str)],
    quantities: &'a [(String, String)],
) -> Vec<(&'a str, &'a str)> {
    let mut fields: HashMap<&str, &str> = [
        ("firstName", "Maija"),
        ("lastName", "Virtanen"),
        ("billingName", ""),
        ("phone", "040 123 4567"),
        ("streetAddress", "Testikatu 1"),
        ("postalCode", "00100"),
        ("city", "Helsinki"),
        ("contact_me_by_fax_only", ""),
    ]
    .into_iter()
    .collect();
    fields.insert("email", email);
    fields.extend(changes.iter().copied());
    let mut fields: Vec<_> = fields.into_iter().collect();
    fields.extend(quantities.iter().map(|(k, v)| (k.as_str(), v.as_str())));
    fields
}

fn quantities(lines: &[(Uuid, i64)]) -> Vec<(String, String)> {
    lines
        .iter()
        .map(|(id, q)| (id.to_string(), q.to_string()))
        .collect()
}

async fn order(
    app: &Router,
    email: &str,
    changes: &[(&str, &str)],
    lines: &[(Uuid, i64)],
) -> Result<Response<Body>, Box<dyn std::error::Error>> {
    let quantities = quantities(lines);
    post(
        app,
        "/CreateOrder",
        &order_fields(email, changes, &quantities),
    )
    .await
}

async fn customers_with(db: &PgPool, email: &str) -> sqlx::Result<i64> {
    sqlx::query_scalar("SELECT count(*) FROM customers WHERE email = $1")
        .bind(email)
        .fetch_one(db)
        .await
}

async fn ordered_quantities(db: &PgPool, email: &str) -> sqlx::Result<Vec<(Uuid, i32, i32)>> {
    sqlx::query_as(
        "SELECT product_id, quantity, unit_price FROM ordered_products
         JOIN orders ON orders.id = order_id JOIN customers ON customers.id = customer_id
         WHERE email = $1 ORDER BY quantity",
    )
    .bind(email)
    .fetch_all(db)
    .await
}

// The front page

#[sqlx::test(migrations = false)]
async fn front_page_shows_the_welcome_message_and_the_order_button(db: PgPool) -> TestResult {
    shop(&db).await?;
    let app = site(db.clone(), false);
    let page = body(get(&app, "/").await?).await?;
    assert!(page.contains("<strong>tilaamaan</strong>"), "{page}");
    assert!(page.contains(r#"href="/NewOrder""#));
    assert!(page.contains(r#"<html lang="fi">"#));
    assert!(page.contains("<title>Bosco Falconeria Öljytilaus</title>"));

    welcome(&db, "Tilaukset on suljettu", false).await?;
    let page = body(get(&app, "/Orders").await?).await?;
    assert!(page.contains("Tilaukset on suljettu"));
    assert!(!page.contains(r#"href="/NewOrder""#));
    Ok(())
}

#[sqlx::test(migrations = false)]
async fn a_demo_says_so_and_shows_a_fake_account(db: PgPool) -> TestResult {
    let catalog = shop(&db).await?;
    sqlx::query("INSERT INTO payment_instructions (text) VALUES ('FI12 3456 7890')")
        .execute(&db)
        .await?;
    let app = site(db.clone(), true);
    let page = body(get(&app, "/").await?).await?;
    assert!(page.contains("<title>[Demo] Bosco Falconeria Öljytilaus</title>"));
    assert!(page.contains("noindex, nofollow"));
    assert!(page.contains("demo-ribbon"));

    let response = order(&app, "demo@example.com", &[], &[(catalog.oil, 1)]).await?;
    let invoice = body(get(&app, location(&response)).await?).await?;
    assert!(invoice.contains("FI00 0000 0000 0000 00"));
    assert!(!invoice.contains("FI12 3456 7890"));
    assert!(invoice.contains("Esittelylasku – älä maksa."));
    Ok(())
}

// The order form

#[sqlx::test(migrations = false)]
async fn order_form_lists_bosco_first_then_the_others(db: PgPool) -> TestResult {
    let catalog = shop(&db).await?;
    let disabled = producer(&db, "Aaltonen", "").await?;
    sqlx::query("UPDATE producers SET enabled = false WHERE id = $1")
        .bind(disabled)
        .execute(&db)
        .await?;
    let app = site(db, false);
    let form = body(get(&app, "/NewOrder").await?).await?;
    let bosco = form.find("Bosco Falconeria").ok_or("no Bosco")?;
    let quetzal = form.find("<h2>Quetzal</h2>").ok_or("no Quetzal")?;
    assert!(bosco < quetzal);
    assert!(!form.contains("Aaltonen"));
    // Products A to Z within a producer, each with its quantity field
    let honey = form.find("Hunajaa").ok_or("no honey")?;
    let oil = form.find("Oliiviöljyä").ok_or("no oil")?;
    assert!(honey < oil);
    assert!(form.contains(&format!(r#"name="{}""#, catalog.chocolate)));
    assert!(form.contains("51\u{a0}€"));
    assert!(form.contains("10,10\u{a0}€"));
    assert!(form.contains(r#"name="contact_me_by_fax_only""#));
    Ok(())
}

#[sqlx::test(migrations = false)]
async fn order_form_link_opened_while_ordering_is_closed_goes_to_the_front_page(
    db: PgPool,
) -> TestResult {
    schema(&db).await?;
    welcome(&db, "Tilaukset on suljettu", false).await?;
    let app = site(db, false);
    let opened = get(&app, "/NewOrder").await?;
    assert_eq!(opened.status(), StatusCode::SEE_OTHER);
    assert_eq!(location(&opened), "/");
    let front = body(get_with_cookie(&app, "/", &flash_cookie(&opened)).await?).await?;
    assert!(front.contains("Tilaaminen ei ole tällä hetkellä mahdollista"));
    // Once: the front page clears it
    Ok(())
}

// Sending an order

#[sqlx::test(migrations = false)]
async fn saves_the_customer_order_lines_and_email_job_together(db: PgPool) -> TestResult {
    let catalog = shop(&db).await?;
    let app = site(db.clone(), false);
    let response = order(
        &app,
        "saved@example.com",
        &[
            ("firstName", " Anna-Liisa "),
            ("billingName", " Oliivi Oy, 1234567-8 "),
        ],
        &[(catalog.oil, 1), (catalog.honey, 3)],
    )
    .await?;
    assert_eq!(response.status(), StatusCode::SEE_OTHER);
    assert!(location(&response).starts_with("/ShowOrder?orderId="));

    let (first, last, reverse, billing): (String, String, String, String) = sqlx::query_as(
        "SELECT first_name, last_name, reverse_name, billing_name FROM customers WHERE email = 'saved@example.com'",
    )
    .fetch_one(&db)
    .await?;
    assert_eq!(
        (
            first.as_str(),
            last.as_str(),
            reverse.as_str(),
            billing.as_str()
        ),
        (
            "Anna-Liisa",
            "Virtanen",
            "virtanen anna-liisa",
            "Oliivi Oy, 1234567-8"
        )
    );
    // At the prices of the moment
    assert_eq!(
        ordered_quantities(&db, "saved@example.com").await?,
        [(catalog.oil, 1, 5100), (catalog.honey, 3, 1010)]
    );
    let job: String = sqlx::query_scalar("SELECT status::text FROM email_order_jobs")
        .fetch_one(&db)
        .await?;
    assert_eq!(job, "job_status_not_started", "the IHP worker sends it");

    // The invoice, with the notice that the order was sent
    let invoice = get_with_cookie(&app, location(&response), &flash_cookie(&response)).await?;
    let clears = invoice
        .headers()
        .get(header::SET_COOKIE)
        .and_then(|v| v.to_str().ok())
        .unwrap_or("")
        .to_string();
    let invoice = body(invoice).await?;
    assert!(invoice.contains("Tilaus lähetetty"));
    assert!(clears.contains("Max-Age=0"));
    assert!(invoice.contains("<p>Oliivi Oy, 1234567-8</p><p>Anna-Liisa Virtanen</p>"));
    assert!(invoice.contains("<p>Testikatu 1</p>"));
    assert!(invoice.contains("<p>00100 Helsinki</p>"));
    assert!(invoice.contains("81,30\u{a0}€"), "51 € + 3 × 10,10 €");
    assert!(invoice.contains("Lasku on lähetetty myös sähköpostiinne."));
    assert!(!invoice.contains("<p></p>"));
    Ok(())
}

#[sqlx::test(migrations = false)]
async fn saves_nothing_when_saving_an_order_line_fails(db: PgPool) -> TestResult {
    let catalog = shop(&db).await?;
    sqlx::query(
        "ALTER TABLE ordered_products ADD CONSTRAINT test_fail_lines CHECK (quantity <> 13)",
    )
    .execute(&db)
    .await?;
    let app = site(db.clone(), false);
    let response = order(
        &app,
        "transaction@example.com",
        &[],
        &[(catalog.oil, 1), (catalog.honey, 13)],
    )
    .await?;
    assert_eq!(response.status(), StatusCode::INTERNAL_SERVER_ERROR);
    assert_eq!(customers_with(&db, "transaction@example.com").await?, 0);
    assert_eq!(count(&db, "SELECT count(*) FROM orders").await?, 0);
    assert_eq!(
        count(&db, "SELECT count(*) FROM email_order_jobs").await?,
        0
    );
    Ok(())
}

#[sqlx::test(migrations = false)]
async fn accepts_an_order_without_a_last_name(db: PgPool) -> TestResult {
    let catalog = shop(&db).await?;
    let app = site(db.clone(), false);
    order(
        &app,
        "onename@example.com",
        &[("lastName", "")],
        &[(catalog.oil, 1)],
    )
    .await?;
    assert_eq!(
        ordered_quantities(&db, "onename@example.com").await?.len(),
        1
    );
    Ok(())
}

#[sqlx::test(migrations = false)]
async fn refuses_an_incomplete_address_and_keeps_what_was_filled_in(db: PgPool) -> TestResult {
    let catalog = shop(&db).await?;
    let app = site(db.clone(), false);
    for (field, value, message) in [
        ("streetAddress", "", "Tämä kenttä vaaditaan"),
        ("postalCode", "", "Postinumerossa on viisi numeroa"),
        ("postalCode", "1234", "Postinumerossa on viisi numeroa"),
        (
            "postalCode",
            "00100 Helsinki",
            "Postinumerossa on viisi numeroa",
        ),
        ("city", " ", "Tämä kenttä vaaditaan"),
        ("phone", "123", "Puhelinnumero on virheellinen"),
        ("firstName", "", "Tämä kenttä vaaditaan"),
    ] {
        let email = format!("refused-{field}@example.com");
        let response = order(&app, &email, &[(field, value)], &[(catalog.oil, 2)]).await?;
        assert_eq!(response.status(), StatusCode::OK, "{field} {value:?}");
        let form = body(response).await?;
        assert!(form.contains(message), "{field} {value:?}");
        assert!(form.contains("is-invalid"));
        // The other details and the quantities stay
        assert!(form.contains(&format!(r#"value="{email}""#)));
        assert!(form.contains(&format!(r#"name="{}" value="2""#, catalog.oil)));
        assert_eq!(customers_with(&db, &email).await?, 0);
    }
    let form = body(order(&app, "not an email", &[], &[(catalog.oil, 1)]).await?).await?;
    assert!(form.contains("Sähköposti on virheellinen"));
    Ok(())
}

#[sqlx::test(migrations = false)]
async fn refuses_an_order_with_no_products(db: PgPool) -> TestResult {
    let catalog = shop(&db).await?;
    let app = site(db.clone(), false);
    for lines in [vec![], vec![(catalog.oil, 0), (catalog.honey, -2)]] {
        let form = body(order(&app, "empty@example.com", &[], &lines).await?).await?;
        assert!(form.contains("Valitse vähintään yksi tuote."));
    }
    // Untouched quantity fields are sent empty
    let empty = [(catalog.oil.to_string(), String::new())];
    let form = body(
        post(
            &app,
            "/CreateOrder",
            &order_fields("empty@example.com", &[], &empty),
        )
        .await?,
    )
    .await?;
    assert!(form.contains("Valitse vähintään yksi tuote."));
    assert_eq!(customers_with(&db, "empty@example.com").await?, 0);
    Ok(())
}

#[sqlx::test(migrations = false)]
async fn refuses_a_quantity_that_is_not_a_whole_number(db: PgPool) -> TestResult {
    let catalog = shop(&db).await?;
    let app = site(db.clone(), false);
    let lines = [(catalog.oil.to_string(), "1.5".to_string())];
    let response = post(
        &app,
        "/CreateOrder",
        &order_fields("half@example.com", &[], &lines),
    )
    .await?;
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    assert_eq!(customers_with(&db, "half@example.com").await?, 0);
    Ok(())
}

#[sqlx::test(migrations = false)]
async fn refuses_the_order_when_an_ordered_product_or_its_producer_was_disabled(
    db: PgPool,
) -> TestResult {
    let catalog = shop(&db).await?;
    let app = site(db.clone(), false);
    sqlx::query("UPDATE products SET enabled = false WHERE id = $1")
        .bind(catalog.honey)
        .execute(&db)
        .await?;
    let form = body(
        order(
            &app,
            "late@example.com",
            &[],
            &[(catalog.oil, 1), (catalog.honey, 2)],
        )
        .await?,
    )
    .await?;
    assert!(form.contains("eivät ole enää tilattavissa"));
    assert!(form.contains("<li>Hunajaa (250 g)</li>"));
    assert!(
        form.contains(&format!(r#"name="{}" value="1""#, catalog.oil)),
        "the other quantities stay"
    );
    assert!(
        !form.contains("Valitse vähintään yksi tuote"),
        "one notice at a time"
    );

    sqlx::query("UPDATE producers SET enabled = false WHERE id = $1")
        .bind(catalog.quetzal)
        .execute(&db)
        .await?;
    let form = body(order(&app, "late@example.com", &[], &[(catalog.chocolate, 1)]).await?).await?;
    assert!(form.contains("<li>Chilisuklaa (60 g)</li>"));
    assert_eq!(customers_with(&db, "late@example.com").await?, 0);

    // A disabled product that wasn't ordered is no reason to refuse
    order(&app, "fine@example.com", &[], &[(catalog.oil, 1)]).await?;
    assert_eq!(ordered_quantities(&db, "fine@example.com").await?.len(), 1);
    Ok(())
}

#[sqlx::test(migrations = false)]
async fn tells_the_customer_when_ordering_closed_before_they_sent_the_order(
    db: PgPool,
) -> TestResult {
    let catalog = shop(&db).await?;
    welcome(&db, "Tilaukset on suljettu", false).await?;
    let app = site(db.clone(), false);
    let sent = order(&app, "late@example.com", &[], &[(catalog.oil, 1)]).await?;
    assert_eq!(location(&sent), "/");
    let front = body(get_with_cookie(&app, "/", &flash_cookie(&sent)).await?).await?;
    assert!(front.contains("Tilaustasi ei lähetetty, koska tilaukset on suljettu."));
    assert!(front.contains("bg-red-100"));
    assert_eq!(customers_with(&db, "late@example.com").await?, 0);
    Ok(())
}

// The invoice

#[sqlx::test(migrations = false)]
async fn says_on_the_invoice_when_it_has_been_paid_or_cancelled(db: PgPool) -> TestResult {
    let catalog = shop(&db).await?;
    sqlx::query("INSERT INTO payment_instructions (text) VALUES ('Tilille **FI12 3456**')")
        .execute(&db)
        .await?;
    let app = site(db.clone(), false);
    let sent = order(&app, "invoice@example.com", &[], &[(catalog.oil, 1)]).await?;
    let url = location(&sent).to_string();
    let open = body(get(&app, &url).await?).await?;
    assert!(open.contains("<h2>Maksuohjeet</h2>"));
    assert!(open.contains("<strong>FI12 3456</strong>"));

    sqlx::query("UPDATE orders SET paid_at = now()")
        .execute(&db)
        .await?;
    let paid = body(get(&app, &url).await?).await?;
    assert!(paid.contains("Lasku on maksettu."));
    assert!(!paid.contains("Maksuohjeet"));

    sqlx::query("UPDATE orders SET cancelled_at = now()")
        .execute(&db)
        .await?;
    let cancelled = body(get(&app, &url).await?).await?;
    assert!(
        cancelled.contains("Lasku on mitätöity."),
        "cancelled wins over paid"
    );
    Ok(())
}

#[sqlx::test(migrations = false)]
async fn an_unknown_order_or_page_is_not_found(db: PgPool) -> TestResult {
    schema(&db).await?;
    let app = site(db, false);
    for uri in [
        &format!("/ShowOrder?orderId={}", Uuid::nil()),
        "/ShowOrder?orderId=nonsense",
        "/ShowOrder",
        "/no-such-page",
    ] {
        let response = get(&app, uri).await?;
        assert_eq!(response.status(), StatusCode::NOT_FOUND, "{uri}");
        assert!(body(response).await?.contains("Sivua ei löytynyt"));
    }
    // No public way to cancel an order
    let response = post(&app, "/UpdateCancelOrder", &[]).await?;
    assert_ne!(response.status(), StatusCode::OK);
    Ok(())
}

#[sqlx::test(migrations = false)]
async fn serves_the_ihp_apps_static_files(db: PgPool) -> TestResult {
    schema(&db).await?;
    let app = site(db, false);
    let logo = get(&app, "/img/logo.jpg").await?;
    assert_eq!(logo.status(), StatusCode::OK);
    Ok(())
}

// The newsletter

#[sqlx::test(migrations = false)]
async fn saves_a_newsletter_subscriber(db: PgPool) -> TestResult {
    schema(&db).await?;
    let app = site(db.clone(), false);
    let form = body(get(&app, "/NewEmail").await?).await?;
    assert!(form.contains(r#"name="contact_me_by_fax_only""#));

    let response = post(
        &app,
        "/CreateEmail",
        &[
            ("firstName", " Uutis "),
            ("lastName", "Tilaaja"),
            ("email", "uutiset@example.com"),
            ("phone", "smuggled"),
            ("contact_me_by_fax_only", ""),
        ],
    )
    .await?;
    assert_eq!(location(&response), "/");
    let front = body(get_with_cookie(&app, "/", &flash_cookie(&response)).await?).await?;
    assert!(front.contains("Tiedot tallennettu"));
    let (first, reverse, phone): (String, String, String) = sqlx::query_as(
        "SELECT first_name, reverse_name, phone FROM customers WHERE email = 'uutiset@example.com'",
    )
    .fetch_one(&db)
    .await?;
    assert_eq!(
        (first.as_str(), reverse.as_str(), phone.as_str()),
        ("Uutis", "tilaaja uutis", "")
    );

    let form = body(
        post(
            &app,
            "/CreateEmail",
            &[("firstName", ""), ("email", "nope")],
        )
        .await?,
    )
    .await?;
    assert!(form.contains("Tämä kenttä vaaditaan"));
    assert!(form.contains("Sähköposti on virheellinen"));
    Ok(())
}

// Forms filled in by a bot

#[sqlx::test(migrations = false)]
async fn thanks_a_bot_but_saves_nothing(db: PgPool) -> TestResult {
    let catalog = shop(&db).await?;
    let app = site(db.clone(), false);
    let response = order(
        &app,
        "botti@example.com",
        &[("contact_me_by_fax_only", "http://spam.example.com")],
        &[(catalog.oil, 2)],
    )
    .await?;
    assert_eq!(location(&response), "/");
    assert_eq!(flash_cookie(&response), "flash=order-sent");
    let response = post(
        &app,
        "/CreateEmail",
        &[
            ("firstName", "Botti"),
            ("email", "uutisbotti@example.com"),
            ("contact_me_by_fax_only", "x"),
        ],
    )
    .await?;
    assert_eq!(location(&response), "/");
    assert_eq!(count(&db, "SELECT count(*) FROM customers").await?, 0);
    assert_eq!(
        count(&db, "SELECT count(*) FROM email_order_jobs").await?,
        0
    );
    Ok(())
}

#[sqlx::test(migrations = false)]
async fn ignores_a_flash_cookie_it_did_not_set(db: PgPool) -> TestResult {
    schema(&db).await?;
    let app = site(db, false);
    let page = body(get_with_cookie(&app, "/", "flash=<script>").await?).await?;
    assert!(!page.contains("<script>"));
    assert!(!page.contains("bg-green-100"));
    Ok(())
}
