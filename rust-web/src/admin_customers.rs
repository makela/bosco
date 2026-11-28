//! The admin's customers, the IHP app's `Admin/Controller/Customers.hs`:
//! - the list, one per name, A to Z by the last name, each name's newest
//! - a customer's page, and the forms to add one, edit one and delete one
//!   that has no orders; admins only
//! - the email lists: the year's customers', to tell them when their order
//!   is delivered, and those who get the newsletter's
//! - taking a customer's email off the newsletter, when they ask the admin,
//!   or putting them back on it
//! - everything the database has of a customer, for a request to see it
//!   (GDPR art. 15), as a page and a text file to send them
//! - erasing a customer who asks for it (`db::erase_customer`): their
//!   email and phone, and the rows without orders; what the invoices need
//!   stays for the accounts, until the nightly `bosco-anonymize`
//!
//! Unlike an order, the admin's form may leave the address empty: many
//! customers from before the address was split have only a street, or
//! nothing.

use std::sync::Arc;

use axum::extract::rejection::FormRejection;
use axum::extract::{Form, Query, State};
use axum::http::{HeaderMap, StatusCode, Uri};
use axum::response::{IntoResponse, Response};
use maud::{Markup, html};
use uuid::Uuid;

use crate::admin::{self, Crumb};
use crate::admin_orders::{Filter, date_time, year_select};
use crate::db::{self, AdminCustomer, NewCustomer};
use crate::permission::Permission;
use crate::session::{FLASH_ERROR, FLASH_SUCCESS, Session};
use crate::validate;
use crate::views::CustomerForm;
use crate::{AppState, Params, Result};

const LIST: &str = "/admin/Customers";

fn path(action: &str, id: Uuid) -> String {
    format!("/admin/{action}Customer?customerId={id}")
}

/// The admin's checks: the address may be empty, but a postal code given
/// must be one
const CHECKS: &[crate::FieldCheck] = &[
    ("firstName", validate::required),
    ("email", validate::email),
    ("phone", validate::phone),
    ("postalCode", |code| {
        if code.trim().is_empty() {
            Ok(())
        } else {
            validate::postal_code(code)
        }
    }),
];

/// The customer's id in the address; None is a 400
fn customer_id(params: &[(String, String)]) -> Option<Uuid> {
    let (_, id) = params.iter().find(|(key, _)| key == "customerId")?;
    Uuid::parse_str(id).ok()
}

async fn require(
    state: &AppState,
    headers: &HeaderMap,
    uri: &Uri,
    permission: Permission,
) -> Result<std::result::Result<Session, Response>> {
    Ok(admin::require_permission(state, headers, uri, permission)
        .await?
        .map(|(_, session)| session))
}

/// The customer the address is about, for an admin; or the response
async fn find(
    state: &Arc<AppState>,
    headers: &HeaderMap,
    uri: &Uri,
    params: &[(String, String)],
) -> Result<std::result::Result<(AdminCustomer, Session), Response>> {
    let Some(id) = customer_id(params) else {
        return Ok(Err(StatusCode::BAD_REQUEST.into_response()));
    };
    let session = match require(state, headers, uri, Permission::ManageShop).await? {
        Ok(session) => session,
        Err(response) => return Ok(Err(response)),
    };
    match db::admin_customer(&state.db, id).await? {
        Some(customer) => Ok(Ok((customer, session))),
        None => Ok(Err(
            crate::not_found(State(state.clone()), headers.clone()).await
        )),
    }
}

fn full_name(customer: &db::Customer) -> String {
    db::words(&[&customer.first_name, &customer.last_name])
}

pub async fn list(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    uri: Uri,
) -> Result<Response> {
    let session = match require(&state, &headers, &uri, Permission::ManageShop).await? {
        Ok(session) => session,
        Err(response) => return Ok(response),
    };
    let customers = db::customers_by_name(&state.db).await?;
    let content = html! {
        (admin::breadcrumb(&[
            Crumb::link("Home", admin::WELCOME),
            Crumb::text("Customers"),
            Crumb::link("New", "/admin/NewCustomer"),
        ]))
        div.table-responsive {
            table.table {
                thead { tr { th { "Name" } th { "Email" } th { "Phone" } } }
                tbody {
                    @for row in &customers {
                        tr {
                            td { a href=(path("Show", row.id)) { (full_name(&row.customer)) } }
                            td { (row.customer.email) }
                            td { (row.customer.phone) }
                        }
                    }
                }
            }
        }
    };
    Ok(admin::page(&state, session, &content))
}

