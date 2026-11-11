//! The data of a public demo (`APP_DEMO`), reset every night by
//! `bosco-reset-demo`: the IHP app's `Application/DemoData.hs`. The catalog
//! from the fixtures, fake payment details and a few seasons of made-up
//! orders. Older seasons have lower prices, since each product's price went
//! up a little most years.
//!
//! The orders come from a seeded generator, the same as the IHP app's, so
//! the same seed and time give the same orders as there, and the tests can
//! check them.

use chrono::{DateTime, Datelike, NaiveDate, TimeDelta, Utc};
use sqlx::PgPool;
use uuid::Uuid;

use crate::db::NewCustomer;
use crate::views::DEMO_PAYMENT_DETAILS;

/// The olive oils, four times as popular as the other products. By id, as
/// the catalogs in other languages (Fixtures.en.sql) have the same ids.
const OLIVE_OILS: [Uuid; 2] = [
    Uuid::from_u128(0x61db0ec5_698a_4b48_b19b_995d41472bb1), // 250 ml
    Uuid::from_u128(0x0fa0cd0f_921a_429e_a184_3a9a547f0990), // 3 l
];

/// How many ordering seasons the demo has: this one and the three before
pub const SEASONS: usize = 4;

/// A seed that changes every day, so each night's orders differ: the day's
/// Modified Julian Day number
pub fn seed_for(now: DateTime<Utc>) -> u64 {
    let epoch = NaiveDate::from_ymd_opt(1858, 11, 17).expect("a date");
    (now.date_naive() - epoch).num_days() as u64
}

/// The INSERT statements of a pg_dump like Fixtures.sql. Its other
/// statements change session settings or need a superuser, and the rows
/// don't need them. Texts may hold line breaks and semicolons, so a
/// statement ends at the first semicolon outside quotes.
pub fn fixture_inserts(sql: &str) -> Vec<String> {
    let chars: Vec<char> = sql.chars().collect();
    let mut statements = Vec::new();
    let mut current = String::new();
    let mut i = 0;
    while i < chars.len() {
        match chars[i] {
            '\'' => {
                // A quoted text up to its closing quote; '' is a quote in it
                current.push('\'');
                i += 1;
                while i < chars.len() {
                    if chars[i] == '\'' && chars.get(i + 1) == Some(&'\'') {
                        current.push_str("''");
                        i += 2;
                    } else if chars[i] == '\'' {
                        current.push('\'');
                        i += 1;
                        break;
                    } else {
                        current.push(chars[i]);
                        i += 1;
                    }
                }
                continue;
            }
            '-' if chars.get(i + 1) == Some(&'-') && current.trim().is_empty() => {
                while i < chars.len() && chars[i] != '\n' {
                    i += 1;
                }
                continue;
            }
            ';' => {
                current.push(';');
                statements.push(std::mem::take(&mut current));
            }
            c => current.push(c),
        }
        i += 1;
    }
    if !current.trim().is_empty() {
        statements.push(current);
    }
    statements
        .into_iter()
        .map(|statement| statement.trim().to_string())
        .filter(|statement| statement.starts_with("INSERT INTO "))
        .collect()
}

