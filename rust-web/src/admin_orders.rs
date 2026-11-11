//! The admin's orders, the IHP app's `Admin/Controller/Orders.hs`:
//! - the list, `/admin/Orders` (`Admin/View/Orders/Index.hs`): a year's
//!   orders that weren't cancelled, searched by the customer's name,
//!   sorted, and less those already invoiced, paid or delivered if asked
//! - an order's page, `/admin/ShowOrder` (`Admin/View/Orders/Show.hs`): its
//!   invoice, the buttons for its next steps that the user's roles allow,
//!   and when its invoice was emailed
//! - the buttons' actions: mark it invoiced, paid or delivered, cancel it,
//!   and email the invoice again
//!
//! - a new order taken in the admin, `/admin/NewOrder`: the public order
//!   form, with every product, also those that can't be ordered now, and
//!   without an email to the customer
//! - all ordered products, `/admin/OrderedProducts`
//!   (`Admin/View/Orders/OrderedProducts.hs`): how many of each product
//!   were ordered each year

use std::sync::Arc;

use axum::extract::rejection::FormRejection;
use axum::extract::{Form, Query, State};
use axum::http::{HeaderMap, StatusCode, Uri};
use axum::response::{IntoResponse, Response};
use chrono::{DateTime, Utc};
use maud::{Markup, html};

use crate::admin::{self, Crumb};
use crate::db::{self, EmailJob, ListedOrder, Step, Unhandled};
use crate::permission::Permission;
use crate::session::{FLASH_ERROR, FLASH_SUCCESS};
use crate::views::{CustomerForm, OrderForm, customer_block, invoice_rows, money, order_form};
use crate::{AppState, Params, Result};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OrderBy {
    Name,
    OrderedAt,
    Price,
}

/// What the list shows, from the query string as IHP reads it: the first
/// of a repeated parameter; an empty one is as if it weren't there
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Filter {
    /// None: the last year with orders
    pub year: Option<i32>,
    pub q: String,
    pub order_by: OrderBy,
    pub descending: bool,
    pub exclude: (bool, bool, bool),
}

impl Filter {
    /// None when the year isn't a whole number
    pub fn parse(params: &[(String, String)]) -> Option<Self> {
        let get = |name: &str| {
            params
                .iter()
                .find(|(key, _)| key == name)
                .map(|(_, value)| value.as_str())
                .filter(|value| !value.is_empty())
        };
        // IHP's ParamReader Bool: "on", as checkboxes send it, or "true"
        let flag = |name| get(name).is_some_and(|v| v == "on" || v.eq_ignore_ascii_case("true"));
        let year = match get("year") {
            None => None,
            Some(text) if text.starts_with('+') => return None,
            Some(text) => Some(text.parse().ok()?),
        };
        Some(Self {
            year,
            q: get("q").unwrap_or_default().to_string(),
            order_by: match get("ordering") {
                Some("price") => OrderBy::Price,
                Some("ordered at") => OrderBy::OrderedAt,
                _ => OrderBy::Name,
            },
            descending: get("orderDir") == Some("descending"),
            exclude: (
                flag("excludeInvoiced"),
                flag("excludePaid"),
                flag("excludeDelivered"),
            ),
        })
    }
}

/// `matchesSearch`: the search, trimmed, anywhere in the text, whatever
/// the case; an empty search matches everything
fn matches(q: &str, text: &str) -> bool {
    let q = q.trim();
    q.is_empty() || text.to_lowercase().contains(&q.to_lowercase())
}

/// The orders the list shows, in its order. Searched and sorted here, as
/// in the IHP app: a year's orders are a few hundred at most. Descending is
/// ascending reversed, ties included, as there.
pub fn arrange(orders: Vec<ListedOrder>, filter: &Filter) -> Vec<ListedOrder> {
    let mut orders: Vec<ListedOrder> = orders
        .into_iter()
        .filter(|order| {
            [
                db::words(&[&order.first_name, &order.last_name]),
                order.reverse_name.clone(),
                order.billing_name.clone(),
            ]
            .iter()
            .any(|text| matches(&filter.q, text))
        })
        .collect();
    match filter.order_by {
        OrderBy::Name => orders.sort_by(|a, b| a.reverse_name.cmp(&b.reverse_name)),
        OrderBy::OrderedAt => orders.sort_by_key(|order| order.ordered_at),
        OrderBy::Price => orders.sort_by_key(|order| order.price),
    }
    if filter.descending {
        orders.reverse();
    }
    orders
}