pub async fn show(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    uri: Uri,
    Query(params): Query<Vec<(String, String)>>,
) -> Result<Response> {
    let (row, session) = match find(&state, &headers, &uri, &params).await? {
        Ok(found) => found,
        Err(response) => return Ok(response),
    };
    let customer = &row.customer;
    let edit = path("Edit", row.id);
    let content = html! {
        (admin::breadcrumb(&[
            Crumb::link("Home", admin::WELCOME),
            Crumb::link("Customers", LIST),
            Crumb::text(full_name(customer)),
            Crumb::link("Edit", &edit),
        ]))
        @if !customer.billing_name.is_empty() { p { (customer.billing_name) } }
        p { (customer.email) }
        p { (customer.phone) }
        @for line in customer.address_lines() { p { (line) } }
        (newsletter_status(&row))
        p class="my-4" {
            a href=(data_path(row.id, false)) { "Everything we have of them" }
        }
        p class="my-4" {
            a href=(path("Erase", row.id)) { "Erase their details, as they asked…" }
        }
    };
    Ok(admin::page(&state, session, &content))
}

/// What erasing the customer does, and the button to do it
pub async fn erase_form(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    uri: Uri,
    Query(params): Query<Vec<(String, String)>>,
) -> Result<Response> {
    let (row, session) = match find(&state, &headers, &uri, &params).await? {
        Ok(found) => found,
        Err(response) => return Ok(response),
    };
    let erasure = db::erasure(&state.db, row.id).await?;
    let customer = &row.customer;
    let show = path("Show", row.id);
    let content = html! {
        (admin::breadcrumb(&[
            Crumb::link("Home", admin::WELCOME),
            Crumb::link("Customers", LIST),
            Crumb::link(&full_name(customer), &show),
            Crumb::text("Erase"),
        ]))
        div class="max-w-prose" {
            p {
                "Erasing " (full_name(customer))
                @if !customer.email.is_empty() { " (" (customer.email) ")" }
                ", as they asked:"
            }
            ul class="list-disc ml-6 my-4" {
                @if erasure.deleted > 0 {
                    li { (erasure.deleted) " without orders: deleted" }
                }
                @if erasure.cleared > 0 {
                    li {
                        (erasure.cleared) " with orders: their email and phone are cleared and they leave the newsletter. "
                        "The names and address stay on the invoices for the accounts, 10 years from the end of the order's year, and are cleared after that."
                    }
                }
            }
            p { "This can't be undone." }
            form method="POST" action=(path("Erase", row.id)) {
                button class="bg-red-600 hover:bg-red-700 text-white py-1 px-3 rounded" type="submit" {
                    "Erase"
                }
            }
        }
    };
    Ok(admin::page(&state, session, &content))
}

/// Erases the customer and the other rows with their email
pub async fn erase(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    uri: Uri,
    Query(params): Query<Vec<(String, String)>>,
) -> Result<Response> {
    let (row, mut session) = match find(&state, &headers, &uri, &params).await? {
        Ok(found) => found,
        Err(response) => return Ok(response),
    };
    let erasure = db::erase_customer(&state.db, row.id).await?;
    tracing::info!(
        customer = %row.id,
        cleared = erasure.cleared,
        deleted = erasure.deleted,
        "erased a customer"
    );
    session.set_text(FLASH_SUCCESS, "Customer erased");
    Ok(admin::with_session(&state, &session, admin::found(LIST)))
}

