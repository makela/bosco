//! The admin's products, the IHP app's `Admin/Controller/Products.hs`: the
//! whole catalog on one page in the order form's order, a product's page
//! with its text history, and the forms to add one, edit one and delete one
//! never ordered.
//!
//! Admins edit everything. Promoters, who translate, edit only the name,
//! the description and the package, never the price, the producer, the
//! place on the order form or whether it's shown. Every change of a text is
//! kept, who made it and from what.

use std::sync::Arc;

use axum::extract::rejection::FormRejection;
use axum::extract::{Form, Query, State};
use axum::http::{HeaderMap, StatusCode, Uri};
use axum::response::{IntoResponse, Response};
use maud::{Markup, html};
use uuid::Uuid;

use crate::admin::{self, Crumb};
use crate::admin_forms::{Field, get, is_on, submit};
use crate::admin_producers::{check_mark, id_param, shown, text_history};
use crate::db::{self, AdminUser, CatalogProduct, Producer, Product, Texts};
use crate::permission::Permission;
use crate::session::{FLASH_ERROR, FLASH_SUCCESS, Session};
use crate::views::money;
use crate::{AppState, Params, Result};

const LIST: &str = "/admin/Products";

fn path(action: &str, id: Uuid) -> String {
    format!("/admin/{action}Product?productId={id}")
}

/// Every producer, Bosco Falconeria first, then A to Z, as the order form
/// lists them
async fn producers(state: &AppState) -> Result<Vec<Producer>> {
    let mut producers: Vec<Producer> = db::catalog_producers(&state.db)
        .await?
        .into_iter()
        .map(|p| Producer {
            id: p.id,
            name: p.name,
            description: p.description,
        })
        .collect();
    db::sort_producers(&mut producers);
    Ok(producers)
}

fn producer_name(producers: &[Producer], id: Uuid) -> &str {
    producers
        .iter()
        .find(|p| p.id == id)
        .map_or("", |p| p.name.as_str())
}

/// The product the address is about, for a user who may see it; or the
/// response
async fn find(
    state: &Arc<AppState>,
    headers: &HeaderMap,
    uri: &Uri,
    params: &[(String, String)],
    permission: Permission,
) -> Result<std::result::Result<(CatalogProduct, AdminUser, Session), Response>> {
    let Some(id) = id_param(params, "productId") else {
        return Ok(Err(StatusCode::BAD_REQUEST.into_response()));
    };
    let (user, session) = match admin::require_permission(state, headers, uri, permission).await? {
        Ok(found) => found,
        Err(response) => return Ok(Err(response)),
    };
    match db::catalog_product(&state.db, id).await? {
        Some(product) => Ok(Ok((product, user, session))),
        None => Ok(Err(
            crate::not_found(State(state.clone()), headers.clone()).await
        )),
    }
}

