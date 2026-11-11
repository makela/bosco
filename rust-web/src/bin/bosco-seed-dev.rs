//! Fills a development database with data to browse, as the IHP app's
//! `Application/Script/SeedDevData.hs`: orders from this season and the two
//! before it in every state, a returning customer, newsletter-only
//! subscribers, a welcome message, payment instructions and a login for
//! each role: admin, delivery person and promoter. The passwords are
//! printed at the end. The catalog must be there already (the fixtures,
//! which `devenv up` loads into a new database).
//!
//! It refuses to run when the database already has orders, so it can't add
//! made-up orders to a database that holds real ones. No email jobs are
//! made, so nothing gets sent. `DATABASE_URL` is the database, as in the
//! project's dev shell:
//!
//! ```sh
//! cd rust-web && nix develop path:. -c cargo run --bin bosco-seed-dev
//! ```

use std::env;

use bosco_web::db::{NewCustomer, Roles};
use bosco_web::{db, password};
use chrono::{DateTime, Datelike, NaiveDate, TimeDelta, Utc};
use sqlx::postgres::PgPoolOptions;
use sqlx::{PgConnection, PgPool};
use uuid::Uuid;

/// A customer: name, phone, and street, postal code and city
type Person = (
    &'static str,
    &'static str,
    (&'static str, &'static str, &'static str),
);

const MAIJA: Person = (
    "Maija Virtanen",
    "040 123 4567",
    ("Mannerheimintie 12 B 7", "00100", "Helsinki"),
);
const JUHANI: Person = (
    "Juhani Korhonen",
    "050-765 4321",
    ("Hämeenkatu 3 A 1", "33100", "Tampere"),
);
const AINO: Person = (
    "Aino Mäkinen",
    "+358 44 987 6543",
    ("Puistokatu 8", "20100", "Turku"),
);
const PEKKA: Person = (
    "Pekka Laine",
    "045 222 3344",
    ("Rantatie 21", "90100", "Oulu"),
);
const ELINA: Person = (
    "Elina Nieminen",
    "0401112233",
    ("Kauppakatu 15 C 22", "40100", "Jyväskylä"),
);
const SANNA: Person = (
    "Sanna Heikkinen",
    "044 555 6677",
    ("Asemakatu 4", "70100", "Kuopio"),
);
const VILLE: Person = (
    "Ville Hämäläinen",
    "+358 40 246 8101",
    ("Satamakatu 9", "15100", "Lahti"),
);
const TUOMAS: Person = (
    "Tuomas Lehtonen",
    "045-998 7766",
    ("Kirkkokatu 30 A 5", "90100", "Oulu"),
);
const KAISA: Person = (
    "Kaisa-Maria Järvinen",
    "050 333 4455",
    ("Länsiväylä 101 D 44", "02160", "Espoo"),
);
const OLLI: Person = (
    "Olli Koskinen",
    "+358 40 777 8899",
    ("Torikatu 2", "28100", "Pori"),
);

/// A product of the fixtures, its name and package, and how many
type Item = (&'static str, &'static str, i32);

fn oil3(n: i32) -> Item {
    ("Oliiviöljyä", "3 l kanisteri", n)
}
fn oil250(n: i32) -> Item {
    ("Oliiviöljyä", "250 ml lasipullo", n)
}
fn almonds(n: i32) -> Item {
    ("Luomumantelit, kuorellinen", "500g", n)
}
fn basil(n: i32) -> Item {
    ("Basilikankukkaviinietikkaa", "250 ml lasipullo", n)
}
fn mint(n: i32) -> Item {
    ("Minttu-laventeliviinietikkaa", "250 ml lasipullo", n)
}
fn marzipan(n: i32) -> Item {
    ("Luomumarsipaania", "250 g", n)
}
fn vinegar500(n: i32) -> Item {
    ("Valkoviinietikkaa", "500 ml lasipullo", n)
}
fn raisins(n: i32) -> Item {
    ("Zibibbo rusinoita", "250 g", n)
}
fn capers(n: i32) -> Item {
    ("Luomukaprista suolassa", "200 g", n)
}
fn pistachios(n: i32) -> Item {
    ("Bronten pistaasipähkinöitä, kuivattuja", "100 g", n)
}
fn chocolate(name: &'static str, n: i32) -> Item {
    (name, "60 g", n)
}

/// An order as it is seeded: its handling in days after ordering (None:
/// not yet), and a factor below 1 for older seasons' prices, to show that
/// orders keep their prices
struct SeedOrder {
    person: Person,
    ordered_at: DateTime<Utc>,
    items: Vec<Item>,
    invoiced: Option<i64>,
    paid: Option<i64>,
    delivered: Option<i64>,
    cancelled: Option<i64>,
    price_factor: f64,
}

fn seed_orders(now: DateTime<Utc>) -> Vec<SeedOrder> {
    let this_year = now.year();
    // Ordered on that day of the year `years_ago` years ago, at 16:00 UTC
    let old = |years_ago: i32,
               month: u32,
               day: u32,
               person: Person,
               items: Vec<Item>,
               invoiced,
               paid,
               delivered| SeedOrder {
        person,
        ordered_at: NaiveDate::from_ymd_opt(this_year - years_ago, month, day)
            .expect("a date")
            .and_hms_opt(16, 0, 0)
            .expect("a time")
            .and_utc(),
        items,
        invoiced,
        paid,
        delivered,
        cancelled: None,
        price_factor: if years_ago >= 2 { 0.9 } else { 1.0 },
    };
    let recent =
        |days_ago: i64, person: Person, items: Vec<Item>, invoiced, paid, delivered| SeedOrder {
            person,
            ordered_at: now - TimeDelta::days(days_ago),
            items,
            invoiced,
            paid,
            delivered,
            cancelled: None,
            price_factor: 1.0,
        };
    let cancelled = |order: SeedOrder, days| SeedOrder {
        cancelled: Some(days),
        ..order
    };
    vec![
        // Two seasons ago: everything handled, at about 10% lower prices
        old(
            2,
            10,
            8,
            MAIJA,
            vec![oil3(1), almonds(2)],
            Some(3),
            Some(9),
            Some(40),
        ),
        old(
            2,
            10,
            15,
            JUHANI,
            vec![oil3(2), chocolate("Kahvisuklaa", 4)],
            Some(3),
            Some(6),
            Some(35),
        ),
        old(
            2,
            10,
            22,
            AINO,
            vec![basil(2), marzipan(1), chocolate("Suolasuklaa", 3)],
            Some(2),
            Some(12),
            Some(30),
        ),
        old(2, 11, 2, PEKKA, vec![oil250(6)], Some(1), Some(4), Some(25)),
        // Last season: mostly handled, one cancelled
        old(
            1,
            10,
            6,
            MAIJA,
            vec![oil3(1), pistachios(2)],
            Some(2),
            Some(5),
            Some(38),
        ),
        old(
            1,
            10,
            12,
            ELINA,
            vec![vinegar500(2), mint(1), chocolate("Chilisuklaa", 2)],
            Some(2),
            Some(10),
            Some(36),
        ),
        old(1, 10, 19, JUHANI, vec![oil3(2)], Some(1), Some(8), Some(33)),
        cancelled(
            old(
                1,
                10,
                25,
                SANNA,
                vec![raisins(2), capers(2)],
                None,
                None,
                None,
            ),
            2,
        ),
        old(
            1,
            11,
            3,
            VILLE,
            vec![
                oil250(4),
                chocolate("Inkiväärisuklaa", 2),
                chocolate("Kanelisuklaa", 2),
            ],
            Some(1),
            Some(3),
            Some(28),
        ),
        // This season (the last four weeks): every state
        recent(
            27,
            MAIJA,
            vec![oil3(2), almonds(1), chocolate("Sesam-appelsiinisuklaa", 2)],
            Some(1),
            Some(6),
            Some(25),
        ),
        recent(
            23,
            JUHANI,
            vec![oil3(1), ("Valkoviinietikkaa", "250 ml lasipullo", 3)],
            Some(2),
            Some(9),
            None,
        ),
        recent(
            18,
            AINO,
            vec![basil(1), mint(1), marzipan(2)],
            Some(1),
            None,
            None,
        ),
        recent(
            14,
            TUOMAS,
            vec![
                oil250(3),
                chocolate("Chilisuklaa", 1),
                chocolate("Suolasuklaa", 1),
            ],
            Some(1),
            None,
            Some(10),
        ),
        cancelled(
            recent(10, ELINA, vec![pistachios(3), raisins(1)], None, None, None),
            3,
        ),
        recent(
            5,
            KAISA,
            vec![oil3(1), capers(2), chocolate("Inkiväärisuklaa", 2)],
            None,
            None,
            None,
        ),
        recent(2, OLLI, vec![vinegar500(1)], None, None, None),
    ]
}

const NEWSLETTER_SUBSCRIBERS: [&str; 3] = ["Leena Salminen", "Matti Rantanen", "Hanna Laaksonen"];

/// firstname.lastname@example.com, without accents or hyphens
fn email_for(name: &str) -> String {
    let plain: String = name
        .to_lowercase()
        .chars()
        .map(|c| match c {
            'ä' | 'å' => 'a',
            'ö' => 'o',
            c => c,
        })
        .collect();
    let words: Vec<&str> = plain.split_whitespace().collect();
    let first = words.first().copied().unwrap_or_default();
    let last = words.last().copied().unwrap_or_default();
    format!("{first}.{last}@example.com").replace('-', "")
}

async fn create_customer(
    tx: &mut PgConnection,
    name: &str,
    phone: &str,
    address: (&str, &str, &str),
) -> sqlx::Result<Uuid> {
    // The seed names have one last name
    let (first_name, last_name) = name.rsplit_once(' ').unwrap_or((name, ""));
    let customer = NewCustomer {
        first_name: first_name.to_string(),
        last_name: last_name.to_string(),
        email: email_for(name),
        phone: phone.to_string(),
        street_address: address.0.to_string(),
        postal_code: address.1.to_string(),
        city: address.2.to_string(),
        ..NewCustomer::default()
    };
    sqlx::query_scalar(
        "INSERT INTO customers (first_name, last_name, reverse_name, email, phone, street_address,
                                postal_code, city)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING id",
    )
    .bind(&customer.first_name)
    .bind(&customer.last_name)
    .bind(customer.reverse_name())
    .bind(&customer.email)
    .bind(&customer.phone)
    .bind(&customer.street_address)
    .bind(&customer.postal_code)
    .bind(&customer.city)
    .fetch_one(&mut *tx)
    .await
}

