//! The admin's customers, the IHP app's `Admin/Controller/Customers.hs`:
//! - the list, one per name, A to Z by the last name, each name's newest
//! - a customer's page, and the forms to add one, edit one and delete one
//!   that has no orders; admins only
//! - the email lists: the year's customers', to tell them when their order
//!   is delivered, and everyone's, for the newsletter
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
use crate::admin_orders::{Filter, year_select};
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
    };
    Ok(admin::page(&state, session, &content))
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
    let customer = filled(NewCustomer::default(), &fields);
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
        p { (emails.join(", ")) }
    };
    Ok(admin::page(&state, session, &content))
}
