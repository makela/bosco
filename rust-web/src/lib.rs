//! Bosco's public site: the IHP app's `Web/` (the welcome message, the order
//! form, the order's invoice and the newsletter form) in Rust, on the same
//! PostgreSQL database. The URLs are IHP's, so links in sent emails and
//! bookmarks keep working. Of the admin, the login and logout are here
//! (`admin.rs`), with IHP's session cookie; the rest is the IHP app's. The
//! email worker is `bosco-worker` (`worker.rs`), or the IHP app's.

pub mod admin;
pub mod admin_customers;
pub mod admin_forms;
pub mod admin_orders;
pub mod admin_password;
pub mod admin_producers;
pub mod admin_products;
pub mod admin_texts;
pub mod db;
pub mod demo_data;
pub mod l10n;
pub mod mail;
pub mod password;
pub mod permission;
pub mod query;
pub mod session;
pub mod settings;
pub mod skein_mac;
pub mod static_files;
pub mod validate;
pub mod views;
pub mod worker;

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;

use axum::Router;
use axum::extract::{Form, Query, State};
use axum::http::{HeaderMap, HeaderValue, StatusCode, header};
use axum::response::{IntoResponse, Redirect, Response};
use axum::routing::{delete, get, post};
use maud::Markup;
use sqlx::PgPool;
use tower_http::trace::TraceLayer;
use uuid::Uuid;

use crate::db::NewCustomer;
use crate::l10n::{Locale, Text};
use crate::views::{CustomerForm, HONEYPOT, OrderForm};

/// What's the same on every page of an instance
#[derive(Debug, Clone)]
pub struct Site {
    pub locale: Locale,
    /// A public demo (`APP_DEMO`): banners, "[Demo]" titles, not indexed,
    /// and invoices with a fake account
    pub demo: bool,
    /// The stylesheet's URL, e.g. the IHP app's dev build `/app.css`
    pub stylesheet: String,
    /// The IHP app's assets' version in production, for the admin's
    /// stylesheet and scripts (`/static/app.css?v=…`); none in development
    pub asset_version: Option<String>,
}

pub struct AppState {
    pub db: PgPool,
    pub site: Site,
    /// The IHP app's `static/`: the logo and the stylesheet
    pub static_dir: PathBuf,
    /// The key of IHP's session cookie, the IHP app's
    pub session_key: session::Key,
    /// Whether the session cookie is only sent over HTTPS, as IHP does when
    /// its base URL is https
    pub secure_cookies: bool,
    /// Whether the instance sends emails (`SEND_EMAILS`), which the admin's
    /// order pages tell
    pub emails_enabled: bool,
}

/// The notice the next page shows once, like IHP's flash messages. Kept in
/// a cookie by its name, so nothing a visitor writes ends up in it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Flash {
    OrderSent,
    DetailsSaved,
    OrderingNotOpen,
    OrderingClosed,
}

const FLASH_COOKIE: &str = "flash";

impl Flash {
    const ALL: [Self; 4] = [
        Self::OrderSent,
        Self::DetailsSaved,
        Self::OrderingNotOpen,
        Self::OrderingClosed,
    ];

    fn key(self) -> &'static str {
        match self {
            Self::OrderSent => "order-sent",
            Self::DetailsSaved => "details-saved",
            Self::OrderingNotOpen => "ordering-not-open",
            Self::OrderingClosed => "ordering-closed",
        }
    }

    pub fn text(self) -> Text {
        match self {
            Self::OrderSent => Text::OrderSent,
            Self::DetailsSaved => Text::DetailsSaved,
            Self::OrderingNotOpen => Text::OrderingNotOpen,
            Self::OrderingClosed => Text::OrderingClosed,
        }
    }

    pub fn is_error(self) -> bool {
        matches!(self, Self::OrderingNotOpen | Self::OrderingClosed)
    }

    fn from_headers(headers: &HeaderMap) -> Option<Self> {
        headers
            .get_all(header::COOKIE)
            .iter()
            .filter_map(|value| value.to_str().ok())
            .flat_map(|cookies| cookies.split(';'))
            .filter_map(|cookie| cookie.trim().strip_prefix("flash="))
            .find_map(|key| Self::ALL.into_iter().find(|flash| flash.key() == key))
    }
}