async fn create_order(
    tx: &mut PgConnection,
    order: &SeedOrder,
) -> Result<(), Box<dyn std::error::Error>> {
    let (name, phone, address) = order.person;
    let customer = create_customer(tx, name, phone, address).await?;
    let after = |days: Option<i64>| days.map(|d| order.ordered_at + TimeDelta::days(d));
    let id: Uuid = sqlx::query_scalar(
        "INSERT INTO orders (customer_id, ordered_at, invoiced_at, paid_at, delivered_at, cancelled_at)
         VALUES ($1, $2, $3, $4, $5, $6) RETURNING id",
    )
    .bind(customer)
    .bind(order.ordered_at)
    .bind(after(order.invoiced))
    .bind(after(order.paid))
    .bind(after(order.delivered))
    .bind(after(order.cancelled))
    .fetch_one(&mut *tx)
    .await?;
    for (name, package, quantity) in &order.items {
        let product: Option<(Uuid, i32)> = sqlx::query_as(
            "SELECT id, price FROM products WHERE name = $1 AND package = $2 LIMIT 1",
        )
        .bind(name)
        .bind(package)
        .fetch_optional(&mut *tx)
        .await?;
        let (product, price) =
            product.ok_or_else(|| format!("No product {name} ({package}) in the fixtures"))?;
        // Haskell's round, which rounds halves to even
        let price = (f64::from(price) * order.price_factor / 10.0).round_ties_even() as i32 * 10;
        sqlx::query(
            "INSERT INTO ordered_products (order_id, product_id, quantity, unit_price) VALUES ($1, $2, $3, $4)",
        )
        .bind(id)
        .bind(product)
        .bind(quantity)
        .bind(price)
        .execute(&mut *tx)
        .await?;
    }
    Ok(())
}