/// IHP's `dateTime`: the time in UTC, which its scripts show in the
/// browser's time zone
pub fn date_time(at: DateTime<Utc>) -> Markup {
    time_element("date-time", at)
}

/// IHP's `timeAgo`, which its scripts show as e.g. "3 days ago"
pub fn time_ago(at: DateTime<Utc>) -> Markup {
    time_element("time-ago", at)
}

fn time_element(class: &str, at: DateTime<Utc>) -> Markup {
    let micros = at.timestamp_subsec_micros();
    let fraction = if micros == 0 {
        String::new()
    } else {
        format!(".{micros:06}").trim_end_matches('0').to_string()
    };
    let iso = format!("{}{fraction}Z", at.format("%Y-%m-%dT%H:%M:%S"));
    html! { time class=(class) datetime=(iso) { (at.format("%d.%m.%Y, %H:%M")) } }
}

fn selected(on: bool) -> Option<&'static str> {
    on.then_some("selected")
}

struct ListView<'a> {
    orders: &'a [ListedOrder],
    filter: &'a Filter,
    year: i32,
    years: std::ops::RangeInclusive<i32>,
    can_manage: bool,
    can_create: bool,
}

fn list_page(state: &AppState, view: &ListView) -> Markup {
    let filter = view.filter;
    let (invoiced, paid, delivered) = filter.exclude;
    let mut crumbs = vec![Crumb::link("Home", admin::WELCOME), Crumb::text("Orders")];
    if view.can_create {
        crumbs.push(Crumb::link("New", "/admin/NewOrder"));
    }
    let checkbox = |name: &str, on: bool, label: &str| {
        html! {
            label {
                input type="checkbox" name=(name) checked=[on.then_some("checked")] onchange="this.form.submit()";
                (label)
            }
        }
    };
    html! {
        (admin::breadcrumb(&crumbs))
        form method="GET" action="/admin/Orders" {
            label {
                "Year "
                select name="year" onchange="this.form.submit()" {
                    @for year in view.years.clone() {
                        option selected=[selected(year == view.year)] { (year) }
                    }
                }
            }
            label {
                "Sort by "
                select name="ordering" onchange="this.form.submit()" {
                    option selected=[selected(filter.order_by == OrderBy::Name)] { "customer" }
                    option selected=[selected(filter.order_by == OrderBy::OrderedAt)] { "ordered at" }
                    option selected=[selected(filter.order_by == OrderBy::Price)] { "price" }
                }
            }
            label {
                "Sort direction "
                select name="orderDir" onchange="this.form.submit()" {
                    option selected=[selected(!filter.descending)] { "ascending" }
                    option selected=[selected(filter.descending)] { "descending" }
                }
            }
            br;
            (checkbox("excludeInvoiced", invoiced, "Exclude invoiced orders"))
            br;
            (checkbox("excludePaid", paid, "Exclude paid orders"))
            br;
            (checkbox("excludeDelivered", delivered, "Exclude delivered orders"))
            input type="search" placeholder="Search" name="q" value=(filter.q);
        }
        p {
            (view.orders.len())
            @if view.orders.len() == 1 { " order" } @else { " orders" }
        }
        @if !view.orders.is_empty() {
            div.table-responsive {
                table.table {
                    thead {
                        tr {
                            th { "Ordered" } th { "Customer" } th { "Invoiced" }
                            th { "Price" } th { "Paid" } th { "Delivered" }
                        }
                    }
                    tbody {
                        @for order in view.orders {
                            tr {
                                td { a href={ "/admin/ShowOrder?orderId=" (order.id) } { (date_time(order.ordered_at)) } }
                                td { (db::words(&[&order.first_name, &order.last_name])) }
                                td { @if let Some(at) = order.invoiced_at { (date_time(at)) } }
                                td { (money(state.site.locale, order.price)) }
                                td {
                                    @if let Some(at) = order.paid_at {
                                        (date_time(at))
                                    } @else if view.can_manage {
                                        form method="POST" action={ "/admin/UpdateMarkPaidOrder?orderId=" (order.id) } {
                                            input type="submit" class="btn-small" value="Mark as paid";
                                        }
                                    }
                                }
                                td { @if let Some(at) = order.delivered_at { (date_time(at)) } }
                            }
                        }
                    }
                }
            }
        }
    }
}

