//! The public site's queries, on the IHP app's tables (`Application/Schema.sql`)
//! as they are: the same database, both apps at once.

use std::collections::HashMap;

use chrono::{DateTime, Utc};
use sqlx::{FromRow, PgPool};
use uuid::Uuid;

#[derive(Debug, FromRow)]
pub struct WelcomeMessage {
    pub text: String,
    pub is_ordering_enabled: bool,
}

#[derive(Debug, Clone, FromRow)]
pub struct Producer {
    pub id: Uuid,
    pub name: String,
    pub description: String,
}

#[derive(Debug, Clone, FromRow)]
pub struct Product {
    pub id: Uuid,
    pub producer_id: Uuid,
    pub name: String,
    pub description: String,
    pub package: String,
    pub price: i32, // cents
    pub ordering: Option<i32>,
}

#[derive(Debug, FromRow)]
pub struct Customer {
    pub email: String,
    pub phone: String,
    pub first_name: String,
    pub last_name: String,
    pub street_address: String,
    pub postal_code: String,
    pub city: String,
    pub billing_name: String,
}

#[derive(Debug, FromRow)]
pub struct Order {
    pub ordered_at: DateTime<Utc>,
    pub invoiced_at: Option<DateTime<Utc>>,
    pub paid_at: Option<DateTime<Utc>>,
    pub delivered_at: Option<DateTime<Utc>>,
    pub cancelled_at: Option<DateTime<Utc>>,
    #[sqlx(flatten)]
    pub customer: Customer,
}

/// An order line with its product, for the invoice
#[derive(Debug, FromRow)]
pub struct OrderLine {
    pub quantity: i32,
    pub unit_price: i32,
    #[sqlx(flatten)]
    pub product: Product,
}

/// What a customer filled in, trimmed where the IHP app trims
#[derive(Debug, Default, Clone)]
pub struct NewCustomer {
    pub first_name: String,
    pub last_name: String,
    pub billing_name: String,
    pub email: String,
    pub phone: String,
    pub street_address: String,
    pub postal_code: String,
    pub city: String,
}

impl NewCustomer {
    /// Lower-cased last name, then first name, e.g. "virtanen maija":
    /// `reverseNameOf` in the IHP app, which lists and sorts customers by it.
    pub fn reverse_name(&self) -> String {
        words(&[&self.last_name, &self.first_name]).to_lowercase()
    }
}

/// The words of the texts with single spaces, like `unwordsNonEmpty`
pub fn words(texts: &[&str]) -> String {
    texts
        .iter()
        .flat_map(|text| text.split_whitespace())
        .collect::<Vec<_>>()
        .join(" ")
}

impl Customer {
    /// The name for the invoice or the company's name, if given, then the
    /// customer's own name, like `nameLines`
    pub fn name_lines(&self) -> Vec<String> {
        [
            self.billing_name.trim().to_string(),
            words(&[&self.first_name, &self.last_name]),
        ]
        .into_iter()
        .filter(|line| !line.is_empty())
        .collect()
    }

    /// The street on one line, the postal code and city on the next, like
    /// `addressLines`
    pub fn address_lines(&self) -> Vec<String> {
        [
            self.street_address.trim().to_string(),
            words(&[&self.postal_code, &self.city]),
        ]
        .into_iter()
        .filter(|line| !line.is_empty())
        .collect()
    }
}

/// Bosco Falconeria first, then the other producers A to Z (`sortProducers`)
pub fn sort_producers(producers: &mut [Producer]) {
    producers.sort_by_key(|p| (p.name != "Bosco Falconeria", p.name.to_lowercase()));
}

/// Products with an ordering number first, lowest first; then by name, the
/// cheaper first when two share a name (`productOrder`)
pub fn product_order(p: &Product) -> (bool, Option<i32>, String, i32) {
    (
        p.ordering.is_none(),
        p.ordering,
        p.name.to_lowercase(),
        p.price,
    )
}

pub async fn last_welcome_message(db: &PgPool) -> sqlx::Result<Option<WelcomeMessage>> {
    sqlx::query_as(
        "SELECT text, is_ordering_enabled FROM welcome_messages ORDER BY published_at DESC LIMIT 1",
    )
    .fetch_optional(db)
    .await
}

/// The enabled producers in display order, and their enabled products: what
/// can be ordered
pub async fn catalog(db: &PgPool) -> sqlx::Result<(Vec<Producer>, Vec<Product>)> {
    let mut producers: Vec<Producer> =
        sqlx::query_as("SELECT id, name, description FROM producers WHERE enabled")
            .fetch_all(db)
            .await?;
    sort_producers(&mut producers);
    let mut products: Vec<Product> = sqlx::query_as(
        "SELECT products.id, producer_id, products.name, products.description, package, price, ordering
         FROM products JOIN producers ON producers.id = products.producer_id
         WHERE products.enabled AND producers.enabled",
    )
    .fetch_all(db)
    .await?;
    products.sort_by_key(product_order);
    Ok((producers, products))
}