/// Whether the customer gets the newsletter, since when or since when not,
/// and the button to change it
fn newsletter_status(row: &AdminCustomer) -> Markup {
    let action = |subscribe: bool| {
        format!(
            "{}&subscribe={}",
            path("UpdateNewsletter", row.id),
            u8::from(subscribe)
        )
    };
    html! {
        div #newsletter class="my-4" {
            @match (row.subscribed_at, row.unsubscribed_at) {
                (Some(since), _) => {
                    p { "Gets the newsletter since " (date_time(since)) }
                    form method="POST" action=(action(false)) {
                        button class="bg-gray-200 hover:bg-gray-300 py-1 px-3 rounded" type="submit" {
                            "Unsubscribe " (row.customer.email) " from the newsletter"
                        }
                    }
                }
                (None, left) => {
                    p {
                        "Doesn't get the newsletter"
                        @if let Some(left) = left { ": unsubscribed " (date_time(left)) }
                    }
                    form method="POST" action=(action(true)) {
                        button class="bg-gray-200 hover:bg-gray-300 py-1 px-3 rounded" type="submit" {
                            "Subscribe to the newsletter, as they asked"
                        }
                    }
                }
            }
        }
    }
}

/// Takes the customer's email off the newsletter, all its customers, or
/// puts this customer back on it
pub async fn update_newsletter(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    uri: Uri,
    Query(params): Query<Vec<(String, String)>>,
) -> Result<Response> {
    let (row, mut session) = match find(&state, &headers, &uri, &params).await? {
        Ok(found) => found,
        Err(response) => return Ok(response),
    };
    let subscribe = match params.iter().find(|(key, _)| key == "subscribe") {
        Some((_, value)) if value == "1" => true,
        Some((_, value)) if value == "0" => false,
        _ => return Ok(StatusCode::BAD_REQUEST.into_response()),
    };
    if subscribe {
        db::resubscribe(&state.db, row.id).await?;
        tracing::info!(customer = %row.id, "subscribed a customer to the newsletter");
        session.set_text(FLASH_SUCCESS, "Subscribed to the newsletter");
    } else {
        let count = db::unsubscribe(&state.db, &row.customer.email).await?;
        tracing::info!(customer = %row.id, count, "unsubscribed an email from the newsletter");
        session.set_text(FLASH_SUCCESS, "Unsubscribed from the newsletter");
    }
    Ok(admin::with_session(
        &state,
        &session,
        admin::found(&path("Show", row.id)),
    ))
}

/// The form's fields, with IHP's labels and what each needs
const FIELDS: [(&str, &str, bool); 8] = [
    ("firstName", "First name", true),
    ("lastName", "Last name", false),
    ("billingName", "Name on the invoice / Company name", false),
    ("email", "Email", true),
    ("phone", "Phone", true),
    ("streetAddress", "Street address", false),
    ("postalCode", "Postal code", false),
    ("city", "City", false),
];

/// The form to add or edit a customer, with what to fix under its fields
fn form(state: &AppState, form: &CustomerForm, editing: Option<Uuid>) -> Markup {
    let action = match editing {
        Some(id) => path("Update", id),
        None => "/admin/CreateCustomer".to_string(),
    };
    let c = &form.customer;
    html! {
        form method="POST" action=(action) class=(if editing.is_some() { "edit-form" } else { "new-form" }) {
            @for (name, label, required) in FIELDS {
                @let id = format!("customer_{name}");
                @let value = match name {
                    "firstName" => &c.first_name,
                    "lastName" => &c.last_name,
                    "billingName" => &c.billing_name,
                    "email" => &c.email,
                    "phone" => &c.phone,
                    "streetAddress" => &c.street_address,
                    "postalCode" => &c.postal_code,
                    _ => &c.city,
                };
                @let error = form.errors.get(name);
                div class="flex flex-col my-6 space-y-2" id={ "form-group-" (id) } {
                    label class="font-medium text-gray-700" for=(id) { (label) }
                    input type="text" name=(name) id=(id) value=(value) required[required]
                        autofocus[name == "firstName"]
                        class={ "focus:ring-blue-500 focus:border-blue-500 block w-full border-gray-300 rounded-md"
                                @if error.is_some() { " is-invalid" } };
                    @if let Some(error) = error {
                        div class="text-red-500 text-xs italic" { (error.text(state.site.locale)) }
                    }
                }
            }
            // Whether a customer gets the newsletter is changed on their page
            @if editing.is_none() {
                div.form-choice {
                    input type="checkbox" name="newsletter" id="customer_newsletter" value="on"
                        checked[c.newsletter];
                    label for="customer_newsletter" { "Gets the newsletter: they asked for it" }
                }
            }
            button class="bg-blue-500 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded" type="submit" {
                @if editing.is_some() { "Save" } @else { "Create customer" }
            }
        }
    }
}