pub async fn orders(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    uri: Uri,
    Query(params): Query<Vec<(String, String)>>,
) -> Result<Response> {
    let (user, session) =
        match admin::require_permission(&state, &headers, &uri, Permission::SeeOrders).await? {
            Ok(found) => found,
            Err(response) => return Ok(response),
        };
    let Some(filter) = Filter::parse(&params) else {
        return Ok(StatusCode::BAD_REQUEST.into_response());
    };
    let years = db::order_years(&state.db).await?;
    let year = filter.year.unwrap_or(*years.end());
    let exclude = Unhandled {
        invoiced: filter.exclude.0,
        paid: filter.exclude.1,
        delivered: filter.exclude.2,
    };
    let orders = arrange(db::orders_of_year(&state.db, year, exclude).await?, &filter);
    let content = list_page(
        &state,
        &ListView {
            orders: &orders,
            filter: &filter,
            year,
            years,
            can_manage: user.roles.can(Permission::ManageOrders),
            can_create: user.roles.can(Permission::CreateOrders),
        },
    );
    Ok(admin::page(&state, session, &content))
}

/// The order an address is about, `?orderId=…`, as IHP's router reads it:
/// None (a 400) when it's missing or not an id
fn order_id(params: &[(String, String)]) -> Option<uuid::Uuid> {
    let (_, id) = params.iter().find(|(key, _)| key == "orderId")?;
    uuid::Uuid::parse_str(id).ok()
}

fn bad_request() -> Response {
    StatusCode::BAD_REQUEST.into_response()
}

/// `renderEmailHistory`: when the invoice was emailed, and how it went
fn email_history(emails_enabled: bool, jobs: &[EmailJob]) -> Markup {
    if jobs.is_empty() {
        return html! { p #email-history { "The invoice hasn't been emailed." } };
    }
    html! {
        div #email-history {
            h2 { "Invoice emails" }
            @if !emails_enabled {
                p { "Emails are off for this instance, so none of these was actually sent." }
            }
            ul {
                @for job in jobs {
                    @let error = job.last_error.as_deref().unwrap_or_default();
                    @let (label, at, detail) = match job.status.as_str() {
                        "job_status_succeeded" => ("Emailed", job.updated_at, String::new()),
                        "job_status_failed" => ("Failed", job.updated_at, format!(": {error}")),
                        "job_status_timed_out" => ("Timed out", job.updated_at, String::new()),
                        "job_status_retry" => ("Failed", job.updated_at, format!(", trying again: {error}")),
                        "job_status_running" => ("Sending, queued", job.created_at, String::new()),
                        _ => ("Queued", job.created_at, String::new()),
                    };
                    li { (label) " " (date_time(at)) (detail) }
                }
            }
        }
    }
}

struct OrderView<'a> {
    id: uuid::Uuid,
    invoice: &'a db::Invoice,
    jobs: &'a [EmailJob],
    roles: db::Roles,
}