/// Every product, also those that can't be ordered now
pub async fn all_products(db: &PgPool) -> sqlx::Result<Vec<Product>> {
    sqlx::query_as(
        "SELECT id, producer_id, name, description, package, price, ordering FROM products",
    )
    .fetch_all(db)
    .await
}

async fn insert_customer(
    db: impl sqlx::PgExecutor<'_>,
    customer: &NewCustomer,
) -> sqlx::Result<Uuid> {
    sqlx::query_scalar(
        "INSERT INTO customers (first_name, last_name, billing_name, email, phone,
                                street_address, postal_code, city, reverse_name)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING id",
    )
    .bind(&customer.first_name)
    .bind(&customer.last_name)
    .bind(&customer.billing_name)
    .bind(&customer.email)
    .bind(&customer.phone)
    .bind(&customer.street_address)
    .bind(&customer.postal_code)
    .bind(&customer.city)
    .bind(customer.reverse_name())
    .fetch_one(db)
    .await
}

/// Saves the customer, the order, its lines at the products' prices now (so
/// later price changes don't touch it) and, with `email`, the job that
/// emails the invoice, all or nothing. The email worker (worker.rs, or the
/// IHP app's) sends the email. An order taken in the admin has none.
pub async fn create_order(
    db: &PgPool,
    customer: &NewCustomer,
    lines: &[(&Product, i64)],
    email: bool,
) -> sqlx::Result<Uuid> {
    let mut tx = db.begin().await?;
    let customer_id = insert_customer(&mut *tx, customer).await?;
    let order_id: Uuid =
        sqlx::query_scalar("INSERT INTO orders (customer_id) VALUES ($1) RETURNING id")
            .bind(customer_id)
            .fetch_one(&mut *tx)
            .await?;
    for (product, quantity) in lines {
        sqlx::query(
            "INSERT INTO ordered_products (order_id, product_id, quantity, unit_price)
             VALUES ($1, $2, $3, $4)",
        )
        .bind(order_id)
        .bind(product.id)
        .bind(i32::try_from(*quantity).map_err(|e| sqlx::Error::Encode(Box::new(e)))?)
        .bind(product.price)
        .execute(&mut *tx)
        .await?;
    }
    if email {
        sqlx::query("INSERT INTO email_order_jobs (order_id) VALUES ($1)")
            .bind(order_id)
            .execute(&mut *tx)
            .await?;
    }
    tx.commit().await?;
    Ok(order_id)
}

/// A newsletter subscriber: a customer without an order
pub async fn create_subscriber(db: &PgPool, customer: &NewCustomer) -> sqlx::Result<()> {
    insert_customer(db, customer).await.map(|_| ())
}

/// An order with its customer, its lines grouped by producer in display
/// order, and the total in cents
pub struct Invoice {
    pub order: Order,
    pub producers: Vec<(Producer, Vec<OrderLine>)>,
    pub total: i64,
}

pub async fn invoice(db: &PgPool, order_id: Uuid) -> sqlx::Result<Option<Invoice>> {
    let Some(order): Option<Order> = sqlx::query_as(
        "SELECT ordered_at, invoiced_at, paid_at, delivered_at, cancelled_at,
                email, phone, first_name, last_name,
                street_address, postal_code, city, billing_name
         FROM orders JOIN customers ON customers.id = orders.customer_id
         WHERE orders.id = $1",
    )
    .bind(order_id)
    .fetch_optional(db)
    .await?
    else {
        return Ok(None);
    };
    let lines: Vec<OrderLine> = sqlx::query_as(
        "SELECT quantity, unit_price, products.id, producer_id, name, description, package,
                price, ordering
         FROM ordered_products JOIN products ON products.id = ordered_products.product_id
         WHERE order_id = $1",
    )
    .bind(order_id)
    .fetch_all(db)
    .await?;
    let total = lines
        .iter()
        .map(|line| i64::from(line.unit_price) * i64::from(line.quantity))
        .sum();
    let ids: Vec<Uuid> = lines.iter().map(|line| line.product.producer_id).collect();
    let mut producers: Vec<Producer> =
        sqlx::query_as("SELECT id, name, description FROM producers WHERE id = ANY($1)")
            .bind(&ids)
            .fetch_all(db)
            .await?;
    sort_producers(&mut producers);
    let mut by_producer: HashMap<Uuid, Vec<OrderLine>> = HashMap::new();
    for line in lines {
        by_producer
            .entry(line.product.producer_id)
            .or_default()
            .push(line);
    }
    let producers = producers
        .into_iter()
        .map(|producer| {
            let mut lines = by_producer.remove(&producer.id).unwrap_or_default();
            lines.sort_by_key(|line| product_order(&line.product));
            (producer, lines)
        })
        .collect();
    Ok(Some(Invoice {
        order,
        producers,
        total,
    }))
}

