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
    pub paid_at: Option<DateTime<Utc>>,
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
/// later price changes don't touch it) and the job that emails the invoice,
/// all or nothing. The IHP app's job worker sends the email.
pub async fn create_order(
    db: &PgPool,
    customer: &NewCustomer,
    lines: &[(&Product, i64)],
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
    sqlx::query("INSERT INTO email_order_jobs (order_id) VALUES ($1)")
        .bind(order_id)
        .execute(&mut *tx)
        .await?;
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
        "SELECT paid_at, cancelled_at, email, phone, first_name, last_name,
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