fn new_page(state: &AppState, customer: &CustomerForm) -> Markup {
    html! {
        (admin::breadcrumb(&[
            Crumb::link("Home", admin::WELCOME),
            Crumb::link("Customers", LIST),
            Crumb::text("New"),
        ]))
        (form(state, customer, None))
    }
}

/// The edit page, with the name and address as the customer wrote them
/// before they were split into their parts, to check the parts against
fn edit_page(state: &AppState, row: &AdminCustomer, customer: &CustomerForm) -> Markup {
    let show = path("Show", row.id);
    let delete = path("Delete", row.id);
    let (name, address) = (row.name.trim(), row.address.trim());
    html! {
        (admin::breadcrumb(&[
            Crumb::link("Home", admin::WELCOME),
            Crumb::link("Customers", LIST),
            Crumb::link(&full_name(&row.customer), &show),
            Crumb::text("Edit"),
            Crumb::text(html! { a href=(delete) class="js-delete back-button" { "Delete" } }),
        ]))
        @if !name.is_empty() || !address.is_empty() {
            div #original-details class="my-4 p-3 border rounded bg-gray-50 text-gray-700" {
                p.font-medium { "As the customer wrote it before the name and address were split" }
                @if !name.is_empty() { p { "Name: " (name) } }
                @if !address.is_empty() { p.whitespace-pre-line { "Address: " (address) } }
            }
        }
        (form(state, customer, Some(row.id)))
    }
}

pub async fn new(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    uri: Uri,
) -> Result<Response> {
    let session = match require(&state, &headers, &uri, Permission::ManageShop).await? {
        Ok(session) => session,
        Err(response) => return Ok(response),
    };
    let content = new_page(&state, &CustomerForm::default());
    Ok(admin::page(&state, session, &content))
}

pub async fn edit(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    uri: Uri,
    Query(params): Query<Vec<(String, String)>>,
) -> Result<Response> {
    let (row, session) = match find(&state, &headers, &uri, &params).await? {
        Ok(found) => found,
        Err(response) => return Ok(response),
    };
    let customer = CustomerForm {
        customer: as_new(&row.customer),
        errors: Default::default(),
    };
    let content = edit_page(&state, &row, &customer);
    Ok(admin::page(&state, session, &content))
}

fn as_new(customer: &db::Customer) -> NewCustomer {
    NewCustomer {
        first_name: customer.first_name.clone(),
        last_name: customer.last_name.clone(),
        billing_name: customer.billing_name.clone(),
        email: customer.email.clone(),
        phone: customer.phone.clone(),
        street_address: customer.street_address.clone(),
        postal_code: customer.postal_code.clone(),
        city: customer.city.clone(),
        // Not on the edit form: see `newsletter_status`
        newsletter: false,
    }
}

/// The form's fields over what the customer was, as IHP's `fill`: a field
/// that isn't sent stays as it was. The names and address are then trimmed
/// and checked, as `buildCustomer` does.
fn filled(mut customer: NewCustomer, fields: &[(String, String)]) -> CustomerForm {
    let get = |name: &str| {
        fields
            .iter()
            .find(|(key, _)| key == name)
            .map(|(_, value)| value.clone())
    };
    for (name, value) in [
        ("firstName", &mut customer.first_name),
        ("lastName", &mut customer.last_name),
        ("billingName", &mut customer.billing_name),
        ("email", &mut customer.email),
        ("phone", &mut customer.phone),
        ("streetAddress", &mut customer.street_address),
        ("postalCode", &mut customer.postal_code),
        ("city", &mut customer.city),
    ] {
        if let Some(new) = get(name) {
            *value = new;
        }
    }
    let params: Params = [
        ("firstName", &customer.first_name),
        ("lastName", &customer.last_name),
        ("billingName", &customer.billing_name),
        ("email", &customer.email),
        ("phone", &customer.phone),
        ("streetAddress", &customer.street_address),
        ("postalCode", &customer.postal_code),
        ("city", &customer.city),
    ]
    .into_iter()
    .map(|(key, value)| (key.to_string(), value.clone()))
    .collect();
    crate::check(crate::customer_from(&params), CHECKS)
}