/// The newest payment instructions
pub async fn payment_instruction(db: &PgPool) -> sqlx::Result<Option<String>> {
    sqlx::query_scalar("SELECT text FROM payment_instructions ORDER BY published_at DESC LIMIT 1")
        .fetch_optional(db)
        .await
}

/// A login to the admin
#[derive(Debug, FromRow)]
pub struct User {
    pub id: Uuid,
    pub password_hash: String,
    pub locked_at: Option<DateTime<Utc>>,
    pub failed_login_attempts: i32,
}

/// After this many wrong passwords in a row a login is locked, IHP's
/// default
pub const MAX_FAILED_LOGINS: i32 = 10;

impl User {
    /// Locked for an hour after the last of too many wrong passwords, as in
    /// IHP
    pub fn is_locked(&self, now: DateTime<Utc>) -> bool {
        self.locked_at
            .is_some_and(|locked_at| now - locked_at < chrono::TimeDelta::hours(1))
    }
}

/// The login with this email, whatever its case, as IHP finds it
pub async fn user_by_email(db: &PgPool, email: &str) -> sqlx::Result<Option<User>> {
    sqlx::query_as(
        "SELECT id, password_hash, locked_at, failed_login_attempts FROM users
         WHERE LOWER(email) = LOWER($1) LIMIT 1",
    )
    .bind(email)
    .fetch_optional(db)
    .await
}

pub async fn login_succeeded(db: &PgPool, user: Uuid) -> sqlx::Result<()> {
    sqlx::query("UPDATE users SET failed_login_attempts = 0 WHERE id = $1")
        .bind(user)
        .execute(db)
        .await
        .map(drop)
}

/// Counts a wrong password, and locks the login at the last one allowed
pub async fn login_failed(db: &PgPool, user: Uuid) -> sqlx::Result<()> {
    sqlx::query(
        "UPDATE users
         SET failed_login_attempts = failed_login_attempts + 1,
             locked_at = CASE WHEN failed_login_attempts + 1 >= $2 THEN NOW() ELSE locked_at END
         WHERE id = $1",
    )
    .bind(user)
    .bind(MAX_FAILED_LOGINS)
    .execute(db)
    .await
    .map(drop)
}

/// The roles a login has, see the IHP app's `Application/Permission.hs`
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Roles {
    pub admin: bool,
    pub deliverer: bool,
    pub promoter: bool,
}

/// The demo login's user with these roles, unlocked, made on its first use
/// with a password nobody knows (`ensureDemoUser`)
pub async fn ensure_demo_user(
    db: &PgPool,
    email: &str,
    roles: Roles,
    password_hash: impl FnOnce() -> String,
) -> sqlx::Result<Uuid> {
    let existing: Option<Uuid> = sqlx::query_scalar(
        "UPDATE users
         SET is_admin = $2, is_deliverer = $3, is_promoter = $4,
             locked_at = NULL, failed_login_attempts = 0
         WHERE id = (SELECT id FROM users WHERE email = $1 LIMIT 1)
         RETURNING id",
    )
    .bind(email)
    .bind(roles.admin)
    .bind(roles.deliverer)
    .bind(roles.promoter)
    .fetch_optional(db)
    .await?;
    if let Some(id) = existing {
        return Ok(id);
    }
    sqlx::query_scalar(
        "INSERT INTO users (email, password_hash, is_admin, is_deliverer, is_promoter)
         VALUES ($1, $2, $3, $4, $5) RETURNING id",
    )
    .bind(email)
    .bind(password_hash())
    .bind(roles.admin)
    .bind(roles.deliverer)
    .bind(roles.promoter)
    .fetch_one(db)
    .await
}

/// A logged-in user, for the admin's pages
#[derive(Debug, Clone)]
pub struct AdminUser {
    pub id: Uuid,
    pub email: String,
    pub roles: Roles,
}

/// The logged-in user, if their login still exists
pub async fn admin_user(db: &PgPool, id: Uuid) -> sqlx::Result<Option<AdminUser>> {
    let row: Option<(String, bool, bool, bool)> = sqlx::query_as(
        "SELECT email, is_admin, is_deliverer, is_promoter FROM users WHERE id = $1",
    )
    .bind(id)
    .fetch_optional(db)
    .await?;
    Ok(row.map(|(email, admin, deliverer, promoter)| AdminUser {
        id,
        email,
        roles: Roles {
            admin,
            deliverer,
            promoter,
        },
    }))
}