fn order_page(state: &AppState, view: &OrderView) -> Markup {
    let order = &view.invoice.order;
    let id = view.id;
    let manage = view.roles.can(Permission::ManageOrders);
    let button = |action: &str, label: &str| {
        html! {
            form method="POST" action={ "/admin/" (action) "?orderId=" (id) } {
                input type="submit" class="btn-small" value=(label);
            }
        }
    };
    html! {
        (admin::breadcrumb(&[
            Crumb::link("Home", admin::WELCOME),
            Crumb::link("Orders", "/admin/Orders"),
            Crumb::text(date_time(order.ordered_at)),
        ]))
        (customer_block(&order.customer))
        table {
            tbody { (invoice_rows(&state.site, view.invoice)) }
        }
        @if let Some(at) = order.cancelled_at {
            p { "Cancelled " (date_time(at)) }
        } @else {
            div.order-steps {
                @if manage { (button("UpdateSendInvoiceOrder", "Send invoice")) }
                @if manage && order.invoiced_at.is_none() { (button("UpdateInvoiceOrder", "Mark as invoiced")) }
                @if manage && order.paid_at.is_none() { (button("UpdateMarkPaidOrder", "Mark as paid")) }
                @if view.roles.can(Permission::MarkDelivered) && order.delivered_at.is_none() {
                    (button("UpdateDeliverOrder", "Mark as delivered"))
                }
                @if manage && order.paid_at.is_none() {
                    a href={ "/admin/DeleteCancelOrder?orderId=" (id) } class="js-delete btn-small danger" { "Cancel order" }
                }
            }
        }
        (email_history(state.emails_enabled, view.jobs))
    }
}

pub async fn show_order(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    uri: Uri,
    Query(params): Query<Vec<(String, String)>>,
) -> Result<Response> {
    let Some(id) = order_id(&params) else {
        return Ok(bad_request());
    };
    let (user, session) =
        match admin::require_permission(&state, &headers, &uri, Permission::SeeOrders).await? {
            Ok(found) => found,
            Err(response) => return Ok(response),
        };
    let Some(invoice) = db::invoice(&state.db, id).await? else {
        return Ok(crate::not_found(State(state), headers).await);
    };
    let jobs = db::email_jobs(&state.db, id).await?;
    let content = order_page(
        &state,
        &OrderView {
            id,
            invoice: &invoice,
            jobs: &jobs,
            roles: user.roles,
        },
    );
    Ok(admin::page(&state, session, &content))
}

fn show_path(id: uuid::Uuid) -> String {
    format!("/admin/ShowOrder?orderId={id}")
}

/// The path and query of the page the button was on, for going back to
/// it: the list as it was, with its year, filters and sorting. Only the
/// path, so it stays on this site.
fn referer_path(headers: &HeaderMap) -> Option<String> {
    let referer = headers.get(axum::http::header::REFERER)?.to_str().ok()?;
    let uri: Uri = referer.parse().ok()?;
    let path = uri.path_and_query()?.as_str();
    path.starts_with('/').then(|| path.to_string())
}

/// One of the buttons: the user may do it, the order is marked, and the
/// next page says so
async fn step(
    state: Arc<AppState>,
    headers: HeaderMap,
    uri: Uri,
    params: &[(String, String)],
    step: Step,
) -> Result<Response> {
    let Some(id) = order_id(params) else {
        return Ok(bad_request());
    };
    let permission = match step {
        Step::Delivered => Permission::MarkDelivered,
        _ => Permission::ManageOrders,
    };
    let (user, mut session) =
        match admin::require_permission(&state, &headers, &uri, permission).await? {
            Ok(found) => found,
            Err(response) => return Ok(response),
        };
    if !db::mark(&state.db, id, step).await? {
        return Ok(crate::not_found(State(state), headers).await);
    }
    tracing::info!(user = %user.id, order = %id, ?step, "marked the order");
    let (message, to) = match step {
        Step::Invoiced => ("Order invoiced", show_path(id)),
        // Back to the list as it was, or to the order's page
        Step::Paid => (
            "Order paid",
            referer_path(&headers).unwrap_or_else(|| "/admin/Orders".to_string()),
        ),
        Step::Delivered => ("Order delivered", show_path(id)),
        Step::Cancelled => ("Order cancelled", "/admin/Orders".to_string()),
    };
    session.set_text(FLASH_SUCCESS, message);
    Ok(admin::with_session(&state, &session, admin::found(&to)))
}

pub async fn mark_paid(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    uri: Uri,
    Query(params): Query<Vec<(String, String)>>,
) -> Result<Response> {
    step(state, headers, uri, &params, Step::Paid).await
}

pub async fn mark_invoiced(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    uri: Uri,
    Query(params): Query<Vec<(String, String)>>,
) -> Result<Response> {
    step(state, headers, uri, &params, Step::Invoiced).await
}