type Fields = std::result::Result<Form<Vec<(String, String)>>, FormRejection>;

pub async fn create(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    uri: Uri,
    form: Fields,
) -> Result<Response> {
    let mut session = match require(&state, &headers, &uri, Permission::ManageShop).await? {
        Ok(session) => session,
        Err(response) => return Ok(response),
    };
    let fields = form.map(|Form(fields)| fields).unwrap_or_default();
    let mut customer = filled(NewCustomer::default(), &fields);
    customer.customer.newsletter = fields.iter().any(|(key, _)| key == "newsletter");
    if !customer.errors.is_empty() {
        let content = new_page(&state, &customer);
        return Ok(admin::page(&state, session, &content));
    }
    let id = db::create_customer(&state.db, &customer.customer).await?;
    tracing::info!(customer = %id, "added a customer");
    session.set_text(FLASH_SUCCESS, "Customer created");
    Ok(admin::with_session(
        &state,
        &session,
        admin::found(&path("Show", id)),
    ))
}

pub async fn update(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    uri: Uri,
    Query(params): Query<Vec<(String, String)>>,
    form: Fields,
) -> Result<Response> {
    let (row, mut session) = match find(&state, &headers, &uri, &params).await? {
        Ok(found) => found,
        Err(response) => return Ok(response),
    };
    let fields = form.map(|Form(fields)| fields).unwrap_or_default();
    let customer = filled(as_new(&row.customer), &fields);
    if !customer.errors.is_empty() {
        let content = edit_page(&state, &row, &customer);
        return Ok(admin::page(&state, session, &content));
    }
    db::update_customer(&state.db, row.id, &customer.customer).await?;
    tracing::info!(customer = %row.id, "changed a customer");
    session.set_text(FLASH_SUCCESS, "Customer updated");
    Ok(admin::with_session(
        &state,
        &session,
        admin::found(&path("Show", row.id)),
    ))
}

/// Deletes a customer, unless they have orders: those stay, with their
/// customer
pub async fn delete(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    uri: Uri,
    Query(params): Query<Vec<(String, String)>>,
) -> Result<Response> {
    let (row, mut session) = match find(&state, &headers, &uri, &params).await? {
        Ok(found) => found,
        Err(response) => return Ok(response),
    };
    if !db::delete_customer(&state.db, row.id).await? {
        let name = full_name(&row.customer);
        session.set_text(
            FLASH_ERROR,
            &format!("Customer “{name}” cannot be deleted because they have orders."),
        );
        return Ok(admin::with_session(
            &state,
            &session,
            admin::found(&path("Edit", row.id)),
        ));
    }
    tracing::info!(customer = %row.id, "deleted a customer");
    session.set_text(FLASH_SUCCESS, "Customer deleted");
    Ok(admin::with_session(&state, &session, admin::found(LIST)))
}

/// The edit page's js-delete link's POST with `_method=DELETE`
pub async fn delete_by_post(
    state: State<Arc<AppState>>,
    headers: HeaderMap,
    uri: Uri,
    query: Query<Vec<(String, String)>>,
    form: std::result::Result<Form<Params>, FormRejection>,
) -> Result<Response> {
    if !admin::is_delete(form) {
        return Ok(StatusCode::METHOD_NOT_ALLOWED.into_response());
    }
    delete(state, headers, uri, query).await
}