/// An order in the admin's list, with its customer's names and its price
#[derive(Debug, Clone, FromRow)]
pub struct ListedOrder {
    pub id: Uuid,
    pub ordered_at: DateTime<Utc>,
    pub invoiced_at: Option<DateTime<Utc>>,
    pub paid_at: Option<DateTime<Utc>>,
    pub delivered_at: Option<DateTime<Utc>>,
    pub first_name: String,
    pub last_name: String,
    pub reverse_name: String,
    pub billing_name: String,
    /// The sum of its lines, in cents
    pub price: i64,
}

/// Which orders the admin's list leaves out, besides the cancelled ones
#[derive(Debug, Default, Clone, Copy)]
pub struct Unhandled {
    pub invoiced: bool,
    pub paid: bool,
    pub delivered: bool,
}

/// The year's orders that weren't cancelled (the year in UTC), less those
/// handled in the ways `exclude` says, in no particular order
pub async fn orders_of_year(
    db: &PgPool,
    year: i32,
    exclude: Unhandled,
) -> sqlx::Result<Vec<ListedOrder>> {
    sqlx::query_as(
        "SELECT orders.id, ordered_at, invoiced_at, paid_at, delivered_at,
                first_name, last_name, reverse_name, billing_name,
                COALESCE((SELECT SUM(unit_price::int8 * quantity) FROM ordered_products
                          WHERE order_id = orders.id), 0)::int8 AS price
         FROM orders JOIN customers ON customers.id = orders.customer_id
         WHERE cancelled_at IS NULL
           AND ordered_at >= make_timestamptz($1, 1, 1, 0, 0, 0, 'UTC')
           AND ordered_at < make_timestamptz($1 + 1, 1, 1, 0, 0, 0, 'UTC')
           AND (NOT $2 OR invoiced_at IS NULL)
           AND (NOT $3 OR paid_at IS NULL)
           AND (NOT $4 OR delivered_at IS NULL)",
    )
    .bind(year)
    .bind(exclude.invoiced)
    .bind(exclude.paid)
    .bind(exclude.delivered)
    .fetch_all(db)
    .await
}

/// The years from the first order's to the last one's (in UTC), cancelled
/// ones included; this year's alone when there are none
pub async fn order_years(db: &PgPool) -> sqlx::Result<std::ops::RangeInclusive<i32>> {
    let (first, last): (Option<i32>, Option<i32>) = sqlx::query_as(
        "SELECT EXTRACT(YEAR FROM MIN(ordered_at) AT TIME ZONE 'UTC')::int4,
                EXTRACT(YEAR FROM MAX(ordered_at) AT TIME ZONE 'UTC')::int4
         FROM orders",
    )
    .fetch_one(db)
    .await?;
    let now = chrono::Datelike::year(&Utc::now());
    Ok(first.unwrap_or(now)..=last.unwrap_or(now))
}

/// A time the order's invoice was emailed, or is to be
#[derive(Debug, FromRow)]
pub struct EmailJob {
    /// IHP's job status, e.g. `job_status_succeeded`
    pub status: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub last_error: Option<String>,
}

/// Every time the order's invoice was emailed, or is to be, oldest first
pub async fn email_jobs(db: &PgPool, order_id: Uuid) -> sqlx::Result<Vec<EmailJob>> {
    sqlx::query_as(
        "SELECT status::text, created_at, updated_at, last_error FROM email_order_jobs
         WHERE order_id = $1 ORDER BY created_at",
    )
    .bind(order_id)
    .fetch_all(db)
    .await
}

/// A step of an order's handling, its time column
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Step {
    Invoiced,
    Paid,
    Delivered,
    Cancelled,
}

/// Marks the order's step done now, as the admin's buttons do. False if
/// there's no such order.
pub async fn mark(db: &PgPool, order_id: Uuid, step: Step) -> sqlx::Result<bool> {
    let sql = match step {
        Step::Invoiced => "UPDATE orders SET invoiced_at = NOW() WHERE id = $1",
        Step::Paid => "UPDATE orders SET paid_at = NOW() WHERE id = $1",
        Step::Delivered => "UPDATE orders SET delivered_at = NOW() WHERE id = $1",
        Step::Cancelled => "UPDATE orders SET cancelled_at = NOW() WHERE id = $1",
    };
    let done = sqlx::query(sql).bind(order_id).execute(db).await?;
    Ok(done.rows_affected() == 1)
}

/// The order's customer's email and whether it was cancelled, if there's
/// such an order
pub async fn order_email(db: &PgPool, order_id: Uuid) -> sqlx::Result<Option<(String, bool)>> {
    sqlx::query_as(
        "SELECT email, cancelled_at IS NOT NULL FROM orders
         JOIN customers ON customers.id = orders.customer_id WHERE orders.id = $1",
    )
    .bind(order_id)
    .fetch_optional(db)
    .await
}