pub async fn list(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    uri: Uri,
) -> Result<Response> {
    let (user, session) =
        match admin::require_permission(&state, &headers, &uri, Permission::EditShopTexts).await? {
            Ok(found) => found,
            Err(response) => return Ok(response),
        };
    let producers = producers(&state).await?;
    let mut products = db::catalog_products(&state.db).await?;
    // Grouped by producer in the order form's order
    let rank = |id: Uuid| producers.iter().position(|p| p.id == id);
    products.sort_by_key(|p| (rank(p.product.producer_id), db::product_order(&p.product)));
    let mut crumbs = vec![Crumb::link("Home", admin::WELCOME), Crumb::text("Products")];
    if user.roles.can(Permission::ManageShop) {
        crumbs.push(Crumb::link("New", "/admin/NewProduct"));
    }
    let content = html! {
        (admin::breadcrumb(&crumbs))
        div.table-responsive {
            table class="table whitespace-nowrap" {
                thead {
                    tr { th { "Producer" } th { "Name" } th { "Package" } th { "Price" } th { "Enabled" } }
                }
                tbody {
                    @for row in &products {
                        @let p = &row.product;
                        tr {
                            td { (producer_name(&producers, p.producer_id)) }
                            td { a href=(path("Show", p.id)) { (p.name) } }
                            td { (p.package) }
                            td { (money(state.site.locale, i64::from(p.price))) }
                            td { (check_mark(row.enabled)) }
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
    let (row, _, session) =
        match find(&state, &headers, &uri, &params, Permission::EditShopTexts).await? {
            Ok(found) => found,
            Err(response) => return Ok(response),
        };
    let p = &row.product;
    let producers = producers(&state).await?;
    let changes = db::text_changes(&state.db, Texts::Product(p.id)).await?;
    let edit = path("Edit", p.id);
    let content = html! {
        (admin::breadcrumb(&[
            Crumb::link("Home", admin::WELCOME),
            Crumb::link("Products", LIST),
            Crumb::text(&p.name),
            Crumb::link("Edit", &edit),
        ]))
        p.font-bold { (producer_name(&producers, p.producer_id)) }
        p { (p.description) }
        p { (money(state.site.locale, i64::from(p.price))) " / " (p.package) }
        (text_history(&changes))
    };
    Ok(admin::page(&state, session, &content))
}

/// The admin's form as filled in: the numbers and the producer as written,
/// to show again with what to fix
#[derive(Debug, Clone)]
struct ProductForm {
    producer_id: String,
    ordering: String,
    price: String,
    name: String,
    description: String,
    package: String,
    enabled: bool,
}

#[derive(Debug, Default)]
struct Errors {
    producer: Option<&'static str>,
    ordering: Option<&'static str>,
    price: Option<&'static str>,
}

impl ProductForm {
    fn of(row: &CatalogProduct) -> Self {
        let p = &row.product;
        Self {
            producer_id: p.producer_id.to_string(),
            ordering: p.ordering.map(|n| n.to_string()).unwrap_or_default(),
            price: p.price.to_string(),
            name: p.name.clone(),
            description: p.description.clone(),
            package: p.package.clone(),
            enabled: row.enabled,
        }
    }

    fn blank() -> Self {
        Self {
            producer_id: String::new(),
            ordering: String::new(),
            price: "0".to_string(),
            name: String::new(),
            description: String::new(),
            package: String::new(),
            enabled: true,
        }
    }

    /// The form's fields over what it was, as IHP's `fill`: a field that
    /// isn't sent stays as it was; a promoter's only the texts
    fn fill(mut self, fields: &[(String, String)], manage: bool) -> Self {
        let set = |name: &str, value: &mut String| {
            if let Some(new) = get(fields, name) {
                *value = new.to_string();
            }
        };
        set("name", &mut self.name);
        set("description", &mut self.description);
        set("package", &mut self.package);
        if manage {
            set("producerId", &mut self.producer_id);
            set("ordering", &mut self.ordering);
            set("price", &mut self.price);
            if let Some(enabled) = get(fields, "enabled") {
                self.enabled = is_on(enabled);
            }
        }
        self
    }

    /// The product, or what to fix: a producer that exists, and whole
    /// numbers for the price (in cents) and the place, which may be empty
    fn check(
        &self,
        id: Uuid,
        producers: &[Producer],
    ) -> std::result::Result<CatalogProduct, Errors> {
        let producer = Uuid::parse_str(self.producer_id.trim())
            .ok()
            .filter(|id| producers.iter().any(|p| p.id == *id));
        let ordering = match self.ordering.trim() {
            "" => Ok(None),
            text => text.parse::<i32>().map(Some),
        };
        let price = self.price.trim().parse::<i32>();
        match (producer, ordering, price) {
            (Some(producer_id), Ok(ordering), Ok(price)) => Ok(CatalogProduct {
                product: Product {
                    id,
                    producer_id,
                    name: self.name.clone(),
                    description: self.description.clone(),
                    package: self.package.clone(),
                    price,
                    ordering,
                },
                enabled: self.enabled,
            }),
            (producer, ordering, price) => Err(Errors {
                producer: producer.is_none().then_some("Choose a producer"),
                ordering: ordering.is_err().then_some("A whole number, or empty"),
                price: price
                    .is_err()
                    .then_some("A whole number of cents, e.g. 1250 for 12,50 €"),
            }),
        }
    }
}

/// An admin's form: everything
fn form(
    form: &ProductForm,
    errors: &Errors,
    producers: &[Producer],
    editing: Option<Uuid>,
) -> Markup {
    let action = match editing {
        Some(id) => path("Update", id),
        None => "/admin/CreateProduct".to_string(),
    };
    let options: Vec<(String, String)> = producers
        .iter()
        .map(|p| (p.id.to_string(), p.name.clone()))
        .collect();
    let enabled = if form.enabled { "on" } else { "off" };
    html! {
        form method="POST" action=(action) {
            (Field::new("product", "producerId", "Producer", &form.producer_id)
                .required().autofocus().error(errors.producer).select(&options))
            (Field::new("product", "ordering", "Place on the order form", &form.ordering)
                .error(errors.ordering)
                .help("The lowest first; those without one after them, A to Z")
                .number())
            (Field::new("product", "name", "Name", &form.name).required().text())
            (Field::new("product", "description", "Description", &form.description).textarea())
            (Field::new("product", "package", "Package", &form.package).required().text())
            (Field::new("product", "price", "Price", &form.price)
                .required().error(errors.price).help("In cents").text())
            (Field::new("product", "enabled", "Shown on the order form", enabled).checkbox())
            (submit(if editing.is_some() { "Save" } else { "Create product" }))
        }
    }
}

/// A promoter's form: the texts they may change, the rest shown
fn text_form(state: &AppState, row: &CatalogProduct, producers: &[Producer]) -> Markup {
    let p = &row.product;
    html! {
        form method="POST" action=(path("Update", p.id)) {
            p { "Producer: " (producer_name(producers, p.producer_id)) }
            p { "Price: " (money(state.site.locale, i64::from(p.price))) }
            p { (shown(row.enabled)) }
            (Field::new("product", "name", "Name", &p.name).required().autofocus().text())
            (Field::new("product", "description", "Description", &p.description).textarea())
            (Field::new("product", "package", "Package", &p.package).required().text())
            (submit("Save"))
        }
    }
}

fn new_page(product: &ProductForm, errors: &Errors, producers: &[Producer]) -> Markup {
    html! {
        (admin::breadcrumb(&[
            Crumb::link("Home", admin::WELCOME),
            Crumb::link("Products", LIST),
            Crumb::text("New"),
        ]))
        (form(product, errors, producers, None))
    }
}

fn edit_page(
    state: &AppState,
    row: &CatalogProduct,
    manage: bool,
    product: &ProductForm,
    errors: &Errors,
    producers: &[Producer],
) -> Markup {
    let p = &row.product;
    let show = path("Show", p.id);
    let delete = path("Delete", p.id);
    let mut crumbs = vec![
        Crumb::link("Home", admin::WELCOME),
        Crumb::link("Products", LIST),
        Crumb::link(&p.name, &show),
        Crumb::text("Edit"),
    ];
    if manage {
        crumbs.push(Crumb::text(
            html! { a href=(delete) class="js-delete back-button" { "Delete" } },
        ));
    }
    html! {
        (admin::breadcrumb(&crumbs))
        @if manage {
            (form(product, errors, producers, Some(p.id)))
        } @else {
            (text_form(state, row, producers))
        }
    }
}

pub async fn new(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    uri: Uri,
) -> Result<Response> {
    let (_, session) =
        match admin::require_permission(&state, &headers, &uri, Permission::ManageShop).await? {
            Ok(found) => found,
            Err(response) => return Ok(response),
        };
    let producers = producers(&state).await?;
    let content = new_page(&ProductForm::blank(), &Errors::default(), &producers);
    Ok(admin::page(&state, session, &content))
}

pub async fn edit(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    uri: Uri,
    Query(params): Query<Vec<(String, String)>>,
) -> Result<Response> {
    let (row, user, session) =
        match find(&state, &headers, &uri, &params, Permission::EditShopTexts).await? {
            Ok(found) => found,
            Err(response) => return Ok(response),
        };
    let producers = producers(&state).await?;
    let manage = user.roles.can(Permission::ManageShop);
    let content = edit_page(
        &state,
        &row,
        manage,
        &ProductForm::of(&row),
        &Errors::default(),
        &producers,
    );
    Ok(admin::page(&state, session, &content))
}

type Fields = std::result::Result<Form<Vec<(String, String)>>, FormRejection>;

pub async fn create(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    uri: Uri,
    form: Fields,
) -> Result<Response> {
    let (_, mut session) =
        match admin::require_permission(&state, &headers, &uri, Permission::ManageShop).await? {
            Ok(found) => found,
            Err(response) => return Ok(response),
        };
    let fields = form.map(|Form(fields)| fields).unwrap_or_default();
    let producers = producers(&state).await?;
    let filled = ProductForm::blank().fill(&fields, true);
    let product = match filled.check(Uuid::nil(), &producers) {
        Ok(product) => product,
        Err(errors) => {
            let content = new_page(&filled, &errors, &producers);
            return Ok(admin::page(&state, session, &content));
        }
    };
    let id = db::create_product(&state.db, &product).await?;
    tracing::info!(product = %id, "added a product");
    session.set_text(FLASH_SUCCESS, "Product created");
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
    let (before, user, mut session) =
        match find(&state, &headers, &uri, &params, Permission::EditShopTexts).await? {
            Ok(found) => found,
            Err(response) => return Ok(response),
        };
    let fields = form.map(|Form(fields)| fields).unwrap_or_default();
    let producers = producers(&state).await?;
    let manage = user.roles.can(Permission::ManageShop);
    let filled = ProductForm::of(&before).fill(&fields, manage);
    let after = match filled.check(before.product.id, &producers) {
        Ok(after) => after,
        Err(errors) => {
            let content = edit_page(&state, &before, manage, &filled, &errors, &producers);
            return Ok(admin::page(&state, session, &content));
        }
    };
    db::update_product(&state.db, user.id, &before, &after).await?;
    tracing::info!(product = %before.product.id, user = %user.id, "changed a product");
    session.set_text(FLASH_SUCCESS, "Product updated");
    Ok(admin::with_session(
        &state,
        &session,
        admin::found(&path("Show", before.product.id)),
    ))
}

/// Deletes a product, unless it was ordered: it's part of past orders, so
/// it can only be disabled
pub async fn delete(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    uri: Uri,
    Query(params): Query<Vec<(String, String)>>,
) -> Result<Response> {
    let (row, _, mut session) =
        match find(&state, &headers, &uri, &params, Permission::ManageShop).await? {
            Ok(found) => found,
            Err(response) => return Ok(response),
        };
    let p = &row.product;
    if !db::delete_product(&state.db, p.id).await? {
        session.set_text(
            FLASH_ERROR,
            &format!(
                "Product “{}” cannot be deleted because it has been ordered. Disable it instead.",
                p.name
            ),
        );
        return Ok(admin::with_session(
            &state,
            &session,
            admin::found(&path("Edit", p.id)),
        ));
    }
    tracing::info!(product = %p.id, "deleted a product");
    session.set_text(FLASH_SUCCESS, "Product deleted");
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