/// The emails of the year's customers, comma-separated to paste into an
/// email's recipients: to tell them their order is on its way
pub async fn delivery_emails(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    uri: Uri,
    Query(params): Query<Vec<(String, String)>>,
) -> Result<Response> {
    let session = match require(&state, &headers, &uri, Permission::SeeEmailLists).await? {
        Ok(session) => session,
        Err(response) => return Ok(response),
    };
    let Some(filter) = Filter::parse(&params) else {
        return Ok(StatusCode::BAD_REQUEST.into_response());
    };
    let years = db::order_years(&state.db).await?;
    let year = filter.year.unwrap_or(*years.end());
    let emails = db::delivery_emails(&state.db, year).await?;
    let content = html! {
        (admin::breadcrumb(&[
            Crumb::link("Home", admin::WELCOME),
            Crumb::text("Emails for delivery info"),
        ]))
        form method="GET" action="/admin/EmailsForDeliveryInfo" {
            (year_select(years, year))
        }
        p { (emails.join(", ")) }
    };
    Ok(admin::page(&state, session, &content))
}

/// Every customer's email, comma-separated, for the newsletter
pub async fn newsletter_emails(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    uri: Uri,
) -> Result<Response> {
    let session = match require(&state, &headers, &uri, Permission::SeeEmailLists).await? {
        Ok(session) => session,
        Err(response) => return Ok(response),
    };
    let emails = db::newsletter_emails(&state.db).await?;
    let content = html! {
        (admin::breadcrumb(&[
            Crumb::link("Home", admin::WELCOME),
            Crumb::text("Emails for the newsletter"),
        ]))
        p { "Those who asked for the newsletter and haven't unsubscribed. Put this at the end of every newsletter:" }
        blockquote class="my-4 pl-4 border-l-4 text-gray-700" {
            (crate::l10n::Text::Unsubscribe.text(state.site.locale)) ": "
            (state.site.base_url.as_deref().unwrap_or("").trim_end_matches('/')) "/Unsubscribe"
        }
        p { (emails.join(", ")) }
    };
    Ok(admin::page(&state, session, &content))
}

fn data_path(id: Uuid, text: bool) -> String {
    let path = format!("/admin/CustomerData?customerId={id}");
    if text {
        format!("{path}&format=text")
    } else {
        path
    }
}

/// A time as the copy for the customer shows it, in UTC as stored
fn utc(at: chrono::DateTime<chrono::Utc>) -> String {
    at.format("%Y-%m-%d %H:%M UTC").to_string()
}