/// Emails the invoice again: a job for the worker, as on ordering
pub async fn queue_invoice_email(db: &PgPool, order_id: Uuid) -> sqlx::Result<()> {
    sqlx::query("INSERT INTO email_order_jobs (order_id) VALUES ($1)")
        .bind(order_id)
        .execute(db)
        .await
        .map(drop)
}

/// Every producer and product, also those that can't be ordered now, in
/// display order: what the admin can take an order of
pub async fn whole_catalog(db: &PgPool) -> sqlx::Result<(Vec<Producer>, Vec<Product>)> {
    let mut producers: Vec<Producer> =
        sqlx::query_as("SELECT id, name, description FROM producers")
            .fetch_all(db)
            .await?;
    sort_producers(&mut producers);
    let mut products = all_products(db).await?;
    products.sort_by_key(product_order);
    Ok((producers, products))
}

/// A product's ordered quantities, per year, in orders that weren't
/// cancelled
#[derive(Debug)]
pub struct ProductYears {
    pub product: Product,
    pub by_year: HashMap<i32, i64>,
}

/// Every product ever ordered, in display order, with how many of it were
/// ordered each year (in UTC), and the producers of these in display order
pub async fn ordered_products(db: &PgPool) -> sqlx::Result<(Vec<Producer>, Vec<ProductYears>)> {
    #[derive(FromRow)]
    struct Row {
        #[sqlx(flatten)]
        product: Product,
        year: i32,
        quantity: i64,
    }
    let rows: Vec<Row> = sqlx::query_as(
        "SELECT products.id, producer_id, name, description, package, price, ordering,
                EXTRACT(YEAR FROM ordered_at AT TIME ZONE 'UTC')::int4 AS year,
                SUM(quantity)::int8 AS quantity
         FROM ordered_products
         JOIN orders ON orders.id = ordered_products.order_id
         JOIN products ON products.id = ordered_products.product_id
         WHERE cancelled_at IS NULL
         GROUP BY products.id, year",
    )
    .fetch_all(db)
    .await?;
    let mut products: Vec<ProductYears> = Vec::new();
    for row in rows {
        match products.iter_mut().find(|p| p.product.id == row.product.id) {
            Some(known) => {
                known.by_year.insert(row.year, row.quantity);
            }
            None => products.push(ProductYears {
                by_year: HashMap::from([(row.year, row.quantity)]),
                product: row.product,
            }),
        }
    }
    products.sort_by_key(|p| product_order(&p.product));
    let ids: Vec<Uuid> = products.iter().map(|p| p.product.producer_id).collect();
    let mut producers: Vec<Producer> =
        sqlx::query_as("SELECT id, name, description FROM producers WHERE id = ANY($1)")
            .bind(&ids)
            .fetch_all(db)
            .await?;
    sort_producers(&mut producers);
    Ok((producers, products))
}

/// The admin's two published texts: the welcome message, which also opens
/// and closes ordering, and the payment instructions
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TextKind {
    Welcome,
    Payment,
}

/// A welcome message or payment instructions
#[derive(Debug, Clone, FromRow)]
pub struct Published {
    pub id: Uuid,
    pub text: String,
    pub published_at: DateTime<Utc>,
    /// Ordering is open: welcome messages only
    pub is_ordering_enabled: Option<bool>,
}

/// All of them: welcome messages newest first, payment instructions
/// oldest first (IHP listed these in no particular order)
pub async fn all_published(db: &PgPool, kind: TextKind) -> sqlx::Result<Vec<Published>> {
    let sql = match kind {
        TextKind::Welcome => {
            "SELECT id, text, published_at, is_ordering_enabled FROM welcome_messages
             ORDER BY published_at DESC"
        }
        TextKind::Payment => {
            "SELECT id, text, published_at, NULL::bool AS is_ordering_enabled
             FROM payment_instructions ORDER BY published_at, id"
        }
    };
    sqlx::query_as(sql).fetch_all(db).await
}

pub async fn published(db: &PgPool, kind: TextKind, id: Uuid) -> sqlx::Result<Option<Published>> {
    let sql = match kind {
        TextKind::Welcome => {
            "SELECT id, text, published_at, is_ordering_enabled FROM welcome_messages WHERE id = $1"
        }
        TextKind::Payment => {
            "SELECT id, text, published_at, NULL::bool AS is_ordering_enabled
             FROM payment_instructions WHERE id = $1"
        }
    };
    sqlx::query_as(sql).bind(id).fetch_optional(db).await
}