/// A login with a random password, or nothing for an existing one: the
/// email with the role, and the password or that it was kept
async fn create_login(
    db: &PgPool,
    email: &str,
    role: &str,
    roles: Roles,
) -> sqlx::Result<(String, String)> {
    if db::login_exists(db, email).await? {
        return Ok((
            email.to_string(),
            "(already existed, password unchanged)".to_string(),
        ));
    }
    let mut bytes = [0u8; 12];
    getrandom::fill(&mut bytes).expect("the system's random numbers");
    let password: String =
        bytes.iter().map(|b| format!("{b:02x}")).collect::<String>()[..16].to_string();
    db::create_login(db, email, &password::hash(&password), roles).await?;
    Ok((format!("{email} ({role})"), password))
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let database_url = env::var("DATABASE_URL").map_err(|_| "DATABASE_URL is not set")?;
    let db = PgPoolOptions::new()
        .max_connections(1)
        .connect(&database_url)
        .await?;
    let orders: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM orders")
        .fetch_one(&db)
        .await?;
    if orders > 0 {
        return Err(
            "The database already has orders; not seeding. Seed a fresh dev database instead."
                .into(),
        );
    }
    let now = Utc::now();
    let mut tx = db.begin().await?;
    let welcome: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM welcome_messages")
        .fetch_one(&mut *tx)
        .await?;
    if welcome == 0 {
        sqlx::query("INSERT INTO welcome_messages (text, is_ordering_enabled) VALUES ($1, true)")
            .bind("Tervetuloa tilaamaan oliiviöljyä ja muita herkkuja Sisiliasta!")
            .execute(&mut *tx)
            .await?;
    }
    let payment: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM payment_instructions")
        .fetch_one(&mut *tx)
        .await?;
    if payment == 0 {
        sqlx::query("INSERT INTO payment_instructions (text) VALUES ($1)")
            .bind("Bosco Falconeria (esimerkkitili)\n\nIBAN FI00 1234 5600 0007 85\n\nBIC ESIMFIHH\n\nMaksun eräpäivä on **15. marraskuuta**.")
            .execute(&mut *tx)
            .await?;
    }
    for order in seed_orders(now) {
        create_order(&mut tx, &order).await?;
    }
    for name in NEWSLETTER_SUBSCRIBERS {
        create_customer(&mut tx, name, "", ("", "", "")).await?;
    }
    tx.commit().await?;
    let role = |admin, deliverer, promoter| Roles {
        admin,
        deliverer,
        promoter,
    };
    let mut logins = Vec::new();
    for (email, name, roles) in [
        ("admin@example.com", "admin", role(true, false, false)),
        (
            "jakelija@example.com",
            "deliverer",
            role(false, true, false),
        ),
        (
            "promoottori@example.com",
            "promoter",
            role(false, false, true),
        ),
    ] {
        logins.push(create_login(&db, email, name, roles).await?);
    }
    println!("Seeded the dev database. Logins at /admin/NewSession:");
    for (email, password) in logins {
        println!("  {email}  {password}");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn emails_of_the_first_and_last_name() {
        assert_eq!(
            email_for("Kaisa-Maria Järvinen"),
            "kaisamaria.jarvinen@example.com"
        );
        assert_eq!(
            email_for("Ville Hämäläinen"),
            "ville.hamalainen@example.com"
        );
    }
}