/// A product as the demo's orders need it
#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::FromRow)]
pub struct CatalogItem {
    #[sqlx(rename = "id")]
    pub product_id: Uuid,
    /// This season's price, in cents
    pub price: i32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DemoCustomer {
    pub first_name: String,
    pub last_name: String,
    pub email: String,
    pub phone: String,
    pub street_address: String,
    pub postal_code: String,
    pub city: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DemoLine {
    pub product_id: Uuid,
    pub quantity: i32,
    pub unit_price: i32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DemoOrder {
    pub customer: DemoCustomer,
    pub ordered_at: DateTime<Utc>,
    pub invoiced_at: Option<DateTime<Utc>>,
    pub paid_at: Option<DateTime<Utc>>,
    pub delivered_at: Option<DateTime<Utc>>,
    pub cancelled_at: Option<DateTime<Utc>>,
    pub lines: Vec<DemoLine>,
}

/// The IHP app's seeded generator, SplitMix64: the same numbers in the
/// same order for the same seed
pub struct Gen(u64);

impl Gen {
    pub fn new(seed: u64) -> Self {
        Self(seed)
    }

    fn word(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9e37_79b9_7f4a_7c15);
        let s = self.0;
        let z1 = (s ^ (s >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
        let z2 = (z1 ^ (z1 >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
        z2 ^ (z2 >> 31)
    }

    /// A number from lo to hi, both included
    pub fn int(&mut self, lo: i64, hi: i64) -> i64 {
        lo + (self.word() % (hi - lo + 1) as u64) as i64
    }

    pub fn chance(&mut self, p: f64) -> bool {
        ((self.word() >> 11) as f64) / 9_007_199_254_740_992.0 < p
    }

    fn weighted<T: Clone>(&mut self, choices: &[(i64, T)]) -> T {
        let total = choices.iter().map(|(weight, _)| weight).sum();
        let mut remaining = self.int(1, total);
        for (i, (weight, choice)) in choices.iter().enumerate() {
            if remaining <= *weight || i == choices.len() - 1 {
                return choice.clone();
            }
            remaining -= weight;
        }
        unreachable!("no choices")
    }

    fn pick<T: Clone>(&mut self, choices: &[T]) -> T {
        let weighted: Vec<(i64, T)> = choices.iter().map(|c| (1, c.clone())).collect();
        self.weighted(&weighted)
    }

    /// Up to n different choices
    fn distinct<T: Clone>(&mut self, n: usize, choices: &[(i64, T)]) -> Vec<T> {
        let mut choices = choices.to_vec();
        let mut chosen = Vec::new();
        for _ in 0..n {
            if choices.is_empty() {
                break;
            }
            let indexed: Vec<(i64, usize)> = choices
                .iter()
                .enumerate()
                .map(|(i, (w, _))| (*w, i))
                .collect();
            let i = self.weighted(&indexed);
            chosen.push(choices.remove(i).1);
        }
        chosen
    }

    fn time_between(&mut self, start: DateTime<Utc>, end: DateTime<Utc>) -> DateTime<Utc> {
        let seconds = ((end - start).num_milliseconds() as f64 / 1000.0).floor() as i64;
        let offset = self.int(0, seconds.max(1));
        start + TimeDelta::seconds(offset)
    }
}

/// Each product's price by season, this season first. Going back a year,
/// the price is 2–9% lower, or the same (about one year in four), rounded
/// to ten cents.
pub fn season_prices(seed: u64, catalog: &[CatalogItem]) -> Vec<(Uuid, Vec<i32>)> {
    let mut rng = Gen::new(seed ^ 0x5eed);
    catalog
        .iter()
        .map(|item| {
            let mut prices = vec![item.price];
            let mut newer = item.price;
            for _ in 1..SEASONS {
                let unchanged = rng.chance(0.25);
                let percent = rng.int(2, 9);
                // Haskell's round, which rounds halves to even
                let lower = (f64::from(newer) / (1.0 + percent as f64 / 100.0) / 10.0)
                    .round_ties_even() as i32
                    * 10;
                let older = if unchanged { newer } else { newer.min(lower) };
                prices.push(older);
                newer = older;
            }
            (item.product_id, prices)
        })
        .collect()
}

/// The time `years` years before, on the same day of the year, or the 28th
/// for the 29th of February (`addGregorianYearsClip`)
fn years_ago(years: i32, time: DateTime<Utc>) -> DateTime<Utc> {
    let date = time.date_naive();
    let year = date.year() - years;
    let day = date
        .with_year(year)
        .or_else(|| NaiveDate::from_ymd_opt(year, date.month(), 28))
        .expect("a date");
    day.and_time(time.time()).and_utc()
}

/// The orders of every season, oldest first. A season is the six weeks
/// before this day of its year, so this season's newest orders are from
/// the last few days and still waiting to be handled. The business grows,
/// so later seasons have more orders, and regular customers come back.
pub fn demo_orders(seed: u64, now: DateTime<Utc>, catalog: &[CatalogItem]) -> Vec<DemoOrder> {
    if catalog.is_empty() {
        return Vec::new();
    }
    let prices = season_prices(seed, catalog);
    let price_of = |item: &CatalogItem, age: usize| {
        prices
            .iter()
            .find(|(id, _)| *id == item.product_id)
            .and_then(|(_, p)| p.get(age).copied())
            .unwrap_or(item.price)
    };
    let mut rng = Gen::new(seed);
    let regulars: Vec<DemoCustomer> = (0..12).map(|_| customer(&mut rng)).collect();
    let weighted_catalog: Vec<(i64, CatalogItem)> = catalog
        .iter()
        .map(|item| {
            (
                if OLIVE_OILS.contains(&item.product_id) {
                    4
                } else {
                    1
                },
                *item,
            )
        })
        .collect();
    let mut all = Vec::new();
    for age in (0..SEASONS).rev() {
        let end = if age == 0 {
            now - TimeDelta::hours(1)
        } else {
            years_ago(age as i32, now)
        };
        let start = end - TimeDelta::days(42);
        let count = rng.int(0, 6) + (32 - 5 * age as i64);
        let returning: Vec<DemoCustomer> = regulars
            .iter()
            .filter(|_| rng.chance(0.6))
            .cloned()
            .collect();
        let newcomers = (count - returning.len() as i64).max(0);
        let mut customers = returning;
        customers.extend((0..newcomers).map(|_| customer(&mut rng)));
        let mut orders: Vec<DemoOrder> = customers
            .into_iter()
            .map(|customer| {
                let ordered_at = rng.time_between(start, end);
                let count = rng.weighted(&[(5, 1usize), (4, 2), (2, 3), (1, 4)]);
                let items = rng.distinct(count, &weighted_catalog);
                let lines = items
                    .iter()
                    .map(|item| DemoLine {
                        product_id: item.product_id,
                        quantity: rng.weighted(&[(6, 1), (3, 2), (1, 3)]),
                        unit_price: price_of(item, age),
                    })
                    .collect();
                states(&mut rng, now, customer, ordered_at, lines)
            })
            .collect();
        orders.sort_by_key(|order| order.ordered_at);
        all.extend(orders);
    }
    all
}

/// What has happened to the order by now: invoiced within two days,
/// usually paid within ten days of that, delivered a few weeks after
/// ordering. Some are cancelled, and an invoice still unpaid after a month
/// is cancelled too.
fn states(
    rng: &mut Gen,
    now: DateTime<Utc>,
    customer: DemoCustomer,
    ordered_at: DateTime<Utc>,
    lines: Vec<DemoLine>,
) -> DemoOrder {
    let cancelled_early = rng.chance(0.04);
    let cancel_days = rng.int(1, 3);
    let invoice_hours = rng.int(4, 48);
    let pays = rng.chance(0.92);
    let pay_days = rng.int(1, 10);
    let delivery_days = rng.int(18, 35);
    let after = |delta: TimeDelta, from: DateTime<Utc>| Some(from + delta).filter(|t| *t <= now);
    let invoiced = if cancelled_early {
        None
    } else {
        after(TimeDelta::hours(invoice_hours), ordered_at)
    };
    let paid = if pays {
        invoiced.and_then(|t| after(TimeDelta::days(pay_days), t))
    } else {
        None
    };
    let delivered = paid.and_then(|_| after(TimeDelta::days(delivery_days), ordered_at));
    let cancelled = if cancelled_early {
        after(TimeDelta::days(cancel_days), ordered_at)
    } else if paid.is_none() {
        invoiced.and_then(|t| after(TimeDelta::days(30), t))
    } else {
        None
    };
    DemoOrder {
        customer,
        ordered_at,
        invoiced_at: invoiced,
        paid_at: paid,
        delivered_at: delivered,
        cancelled_at: cancelled,
        lines,
    }
}

const FIRST_NAMES: [&str; 30] = [
    "Maija",
    "Juhani",
    "Aino",
    "Pekka",
    "Elina",
    "Sanna",
    "Ville",
    "Tuomas",
    "Kaisa-Maria",
    "Olli",
    "Leena",
    "Matti",
    "Hanna",
    "Antti",
    "Laura",
    "Mikko",
    "Riikka",
    "Jussi",
    "Eeva",
    "Timo",
    "Satu",
    "Heikki",
    "Johanna",
    "Kari",
    "Minna",
    "Jari",
    "Tiina",
    "Petri",
    "Anu",
    "Markku",
];

const LAST_NAMES: [&str; 24] = [
    "Virtanen",
    "Korhonen",
    "Mäkinen",
    "Laine",
    "Nieminen",
    "Heikkinen",
    "Hämäläinen",
    "Lehtonen",
    "Järvinen",
    "Koskinen",
    "Salminen",
    "Rantanen",
    "Laaksonen",
    "Mäkelä",
    "Lehtinen",
    "Saarinen",
    "Niemi",
    "Kinnunen",
    "Heinonen",
    "Tuominen",
    "Ahonen",
    "Lindholm",
    "Karjalainen",
    "Hiltunen",
];

const PLACES: [(&str, &str, &str); 12] = [
    ("Mannerheimintie", "00100", "Helsinki"),
    ("Fredrikinkatu", "00120", "Helsinki"),
    ("Hämeenkatu", "33100", "Tampere"),
    ("Puistokatu", "20100", "Turku"),
    ("Rantatie", "90100", "Oulu"),
    ("Kauppakatu", "40100", "Jyväskylä"),
    ("Asemakatu", "70100", "Kuopio"),
    ("Satamakatu", "15100", "Lahti"),
    ("Länsiväylä", "02160", "Espoo"),
    ("Torikatu", "28100", "Pori"),
    ("Kirkkokatu", "53100", "Lappeenranta"),
    ("Koulukatu", "65100", "Vaasa"),
];

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
        .filter(|c| *c != '-')
        .collect();
    format!(
        "{}@example.com",
        plain.split_whitespace().collect::<Vec<_>>().join(".")
    )
}

fn customer(rng: &mut Gen) -> DemoCustomer {
    let first = rng.pick(&FIRST_NAMES);
    let last = rng.pick(&LAST_NAMES);
    let (street, postal_code, city) = rng.pick(&PLACES);
    let number = rng.int(1, 60);
    let flat = rng.chance(0.5);
    let stair = rng.pick(&["A", "B", "C"]);
    let door = rng.int(1, 40);
    let prefix = rng.pick(&["040", "041", "044", "045", "050"]);
    let digits: String = (0..7).map(|_| rng.int(0, 9).to_string()).collect();
    let street_address = if flat {
        format!("{street} {number} {stair} {door}")
    } else {
        format!("{street} {number}")
    };
    DemoCustomer {
        first_name: first.to_string(),
        last_name: last.to_string(),
        email: email_for(&format!("{first} {last}")),
        phone: format!("{prefix} {} {}", &digits[..3], &digits[3..]),
        street_address,
        postal_code: postal_code.to_string(),
        city: city.to_string(),
    }
}

/// Subscribed to the newsletter without ordering: a name and an email
fn newsletter_subscribers() -> Vec<DemoCustomer> {
    let mut rng = Gen::new(0xfeed);
    (0..5)
        .map(|_| {
            let c = customer(&mut rng);
            DemoCustomer {
                phone: String::new(),
                street_address: String::new(),
                postal_code: String::new(),
                city: String::new(),
                ..c
            }
        })
        .collect()
}

async fn insert_customer(tx: &mut sqlx::PgConnection, c: &DemoCustomer) -> sqlx::Result<Uuid> {
    let reverse_name = NewCustomer {
        first_name: c.first_name.clone(),
        last_name: c.last_name.clone(),
        ..NewCustomer::default()
    }
    .reverse_name();
    sqlx::query_scalar(
        "INSERT INTO customers (first_name, last_name, reverse_name, email, phone, street_address,
                                postal_code, city)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING id",
    )
    .bind(&c.first_name)
    .bind(&c.last_name)
    .bind(reverse_name)
    .bind(&c.email)
    .bind(&c.phone)
    .bind(&c.street_address)
    .bind(&c.postal_code)
    .bind(&c.city)
    .fetch_one(&mut *tx)
    .await
}

/// Empties the demo's data and fills it again, in one transaction. Logins
/// are kept, so whoever is logged in stays logged in. Returns the number of
/// orders made.
pub async fn reset(
    db: &PgPool,
    fixtures: &str,
    seed: u64,
    now: DateTime<Utc>,
) -> sqlx::Result<usize> {
    let mut tx = db.begin().await?;
    // Children before parents, for the foreign keys
    for sql in [
        "DELETE FROM text_changes",
        "DELETE FROM email_order_jobs",
        "DELETE FROM ordered_products",
        "DELETE FROM orders",
        "DELETE FROM customers",
        "DELETE FROM products",
        "DELETE FROM producers",
        "DELETE FROM welcome_messages",
        "DELETE FROM payment_instructions",
    ] {
        sqlx::query(sql).execute(&mut *tx).await?;
    }
    for statement in fixture_inserts(fixtures) {
        // The fixtures' own statements, as the IHP app ran them
        sqlx::raw_sql(sqlx::AssertSqlSafe(statement))
            .execute(&mut *tx)
            .await?;
    }
    sqlx::query("INSERT INTO payment_instructions (text) VALUES ($1)")
        .bind(DEMO_PAYMENT_DETAILS)
        .execute(&mut *tx)
        .await?;
    // In the database's order, after the fixtures' inserts theirs, as the
    // IHP app read them: the generator's numbers follow it
    let catalog: Vec<CatalogItem> = sqlx::query_as("SELECT id, price FROM products WHERE enabled")
        .fetch_all(&mut *tx)
        .await?;
    let orders = demo_orders(seed, now, &catalog);
    for order in &orders {
        let customer = insert_customer(&mut tx, &order.customer).await?;
        let id: Uuid = sqlx::query_scalar(
            "INSERT INTO orders (customer_id, ordered_at, invoiced_at, paid_at, delivered_at, cancelled_at)
             VALUES ($1, $2, $3, $4, $5, $6) RETURNING id",
        )
        .bind(customer)
        .bind(order.ordered_at)
        .bind(order.invoiced_at)
        .bind(order.paid_at)
        .bind(order.delivered_at)
        .bind(order.cancelled_at)
        .fetch_one(&mut *tx)
        .await?;
        for line in &order.lines {
            sqlx::query(
                "INSERT INTO ordered_products (order_id, product_id, quantity, unit_price)
                 VALUES ($1, $2, $3, $4)",
            )
            .bind(id)
            .bind(line.product_id)
            .bind(line.quantity)
            .bind(line.unit_price)
            .execute(&mut *tx)
            .await?;
        }
    }
    for subscriber in newsletter_subscribers() {
        insert_customer(&mut tx, &subscriber).await?;
    }
    tx.commit().await?;
    Ok(orders.len())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_the_fixtures_inserts() {
        let sql = "SET x = 1;\n-- a comment; with a semicolon\nINSERT INTO a VALUES ('x;y', 'it''s');\nSELECT 1;\n  INSERT INTO b VALUES ('two\nlines');";
        assert_eq!(
            fixture_inserts(sql),
            [
                "INSERT INTO a VALUES ('x;y', 'it''s');",
                "INSERT INTO b VALUES ('two\nlines');"
            ]
        );
    }

    #[test]
    fn emails_without_accents_or_hyphens() {
        assert_eq!(
            email_for("Kaisa-Maria Mäkinen"),
            "kaisamaria.makinen@example.com"
        );
        assert_eq!(email_for("Aino Hämäläinen"), "aino.hamalainen@example.com");
    }

    #[test]
    fn the_seed_is_the_days_number() {
        let now: DateTime<Utc> = "2026-11-11T15:00:00Z".parse().unwrap();
        assert_eq!(seed_for(now), 61355);
        assert_eq!(
            years_ago(2, "2028-02-29T10:00:00Z".parse().unwrap()),
            "2026-02-28T10:00:00Z".parse::<DateTime<Utc>>().unwrap()
        );
    }
}