/// Publishes a new one now
pub async fn create_published(
    db: &PgPool,
    kind: TextKind,
    text: &str,
    is_ordering_enabled: bool,
) -> sqlx::Result<Uuid> {
    match kind {
        TextKind::Welcome => sqlx::query_scalar(
            "INSERT INTO welcome_messages (text, is_ordering_enabled) VALUES ($1, $2) RETURNING id",
        )
        .bind(text)
        .bind(is_ordering_enabled)
        .fetch_one(db)
        .await,
        TextKind::Payment => {
            sqlx::query_scalar("INSERT INTO payment_instructions (text) VALUES ($1) RETURNING id")
                .bind(text)
                .fetch_one(db)
                .await
        }
    }
}

/// Changes one; its publishing time stays
pub async fn update_published(
    db: &PgPool,
    kind: TextKind,
    changed: &Published,
) -> sqlx::Result<()> {
    let query = match kind {
        TextKind::Welcome => sqlx::query(
            "UPDATE welcome_messages SET text = $2, is_ordering_enabled = $3 WHERE id = $1",
        )
        .bind(changed.id)
        .bind(&changed.text)
        .bind(changed.is_ordering_enabled.unwrap_or(false)),
        TextKind::Payment => sqlx::query("UPDATE payment_instructions SET text = $2 WHERE id = $1")
            .bind(changed.id)
            .bind(&changed.text),
    };
    query.execute(db).await.map(drop)
}

pub async fn delete_published(db: &PgPool, kind: TextKind, id: Uuid) -> sqlx::Result<()> {
    let sql = match kind {
        TextKind::Welcome => "DELETE FROM welcome_messages WHERE id = $1",
        TextKind::Payment => "DELETE FROM payment_instructions WHERE id = $1",
    };
    sqlx::query(sql).bind(id).execute(db).await.map(drop)
}

/// A customer as the admin sees and edits them
#[derive(Debug, FromRow)]
pub struct AdminCustomer {
    pub id: Uuid,
    #[sqlx(flatten)]
    pub customer: Customer,
    /// The name and address as written before they were split into their
    /// parts (migration 1794227624), to check the parts against
    pub name: String,
    pub address: String,
}

/// One customer per name, A to Z by the last name, each name's newest: a
/// customer who ordered every year is in once, as they wrote it last
pub async fn customers_by_name(db: &PgPool) -> sqlx::Result<Vec<AdminCustomer>> {
    sqlx::query_as(
        "SELECT DISTINCT ON (reverse_name) id, email, phone, first_name, last_name, street_address,
                postal_code, city, billing_name, name, address
         FROM customers ORDER BY reverse_name, created_at DESC, id",
    )
    .fetch_all(db)
    .await
}

pub async fn admin_customer(db: &PgPool, id: Uuid) -> sqlx::Result<Option<AdminCustomer>> {
    sqlx::query_as(
        "SELECT id, email, phone, first_name, last_name, street_address, postal_code, city,
                billing_name, name, address
         FROM customers WHERE id = $1",
    )
    .bind(id)
    .fetch_optional(db)
    .await
}

/// A customer the admin adds, e.g. for the newsletter
pub async fn create_customer(db: &PgPool, customer: &NewCustomer) -> sqlx::Result<Uuid> {
    insert_customer(db, customer).await
}

pub async fn update_customer(db: &PgPool, id: Uuid, customer: &NewCustomer) -> sqlx::Result<()> {
    sqlx::query(
        "UPDATE customers
         SET first_name = $2, last_name = $3, billing_name = $4, email = $5, phone = $6,
             street_address = $7, postal_code = $8, city = $9, reverse_name = $10
         WHERE id = $1",
    )
    .bind(id)
    .bind(&customer.first_name)
    .bind(&customer.last_name)
    .bind(&customer.billing_name)
    .bind(&customer.email)
    .bind(&customer.phone)
    .bind(&customer.street_address)
    .bind(&customer.postal_code)
    .bind(&customer.city)
    .bind(customer.reverse_name())
    .execute(db)
    .await
    .map(drop)
}

/// Deletes a customer without orders; false (and nothing deleted) if they
/// have any
pub async fn delete_customer(db: &PgPool, id: Uuid) -> sqlx::Result<bool> {
    let deleted = sqlx::query(
        "DELETE FROM customers WHERE id = $1
           AND NOT EXISTS (SELECT 1 FROM orders WHERE customer_id = $1)",
    )
    .bind(id)
    .execute(db)
    .await?;
    Ok(deleted.rows_affected() == 1)
}

/// The emails in lower case, each once, A to Z, as the IHP app made its
/// lists: lower-cased here, as PostgreSQL leaves ä and the like alone in a
/// database without a locale
fn email_list(emails: Vec<String>) -> Vec<String> {
    let mut emails: Vec<String> = emails.iter().map(|email| email.to_lowercase()).collect();
    emails.sort();
    emails.dedup();
    emails
}