pub async fn mark_delivered(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    uri: Uri,
    Query(params): Query<Vec<(String, String)>>,
) -> Result<Response> {
    step(state, headers, uri, &params, Step::Delivered).await
}

/// Cancelling is a DELETE, which the order page's link sends as a POST
/// with `_method=DELETE`, as IHP's `js-delete` links do
pub async fn cancel(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    uri: Uri,
    Query(params): Query<Vec<(String, String)>>,
) -> Result<Response> {
    step(state, headers, uri, &params, Step::Cancelled).await
}

pub async fn cancel_by_post(
    state: State<Arc<AppState>>,
    headers: HeaderMap,
    uri: Uri,
    query: Query<Vec<(String, String)>>,
    form: std::result::Result<Form<Params>, FormRejection>,
) -> Result<Response> {
    if !admin::is_delete(form) {
        return Ok(StatusCode::METHOD_NOT_ALLOWED.into_response());
    }
    cancel(state, headers, uri, query).await
}

/// Emails the invoice to the customer again, e.g. after their email
/// address was corrected: a job for the worker, as on ordering
pub async fn send_invoice(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    uri: Uri,
    Query(params): Query<Vec<(String, String)>>,
) -> Result<Response> {
    let Some(id) = order_id(&params) else {
        return Ok(bad_request());
    };
    let (user, mut session) =
        match admin::require_permission(&state, &headers, &uri, Permission::ManageOrders).await? {
            Ok(found) => found,
            Err(response) => return Ok(response),
        };
    let Some((email, cancelled)) = db::order_email(&state.db, id).await? else {
        return Ok(crate::not_found(State(state), headers).await);
    };
    if cancelled {
        session.set_text(FLASH_ERROR, "A cancelled order's invoice can't be sent");
    } else {
        db::queue_invoice_email(&state.db, id).await?;
        tracing::info!(user = %user.id, order = %id, "queued the invoice to be emailed again");
        session.set_text(
            FLASH_SUCCESS,
            &format!("Invoice queued for sending to {email}"),
        );
    }
    Ok(admin::with_session(
        &state,
        &session,
        admin::found(&show_path(id)),
    ))
}

struct NewOrder<'a> {
    producers: &'a [db::Producer],
    products: &'a [db::Product],
    quantities: &'a std::collections::HashMap<uuid::Uuid, i64>,
    form: &'a CustomerForm,
    no_products_selected: bool,
}

/// The public order form in the admin's layout, sent to the admin
fn new_order_page(state: &AppState, order: &NewOrder) -> Markup {
    order_form(
        &state.site,
        &OrderForm {
            action: "/admin/CreateOrder",
            producers: order.producers,
            products: order.products,
            quantities: order.quantities,
            form: order.form,
            unavailable: &[],
            no_products_selected: order.no_products_selected,
        },
    )
}

pub async fn new_order(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    uri: Uri,
) -> Result<Response> {
    let (_, session) =
        match admin::require_permission(&state, &headers, &uri, Permission::CreateOrders).await? {
            Ok(found) => found,
            Err(response) => return Ok(response),
        };
    let (producers, products) = db::whole_catalog(&state.db).await?;
    let content = new_order_page(
        &state,
        &NewOrder {
            producers: &producers,
            products: &products,
            quantities: &Default::default(),
            form: &CustomerForm::default(),
            no_products_selected: false,
        },
    );
    Ok(admin::page(&state, session, &content))
}