/// A section of what we have of them: a heading, and labelled values
type Section = (String, Vec<(&'static str, String)>);

/// What the database has of the person, in sections, the same for the
/// page and the text file: the copies of their details, their newsletter
/// status in each, and their orders with their lines and emails
fn data_sections(locale: crate::l10n::Locale, data: &db::PersonData) -> Vec<Section> {
    let optional =
        |at: Option<chrono::DateTime<chrono::Utc>>| at.map(utc).unwrap_or_else(|| "–".into());
    let mut sections = Vec::new();
    for (i, record) in data.records.iter().enumerate() {
        let c = &record.customer;
        let newsletter = match (record.subscribed_at, record.unsubscribed_at) {
            (Some(since), _) => format!("subscribed since {}", utc(since)),
            (None, Some(left)) => format!("unsubscribed {}", utc(left)),
            (None, None) => "not subscribed".into(),
        };
        let mut fields = vec![
            ("Saved", utc(record.created_at)),
            ("Last changed", utc(record.last_modified_at)),
            ("First name", c.first_name.clone()),
            ("Last name", c.last_name.clone()),
            ("Name on the invoice", c.billing_name.clone()),
            ("Email", c.email.clone()),
            ("Phone", c.phone.clone()),
            ("Street address", c.street_address.clone()),
            ("Postal code", c.postal_code.clone()),
            ("City", c.city.clone()),
        ];
        // As written before they were split, when it's still there
        if !record.name.is_empty() {
            fields.push(("Name, as first written", record.name.clone()));
        }
        if !record.address.is_empty() {
            fields.push(("Address, as first written", record.address.clone()));
        }
        fields.push(("Newsletter", newsletter));
        let orders = data
            .orders
            .iter()
            .filter(|order| order.customer_id == record.id)
            .count();
        fields.push(("Orders with these details", orders.to_string()));
        sections.push((
            format!("Details {} of {}", i + 1, data.records.len()),
            fields,
        ));
    }
    for order in &data.orders {
        let mut fields = vec![
            ("Ordered", utc(order.ordered_at)),
            ("Invoiced", optional(order.invoiced_at)),
            ("Paid", optional(order.paid_at)),
            ("Delivered", optional(order.delivered_at)),
            ("Cancelled", optional(order.cancelled_at)),
        ];
        for (name, package, quantity, price) in &order.lines {
            fields.push((
                "Product",
                format!(
                    "{quantity} × {name} ({package}), {} each",
                    crate::views::money(locale, i64::from(*price))
                ),
            ));
        }
        fields.push(("Total", crate::views::money(locale, order.total())));
        for email in &order.emails {
            let status = match email.status.as_str() {
                "job_status_succeeded" => "sent",
                "job_status_failed" | "job_status_retry" => "failed",
                "job_status_timed_out" => "timed out",
                _ => "waiting to be sent",
            };
            let error = email
                .last_error
                .as_deref()
                .map(|error| format!(": {error}"))
                .unwrap_or_default();
            fields.push((
                "Order email",
                format!("{status}, {}{error}", utc(email.updated_at)),
            ));
        }
        sections.push((format!("Order {}", order.id), fields));
    }
    sections
}

/// What the database doesn't have, for the answer to say
const ELSEWHERE: &str = "Not in the database, so not here: the server's technical logs, kept for at most 30 days, and the order emails as sent, in the sending mailbox.";

/// The sections as plain text, to attach to the answer
fn data_text(name: &str, sections: &[Section]) -> String {
    let mut text = format!("What we have of {name}, {}\n", utc(chrono::Utc::now()));
    for (heading, fields) in sections {
        text.push_str(&format!("\n{heading}\n"));
        for (label, value) in fields {
            text.push_str(&format!("  {label}: {value}\n"));
        }
    }
    text.push_str(&format!("\n{ELSEWHERE}\n"));
    text
}

/// Everything the database has of the customer and the others with their
/// email: the page, or with `format=text` a text file to send them
pub async fn data(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    uri: Uri,
    Query(params): Query<Vec<(String, String)>>,
) -> Result<Response> {
    let (row, session) = match find(&state, &headers, &uri, &params).await? {
        Ok(found) => found,
        Err(response) => return Ok(response),
    };
    let data = db::person_data(&state.db, row.id).await?;
    let sections = data_sections(state.site.locale, &data);
    let name = full_name(&row.customer);
    tracing::info!(customer = %row.id, "looked up everything of a customer");
    if params
        .iter()
        .any(|(key, value)| key == "format" && value == "text")
    {
        let file = format!(
            "attachment; filename=\"customer-data-{}.txt\"",
            chrono::Utc::now().format("%Y-%m-%d")
        );
        return Ok((
            [
                (
                    axum::http::header::CONTENT_TYPE,
                    "text/plain; charset=utf-8".to_string(),
                ),
                (axum::http::header::CONTENT_DISPOSITION, file),
            ],
            data_text(&name, &sections),
        )
            .into_response());
    }
    let show = path("Show", row.id);
    let content = html! {
        (admin::breadcrumb(&[
            Crumb::link("Home", admin::WELCOME),
            Crumb::link("Customers", LIST),
            Crumb::link(&name, &show),
            Crumb::text("Everything we have"),
        ]))
        p class="my-4" {
            "Every saved copy of the details with this email, and their orders. "
            a href=(data_path(row.id, true)) { "Download it as a text file" }
            " to send them."
        }
        @for (heading, fields) in &sections {
            h2 class="text-lg font-semibold mt-6 mb-2" { (heading) }
            table class="mb-4" {
                @for (label, value) in fields {
                    tr {
                        th class="text-left font-normal text-gray-600 pr-4 align-top" { (label) }
                        td { (value) }
                    }
                }
            }
        }
        p class="my-4 text-gray-600" { (ELSEWHERE) }
    };
    Ok(admin::page(&state, session, &content))
}