/// The emails of the year's customers, who get to know when their order is
/// delivered: of the orders that weren't cancelled (the year in UTC)
pub async fn delivery_emails(db: &PgPool, year: i32) -> sqlx::Result<Vec<String>> {
    let emails = sqlx::query_scalar(
        "SELECT email FROM orders JOIN customers ON customers.id = orders.customer_id
         WHERE cancelled_at IS NULL
           AND ordered_at >= make_timestamptz($1, 1, 1, 0, 0, 0, 'UTC')
           AND ordered_at < make_timestamptz($1 + 1, 1, 1, 0, 0, 0, 'UTC')",
    )
    .bind(year)
    .fetch_all(db)
    .await?;
    Ok(email_list(emails))
}

/// Every customer's email, for the newsletter
pub async fn newsletter_emails(db: &PgPool) -> sqlx::Result<Vec<String>> {
    let emails = sqlx::query_scalar("SELECT email FROM customers")
        .fetch_all(db)
        .await?;
    Ok(email_list(emails))
}

/// A producer as the admin edits it
#[derive(Debug, Clone, FromRow)]
pub struct CatalogProducer {
    pub id: Uuid,
    pub name: String,
    pub subject: String,
    pub description: String,
    /// Shown on the order form
    pub enabled: bool,
}

/// Every producer, by name as the database sorts them
pub async fn catalog_producers(db: &PgPool) -> sqlx::Result<Vec<CatalogProducer>> {
    sqlx::query_as("SELECT id, name, subject, description, enabled FROM producers ORDER BY name")
        .fetch_all(db)
        .await
}

pub async fn catalog_producer(db: &PgPool, id: Uuid) -> sqlx::Result<Option<CatalogProducer>> {
    sqlx::query_as("SELECT id, name, subject, description, enabled FROM producers WHERE id = $1")
        .bind(id)
        .fetch_optional(db)
        .await
}

/// A change of a product's or producer's text, and who made it
#[derive(Debug, FromRow)]
pub struct TextChange {
    pub created_at: DateTime<Utc>,
    pub email: String,
    pub field_name: String,
    pub text_before: String,
    pub text_after: String,
}

/// What a text change is of
#[derive(Debug, Clone, Copy)]
pub enum Texts {
    Producer(Uuid),
    Product(Uuid),
}

/// The text changes of a producer or product, newest first
pub async fn text_changes(db: &PgPool, of: Texts) -> sqlx::Result<Vec<TextChange>> {
    let (sql, id) = match of {
        Texts::Producer(id) => (
            "SELECT text_changes.created_at, email, field_name, text_before, text_after
             FROM text_changes JOIN users ON users.id = text_changes.user_id
             WHERE producer_id = $1 ORDER BY text_changes.created_at DESC",
            id,
        ),
        Texts::Product(id) => (
            "SELECT text_changes.created_at, email, field_name, text_before, text_after
             FROM text_changes JOIN users ON users.id = text_changes.user_id
             WHERE product_id = $1 ORDER BY text_changes.created_at DESC",
            id,
        ),
    };
    sqlx::query_as(sql).bind(id).fetch_all(db).await
}

/// Records which of the texts changed, (field, before, after), by whom
async fn record_text_changes(
    tx: &mut sqlx::PgConnection,
    user: Uuid,
    of: Texts,
    texts: &[(&str, &str, &str)],
) -> sqlx::Result<()> {
    let (producer, product) = match of {
        Texts::Producer(id) => (Some(id), None),
        Texts::Product(id) => (None, Some(id)),
    };
    for (field, before, after) in texts {
        if before != after {
            sqlx::query(
                "INSERT INTO text_changes (user_id, producer_id, product_id, field_name,
                                           text_before, text_after)
                 VALUES ($1, $2, $3, $4, $5, $6)",
            )
            .bind(user)
            .bind(producer)
            .bind(product)
            .bind(field)
            .bind(before)
            .bind(after)
            .execute(&mut *tx)
            .await?;
        }
    }
    Ok(())
}

pub async fn create_producer(db: &PgPool, producer: &CatalogProducer) -> sqlx::Result<Uuid> {
    sqlx::query_scalar(
        "INSERT INTO producers (name, subject, description, enabled) VALUES ($1, $2, $3, $4)
         RETURNING id",
    )
    .bind(&producer.name)
    .bind(&producer.subject)
    .bind(&producer.description)
    .bind(producer.enabled)
    .fetch_one(db)
    .await
}