/// Saves an order taken in the admin, e.g. on the phone: any product, even
/// one that can't be ordered now, and whether ordering is open or not. No
/// email: the customer didn't fill in the form themselves.
pub async fn create_order(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    uri: Uri,
    form: std::result::Result<Form<Params>, FormRejection>,
) -> Result<Response> {
    let (user, mut session) =
        match admin::require_permission(&state, &headers, &uri, Permission::CreateOrders).await? {
            Ok(found) => found,
            Err(response) => return Ok(response),
        };
    let params = form.map(|Form(params)| params).unwrap_or_default();
    let (producers, products) = db::whole_catalog(&state.db).await?;
    let Some(quantities) = crate::quantities(&params, &products) else {
        return Ok(bad_request());
    };
    let lines: Vec<_> = products
        .iter()
        .filter_map(|product| {
            let quantity = *quantities.get(&product.id)?;
            (quantity > 0).then_some((product, quantity))
        })
        .collect();
    let customer = crate::check(crate::customer_from(&params), crate::ORDER_CHECKS);
    if !customer.errors.is_empty() || lines.is_empty() {
        let shown = lines.iter().map(|(p, q)| (p.id, *q)).collect();
        let content = new_order_page(
            &state,
            &NewOrder {
                producers: &producers,
                products: &products,
                quantities: &shown,
                form: &customer,
                no_products_selected: lines.is_empty(),
            },
        );
        return Ok(admin::page(&state, session, &content));
    }
    let id = db::create_order(&state.db, &customer.customer, &lines, false).await?;
    tracing::info!(user = %user.id, order = %id, "took an order in the admin");
    session.set_text(FLASH_SUCCESS, "Order created");
    Ok(admin::with_session(
        &state,
        &session,
        admin::found(&show_path(id)),
    ))
}