/// A database error: logged, and the visitor gets a plain 500
pub struct AppError(sqlx::Error);

impl From<sqlx::Error> for AppError {
    fn from(error: sqlx::Error) -> Self {
        Self(error)
    }
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        tracing::error!("database: {}", self.0);
        StatusCode::INTERNAL_SERVER_ERROR.into_response()
    }
}

type Result<T> = std::result::Result<T, AppError>;
pub(crate) type Params = HashMap<String, String>;
/// A form field's name and its check
type FieldCheck = (&'static str, fn(&str) -> validate::Check);

/// A page in the layout, with the notice the previous request left, which
/// it then clears
fn page(state: &AppState, headers: &HeaderMap, status: StatusCode, content: &Markup) -> Response {
    let flash = Flash::from_headers(headers);
    let mut response = (status, views::layout(&state.site, flash, content)).into_response();
    if flash.is_some() {
        response.headers_mut().append(
            header::SET_COOKIE,
            HeaderValue::from_static("flash=; Path=/; Max-Age=0; HttpOnly; SameSite=Lax"),
        );
    }
    response
}

/// Goes to `to`, which shows `flash` once
fn redirect_with(flash: Flash, to: &str) -> Response {
    let mut response = Redirect::to(to).into_response();
    let cookie = format!(
        "{FLASH_COOKIE}={}; Path=/; HttpOnly; SameSite=Lax",
        flash.key()
    );
    if let Ok(value) = HeaderValue::from_str(&cookie) {
        response.headers_mut().append(header::SET_COOKIE, value);
    }
    response
}

/// A bot filled in the field people don't see. It is answered as if the
/// form was sent, so that it doesn't simply try again otherwise, and
/// nothing is saved.
fn is_spam(params: &Params, path: &str) -> bool {
    let spam = params
        .get(HONEYPOT)
        .is_some_and(|value| !value.trim().is_empty());
    if spam {
        tracing::info!("Ignored a form filled in by a bot: {path}");
    }
    spam
}

fn param(params: &Params, name: &str) -> String {
    params.get(name).cloned().unwrap_or_default()
}

/// The customer's fields of a form, the name and address trimmed, as the
/// IHP app does; the email and phone as they were written
pub(crate) fn customer_from(params: &Params) -> NewCustomer {
    let trimmed = |name: &str| param(params, name).trim().to_string();
    NewCustomer {
        first_name: trimmed("firstName"),
        last_name: trimmed("lastName"),
        billing_name: trimmed("billingName"),
        email: param(params, "email"),
        phone: param(params, "phone"),
        street_address: trimmed("streetAddress"),
        postal_code: trimmed("postalCode"),
        city: trimmed("city"),
    }
}

/// The fields' checks, the first failing one of each field
pub(crate) fn check(customer: NewCustomer, checks: &[FieldCheck]) -> CustomerForm {
    let mut errors = HashMap::new();
    for (name, check) in checks {
        let value = match *name {
            "firstName" => &customer.first_name,
            "email" => &customer.email,
            "phone" => &customer.phone,
            "streetAddress" => &customer.street_address,
            "postalCode" => &customer.postal_code,
            _ => &customer.city,
        };
        if let Err(text) = check(value) {
            errors.entry(*name).or_insert(text);
        }
    }
    CustomerForm { customer, errors }
}

/// The quantities ordered: a product's is in the field named by its id.
/// Empty is 0, as in the IHP app; None (a 400) for anything else but a
/// whole number.
pub(crate) fn quantities(params: &Params, products: &[db::Product]) -> Option<HashMap<Uuid, i64>> {
    let mut quantities = HashMap::new();
    for product in products {
        match params.get(&product.id.to_string()).map(String::as_str) {
            None | Some("") => {}
            Some(value) => {
                quantities.insert(product.id, value.parse::<i64>().ok()?);
            }
        }
    }
    Some(quantities)
}

/// An order needs the whole address; the last name is optional, for the few
/// who have only one name
pub(crate) const ORDER_CHECKS: &[FieldCheck] = &[
    ("firstName", validate::required),
    ("email", validate::email),
    ("phone", validate::phone),
    ("streetAddress", validate::required),
    ("postalCode", validate::postal_code),
    ("city", validate::required),
];

const SUBSCRIBE_CHECKS: &[FieldCheck] = &[
    ("firstName", validate::required),
    ("email", validate::email),
];

async fn index(State(state): State<Arc<AppState>>, headers: HeaderMap) -> Result<Response> {
    let message = db::last_welcome_message(&state.db).await?;
    let content = views::index(&state.site, message.as_ref());
    Ok(page(&state, &headers, StatusCode::OK, &content))
}

async fn ordering_open(state: &AppState) -> Result<bool> {
    Ok(db::last_welcome_message(&state.db)
        .await?
        .is_some_and(|message| message.is_ordering_enabled))
}

async fn new_order(State(state): State<Arc<AppState>>, headers: HeaderMap) -> Result<Response> {
    // Old links to the order form keep working after ordering closes
    if !ordering_open(&state).await? {
        return Ok(redirect_with(Flash::OrderingNotOpen, "/"));
    }
    let (producers, products) = db::catalog(&state.db).await?;
    let content = views::order_form(
        &state.site,
        &OrderForm {
            action: "/CreateOrder",
            producers: &producers,
            products: &products,
            quantities: &HashMap::new(),
            form: &CustomerForm::default(),
            unavailable: &[],
            no_products_selected: false,
        },
    );
    Ok(page(&state, &headers, StatusCode::OK, &content))
}

/// Saves the order and shows its invoice. If any of the products ordered
/// can't be ordered any more (they were disabled while the customer filled
/// in the form), or none were ordered at all, nothing is saved and the form
/// says why.
async fn create_order(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Form(params): Form<Params>,
) -> Result<Response> {
    // A bot's order can't be shown like a person's, which has an invoice, so
    // it is thanked on the front page
    if is_spam(&params, "/CreateOrder") {
        return Ok(redirect_with(Flash::OrderSent, "/"));
    }
    // Ordering can close while the customer is still filling in the form
    if !ordering_open(&state).await? {
        return Ok(redirect_with(Flash::OrderingClosed, "/"));
    }
    let (producers, products) = db::catalog(&state.db).await?;
    let all_products = db::all_products(&state.db).await?;

    let Some(quantities) = quantities(&params, &all_products) else {
        return Ok(StatusCode::BAD_REQUEST.into_response());
    };
    let ordered = |id: &Uuid| quantities.get(id).is_some_and(|&q| q > 0);
    let lines: Vec<_> = products
        .iter()
        .filter(|p| ordered(&p.id))
        .map(|p| (p, quantities[&p.id]))
        .collect();
    let unavailable: Vec<_> = all_products
        .iter()
        .filter(|p| ordered(&p.id) && !products.iter().any(|o| o.id == p.id))
        .cloned()
        .collect();
    // Only one notice at a time: unavailable products explain an empty order
    let no_products_selected = lines.is_empty() && unavailable.is_empty();

    let form = check(customer_from(&params), ORDER_CHECKS);
    if !form.errors.is_empty() || !unavailable.is_empty() || no_products_selected {
        let shown: HashMap<Uuid, i64> = lines.iter().map(|(p, q)| (p.id, *q)).collect();
        let content = views::order_form(
            &state.site,
            &OrderForm {
                action: "/CreateOrder",
                producers: &producers,
                products: &products,
                quantities: &shown,
                form: &form,
                unavailable: &unavailable,
                no_products_selected,
            },
        );
        return Ok(page(&state, &headers, StatusCode::OK, &content));
    }
    let order_id = db::create_order(&state.db, &form.customer, &lines, true).await?;
    Ok(redirect_with(
        Flash::OrderSent,
        &format!("/ShowOrder?orderId={order_id}"),
    ))
}

async fn show_order(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Query(params): Query<Params>,
) -> Result<Response> {
    let order_id = params
        .get("orderId")
        .and_then(|id| Uuid::parse_str(id).ok());
    let invoice = match order_id {
        Some(id) => db::invoice(&state.db, id).await?,
        None => None,
    };
    let Some(invoice) = invoice else {
        return Ok(not_found(State(state), headers).await);
    };
    // A demo's invoices show only a fake account, whatever the database has
    let instruction = if state.site.demo {
        Some(views::DEMO_PAYMENT_DETAILS.to_string())
    } else {
        db::payment_instruction(&state.db).await?
    };
    let content = views::invoice(&state.site, &invoice, instruction.as_deref());
    Ok(page(&state, &headers, StatusCode::OK, &content))
}

async fn new_email(State(state): State<Arc<AppState>>, headers: HeaderMap) -> Response {
    let content = views::subscribe_form(&state.site, &CustomerForm::default());
    page(&state, &headers, StatusCode::OK, &content)
}

async fn create_email(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Form(params): Form<Params>,
) -> Result<Response> {
    if is_spam(&params, "/CreateEmail") {
        return Ok(redirect_with(Flash::DetailsSaved, "/"));
    }
    let params: Params = params
        .into_iter()
        .filter(|(name, _)| matches!(name.as_str(), "firstName" | "lastName" | "email"))
        .collect();
    let form = check(customer_from(&params), SUBSCRIBE_CHECKS);
    if !form.errors.is_empty() {
        let content = views::subscribe_form(&state.site, &form);
        return Ok(page(&state, &headers, StatusCode::OK, &content));
    }
    db::create_subscriber(&state.db, &form.customer).await?;
    Ok(redirect_with(Flash::DetailsSaved, "/"))
}

pub(crate) async fn not_found(State(state): State<Arc<AppState>>, headers: HeaderMap) -> Response {
    let content = views::not_found(&state.site);
    page(&state, &headers, StatusCode::NOT_FOUND, &content)
}

/// A static file (`static_files.rs`), or else not found
async fn static_or_not_found(
    State(state): State<Arc<AppState>>,
    uri: axum::http::Uri,
    headers: HeaderMap,
) -> Response {
    match static_files::serve(&state.static_dir, &uri, &headers).await {
        Some(file) => file,
        None => not_found(State(state), headers).await,
    }
}

/// All the site's routes. Other addresses are the IHP app's static files,
/// the logo, the stylesheets and the scripts, there and under /static/ as
/// IHP serves them, or else not found.
pub fn app(state: Arc<AppState>) -> Router {
    let router = Router::new()
        .route("/", get(index))
        .route("/Orders", get(index))
        .route("/NewOrder", get(new_order))
        .route("/CreateOrder", post(create_order))
        .route("/ShowOrder", get(show_order))
        .route("/NewEmail", get(new_email))
        .route("/CreateEmail", post(create_email))
        // The methods IHP's AutoRoute takes for each
        .route(
            admin::NEW_SESSION,
            get(admin::new_session).post(admin::new_session),
        )
        .route("/admin/", get(admin::welcome).post(admin::welcome))
        .route(admin::WELCOME, get(admin::welcome).post(admin::welcome))
        .route(
            "/admin/Orders",
            get(admin_orders::orders).post(admin_orders::orders),
        )
        .route(
            "/admin/Customers",
            get(admin_customers::list).post(admin_customers::list),
        )
        .route(
            "/admin/NewCustomer",
            get(admin_customers::new).post(admin_customers::new),
        )
        .route(
            "/admin/ShowCustomer",
            get(admin_customers::show).post(admin_customers::show),
        )
        .route(
            "/admin/EditCustomer",
            get(admin_customers::edit).post(admin_customers::edit),
        )
        .route("/admin/CreateCustomer", post(admin_customers::create))
        .route(
            "/admin/UpdateCustomer",
            post(admin_customers::update).patch(admin_customers::update),
        )
        .route(
            "/admin/DeleteCustomer",
            delete(admin_customers::delete).post(admin_customers::delete_by_post),
        )
        .route(
            "/admin/EmailsForDeliveryInfo",
            get(admin_customers::delivery_emails).post(admin_customers::delivery_emails),
        )
        .route(
            "/admin/EmailsForNewsLetter",
            get(admin_customers::newsletter_emails).post(admin_customers::newsletter_emails),
        )
        .route(
            "/admin/Producers",
            get(admin_producers::list).post(admin_producers::list),
        )
        .route(
            "/admin/NewProducer",
            get(admin_producers::new).post(admin_producers::new),
        )
        .route(
            "/admin/ShowProducer",
            get(admin_producers::show).post(admin_producers::show),
        )
        .route(
            "/admin/EditProducer",
            get(admin_producers::edit).post(admin_producers::edit),
        )
        .route("/admin/CreateProducer", post(admin_producers::create))
        .route(
            "/admin/UpdateProducer",
            post(admin_producers::update).patch(admin_producers::update),
        )
        .route(
            "/admin/DeleteProducer",
            delete(admin_producers::delete).post(admin_producers::delete_by_post),
        )
        .route(
            "/admin/Products",
            get(admin_products::list).post(admin_products::list),
        )
        .route(
            "/admin/NewProduct",
            get(admin_products::new).post(admin_products::new),
        )
        .route(
            "/admin/ShowProduct",
            get(admin_products::show).post(admin_products::show),
        )
        .route(
            "/admin/EditProduct",
            get(admin_products::edit).post(admin_products::edit),
        )
        .route("/admin/CreateProduct", post(admin_products::create))
        .route(
            "/admin/UpdateProduct",
            post(admin_products::update).patch(admin_products::update),
        )
        .route(
            "/admin/DeleteProduct",
            delete(admin_products::delete).post(admin_products::delete_by_post),
        )
        .route(
            "/admin/NewPassword",
            get(admin_password::new).post(admin_password::new),
        )
        .route(
            "/admin/UpdatePassword",
            post(admin_password::update).patch(admin_password::update),
        )
        .route(
            "/admin/NewOrder",
            get(admin_orders::new_order).post(admin_orders::new_order),
        )
        .route("/admin/CreateOrder", post(admin_orders::create_order))
        .route(
            "/admin/OrderedProducts",
            get(admin_orders::ordered_products).post(admin_orders::ordered_products),
        )
        .route(
            "/admin/ShowOrder",
            get(admin_orders::show_order).post(admin_orders::show_order),
        )
        .route(
            "/admin/UpdateMarkPaidOrder",
            post(admin_orders::mark_paid).patch(admin_orders::mark_paid),
        )
        .route(
            "/admin/UpdateInvoiceOrder",
            post(admin_orders::mark_invoiced).patch(admin_orders::mark_invoiced),
        )
        .route(
            "/admin/UpdateDeliverOrder",
            post(admin_orders::mark_delivered).patch(admin_orders::mark_delivered),
        )
        .route(
            "/admin/UpdateSendInvoiceOrder",
            post(admin_orders::send_invoice).patch(admin_orders::send_invoice),
        )
        .route(
            "/admin/DeleteCancelOrder",
            delete(admin_orders::cancel).post(admin_orders::cancel_by_post),
        )
        .route("/admin/CreateSession", post(admin::create_session))
        .route(
            "/admin/DeleteSession",
            delete(admin::delete_session).post(admin::delete_session_by_post),
        )
        .route(
            "/admin/DemoLogin",
            get(admin::demo_login).post(admin::demo_login),
        );
    admin_texts::routes(router)
        .fallback(static_or_not_found)
        .layer(TraceLayer::new_for_http())
        .with_state(state)
}