/// Saves the producer as edited, with the texts that changed in its
/// history, all or nothing
pub async fn update_producer(
    db: &PgPool,
    user: Uuid,
    before: &CatalogProducer,
    after: &CatalogProducer,
) -> sqlx::Result<()> {
    let mut tx = db.begin().await?;
    record_text_changes(
        &mut tx,
        user,
        Texts::Producer(before.id),
        &[
            ("name", &before.name, &after.name),
            ("subject", &before.subject, &after.subject),
            ("description", &before.description, &after.description),
        ],
    )
    .await?;
    sqlx::query(
        "UPDATE producers SET name = $2, subject = $3, description = $4, enabled = $5
         WHERE id = $1",
    )
    .bind(before.id)
    .bind(&after.name)
    .bind(&after.subject)
    .bind(&after.description)
    .bind(after.enabled)
    .execute(&mut *tx)
    .await?;
    tx.commit().await
}

/// Deletes a producer without products, and its text history; false (and
/// nothing deleted) if it has any
pub async fn delete_producer(db: &PgPool, id: Uuid) -> sqlx::Result<bool> {
    let deleted = sqlx::query(
        "DELETE FROM producers WHERE id = $1
           AND NOT EXISTS (SELECT 1 FROM products WHERE producer_id = $1)",
    )
    .bind(id)
    .execute(db)
    .await?;
    Ok(deleted.rows_affected() == 1)
}

/// A product as the admin edits it
#[derive(Debug, Clone, FromRow)]
pub struct CatalogProduct {
    #[sqlx(flatten)]
    pub product: Product,
    /// Shown on the order form
    pub enabled: bool,
}

/// Every product, in no particular order
pub async fn catalog_products(db: &PgPool) -> sqlx::Result<Vec<CatalogProduct>> {
    sqlx::query_as(
        "SELECT id, producer_id, name, description, package, price, ordering, enabled FROM products",
    )
    .fetch_all(db)
    .await
}

pub async fn catalog_product(db: &PgPool, id: Uuid) -> sqlx::Result<Option<CatalogProduct>> {
    sqlx::query_as(
        "SELECT id, producer_id, name, description, package, price, ordering, enabled
         FROM products WHERE id = $1",
    )
    .bind(id)
    .fetch_optional(db)
    .await
}

pub async fn create_product(db: &PgPool, product: &CatalogProduct) -> sqlx::Result<Uuid> {
    let p = &product.product;
    sqlx::query_scalar(
        "INSERT INTO products (producer_id, name, description, package, price, ordering, enabled)
         VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id",
    )
    .bind(p.producer_id)
    .bind(&p.name)
    .bind(&p.description)
    .bind(&p.package)
    .bind(p.price)
    .bind(p.ordering)
    .bind(product.enabled)
    .fetch_one(db)
    .await
}

/// Saves the product as edited, with the texts that changed in its
/// history, all or nothing
pub async fn update_product(
    db: &PgPool,
    user: Uuid,
    before: &CatalogProduct,
    after: &CatalogProduct,
) -> sqlx::Result<()> {
    let (b, a) = (&before.product, &after.product);
    let mut tx = db.begin().await?;
    record_text_changes(
        &mut tx,
        user,
        Texts::Product(b.id),
        &[
            ("name", &b.name, &a.name),
            ("description", &b.description, &a.description),
            ("package", &b.package, &a.package),
        ],
    )
    .await?;
    sqlx::query(
        "UPDATE products SET producer_id = $2, name = $3, description = $4, package = $5,
                             price = $6, ordering = $7, enabled = $8
         WHERE id = $1",
    )
    .bind(b.id)
    .bind(a.producer_id)
    .bind(&a.name)
    .bind(&a.description)
    .bind(&a.package)
    .bind(a.price)
    .bind(a.ordering)
    .bind(after.enabled)
    .execute(&mut *tx)
    .await?;
    tx.commit().await
}

/// Deletes a product never ordered, and its text history; false (and
/// nothing deleted) if it was
pub async fn delete_product(db: &PgPool, id: Uuid) -> sqlx::Result<bool> {
    let deleted = sqlx::query(
        "DELETE FROM products WHERE id = $1
           AND NOT EXISTS (SELECT 1 FROM ordered_products WHERE product_id = $1)",
    )
    .bind(id)
    .execute(db)
    .await?;
    Ok(deleted.rows_affected() == 1)
}

/// The login's password hash, IHP's (`password.rs`)
pub async fn password_hash(db: &PgPool, user: Uuid) -> sqlx::Result<Option<String>> {
    sqlx::query_scalar("SELECT password_hash FROM users WHERE id = $1")
        .bind(user)
        .fetch_optional(db)
        .await
}

pub async fn set_password_hash(db: &PgPool, user: Uuid, hash: &str) -> sqlx::Result<()> {
    sqlx::query("UPDATE users SET password_hash = $2 WHERE id = $1")
        .bind(user)
        .bind(hash)
        .execute(db)
        .await
        .map(drop)
}