/// How many of each product were ordered each year, newest first, under
/// their producers
fn ordered_products_page(
    years: &[i32],
    producers: &[db::Producer],
    products: &[db::ProductYears],
) -> Markup {
    html! {
        (admin::breadcrumb(&[
            Crumb::link("Home", admin::WELCOME),
            Crumb::text("All ordered products"),
        ]))
        div.table-responsive {
            table.whitespace-nowrap {
                thead {
                    tr {
                        th {}
                        @for year in years { th { (year) } }
                    }
                }
                tbody {
                    @for producer in producers {
                        tr { th colspan=(years.len() + 1) { (producer.name) } }
                        @for ordered in products.iter().filter(|p| p.product.producer_id == producer.id) {
                            tr {
                                td { (ordered.product.name) " (" (ordered.product.package) ")" }
                                @for year in years {
                                    td { (ordered.by_year.get(year).copied().unwrap_or(0)) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

pub async fn ordered_products(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    uri: Uri,
) -> Result<Response> {
    let (_, session) =
        match admin::require_permission(&state, &headers, &uri, Permission::SeeOrderedProducts)
            .await?
        {
            Ok(found) => found,
            Err(response) => return Ok(response),
        };
    let years: Vec<i32> = db::order_years(&state.db).await?.rev().collect();
    let (producers, products) = db::ordered_products(&state.db).await?;
    let content = ordered_products_page(&years, &producers, &products);
    Ok(admin::page(&state, session, &content))
}

#[cfg(test)]
mod tests {
    use super::*;
    use uuid::Uuid;

    fn params(query: &str) -> Vec<(String, String)> {
        query
            .split('&')
            .filter(|pair| !pair.is_empty())
            .map(|pair| {
                let (key, value) = pair.split_once('=').unwrap_or((pair, ""));
                (key.to_string(), value.to_string())
            })
            .collect()
    }

    #[test]
    fn reads_the_query_as_ihp() {
        let filter = Filter::parse(&params("")).unwrap();
        assert_eq!(
            filter,
            Filter {
                year: None,
                q: String::new(),
                order_by: OrderBy::Name,
                descending: false,
                exclude: (false, false, false),
            }
        );
        let filter = Filter::parse(&params(
            "year=2025&year=2026&ordering=price&orderDir=descending&excludePaid=on&excludeInvoiced=TRUE&excludeDelivered=yes&q=aalto",
        ))
        .unwrap();
        assert_eq!(filter.year, Some(2025));
        assert_eq!(filter.order_by, OrderBy::Price);
        assert!(filter.descending);
        assert_eq!(filter.exclude, (true, true, false));
        assert_eq!(filter.q, "aalto");
        assert_eq!(Filter::parse(&params("year=")).unwrap().year, None);
        assert_eq!(
            Filter::parse(&params("ordering=nonsense"))
                .unwrap()
                .order_by,
            OrderBy::Name
        );
        for bad in ["year=abc", "year=+2025", "year=2025.0"] {
            assert_eq!(Filter::parse(&params(bad)), None, "{bad}");
        }
    }

    fn order(first: &str, last: &str, billing: &str, price: i64, day: u32) -> ListedOrder {
        ListedOrder {
            id: Uuid::nil(),
            ordered_at: format!("2026-01-{day:02}T12:00:00Z").parse().unwrap(),
            invoiced_at: None,
            paid_at: None,
            delivered_at: None,
            first_name: first.into(),
            last_name: last.into(),
            reverse_name: db::words(&[last, first]).to_lowercase(),
            billing_name: billing.into(),
            price,
        }
    }

    fn names(orders: &[ListedOrder]) -> Vec<&str> {
        orders.iter().map(|o| o.first_name.as_str()).collect()
    }

    #[test]
    fn searches_and_sorts() {
        let all = || {
            vec![
                order("Äijä", "Öhman", "", 300, 3),
                order("Bertta", "Aalto", "Oliivi Oy", 100, 1),
                order("Eeva", "Aalto", "", 100, 2),
            ]
        };
        let filter = |query: &str| Filter::parse(&params(query)).unwrap();
        assert_eq!(
            names(&arrange(all(), &filter(""))),
            ["Bertta", "Eeva", "Äijä"]
        );
        assert_eq!(
            names(&arrange(all(), &filter("orderDir=descending"))),
            ["Äijä", "Eeva", "Bertta"]
        );
        // Ties keep their order, and descending reverses it
        assert_eq!(
            names(&arrange(all(), &filter("ordering=price"))),
            ["Bertta", "Eeva", "Äijä"]
        );
        assert_eq!(
            names(&arrange(
                all(),
                &filter("ordering=price&orderDir=descending")
            )),
            ["Äijä", "Eeva", "Bertta"]
        );
        assert_eq!(
            names(&arrange(all(), &filter("ordering=ordered at"))),
            ["Bertta", "Eeva", "Äijä"]
        );
        // The full name, the reversed name or the billing name, any case
        assert_eq!(names(&arrange(all(), &filter("q=  "))).len(), 3);
        assert_eq!(names(&arrange(all(), &filter("q= ÖHMAN "))), ["Äijä"]);
        assert_eq!(names(&arrange(all(), &filter("q=aalto eeva"))), ["Eeva"]);
        assert_eq!(names(&arrange(all(), &filter("q=eeva aalto"))), ["Eeva"]);
        assert_eq!(names(&arrange(all(), &filter("q=oliivi"))), ["Bertta"]);
    }

    #[test]
    fn reads_the_order_id_and_the_page_to_go_back_to() {
        let id = "d6af84db-3cf4-4445-8003-061c3bd99dc3";
        assert_eq!(
            order_id(&params(&format!("orderId={id}"))),
            Some(id.parse().unwrap())
        );
        assert_eq!(order_id(&params("orderId=xyz")), None);
        assert_eq!(order_id(&params("")), None);
        let referer = |value: &str| {
            let mut headers = HeaderMap::new();
            headers.insert(axum::http::header::REFERER, value.parse().unwrap());
            referer_path(&headers)
        };
        assert_eq!(
            referer("https://tilaus.example.fi/admin/Orders?year=2025&q=aalto").as_deref(),
            Some("/admin/Orders?year=2025&q=aalto")
        );
        // Another site's address goes to that path here
        assert_eq!(
            referer("https://evil.example/admin/Orders").as_deref(),
            Some("/admin/Orders")
        );
        assert_eq!(
            referer("/admin/ShowOrder?orderId=1").as_deref(),
            Some("/admin/ShowOrder?orderId=1")
        );
        assert_eq!(referer("nonsense"), None);
    }

    #[test]
    fn times_as_ihp_writes_them() {
        let at = |text: &str| date_time(text.parse().unwrap()).into_string();
        assert_eq!(
            at("2026-03-01T07:00:00Z"),
            r#"<time class="date-time" datetime="2026-03-01T07:00:00Z">01.03.2026, 07:00</time>"#
        );
        assert_eq!(
            at("2025-12-03T09:30:00.123456Z"),
            r#"<time class="date-time" datetime="2025-12-03T09:30:00.123456Z">03.12.2025, 09:30</time>"#
        );
        assert!(at("2025-03-04T10:11:12.5Z").contains(r#"datetime="2025-03-04T10:11:12.5Z""#));
    }
}
