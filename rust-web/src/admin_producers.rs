//! The admin's producers, the IHP app's `Admin/Controller/Producers.hs`:
//! the list, a producer's page with its text history, and the forms to add
//! one, edit one and delete one without products.
//!
//! Admins edit everything. Promoters, who translate, edit only the subject
//! and the description, and see the rest; not the name, a proper name, by
//! which the order form also lists Bosco Falconeria first. Every change of
//! a text is kept, who made it and from what (`text_changes`).

use std::sync::Arc;

use axum::extract::rejection::FormRejection;
use axum::extract::{Form, Query, State};
use axum::http::{HeaderMap, StatusCode, Uri};
use axum::response::{IntoResponse, Response};
use maud::{Markup, html};
use uuid::Uuid;

use crate::admin::{self, Crumb};
use crate::admin_forms::{Field, get, is_on, submit};
use crate::admin_orders::date_time;
use crate::db::{self, AdminUser, CatalogProducer, TextChange, Texts};
use crate::permission::Permission;
use crate::session::{FLASH_ERROR, FLASH_SUCCESS, Session};
use crate::views::markdown;
use crate::{AppState, Params, Result};

const LIST: &str = "/admin/Producers";

fn path(action: &str, id: Uuid) -> String {
    format!("/admin/{action}Producer?producerId={id}")
}

/// "✓" for what's shown on the order form
pub fn check_mark(on: bool) -> &'static str {
    if on { "✓" } else { "" }
}

/// "Shown on the order form", or not, for those who can't change it
pub fn shown(enabled: bool) -> &'static str {
    if enabled {
        "Shown on the order form"
    } else {
        "Not shown on the order form"
    }
}

/// A product's or producer's text history, newest first: a quiet line per
/// change, which opens to show the texts, as a description can be long
pub fn text_history(changes: &[TextChange]) -> Markup {
    if changes.is_empty() {
        return html! {
            p #text-history class="mt-8 text-sm text-gray-500" { "The texts haven't been changed here yet." }
        };
    }
    let or_empty = |text: &str| {
        if text.is_empty() {
            "(empty)".to_string()
        } else {
            text.to_string()
        }
    };
    html! {
        div #text-history class="mt-8 text-sm text-gray-600" {
            h2 class="text-base font-medium" { "Text changes" }
            @for change in changes {
                details class="my-1" {
                    summary class="cursor-pointer" {
                        (date_time(change.created_at)) " · " (change.email) " · " (change.field_name)
                    }
                    div class="ml-4 my-2 pl-3 border-l-2 border-gray-200 space-y-2" {
                        p class="whitespace-pre-line" { "Was: " (or_empty(&change.text_before)) }
                        p class="whitespace-pre-line" { "Now: " (or_empty(&change.text_after)) }
                    }
                }
            }
        }
    }
}

/// The id in the address; None is a 400
pub fn id_param(params: &[(String, String)], name: &str) -> Option<Uuid> {
    let (_, id) = params.iter().find(|(key, _)| key == name)?;
    Uuid::parse_str(id).ok()
}

/// The producer the address is about, for a user who may see it; or the
/// response
async fn find(
    state: &Arc<AppState>,
    headers: &HeaderMap,
    uri: &Uri,
    params: &[(String, String)],
    permission: Permission,
) -> Result<std::result::Result<(CatalogProducer, AdminUser, Session), Response>> {
    let Some(id) = id_param(params, "producerId") else {
        return Ok(Err(StatusCode::BAD_REQUEST.into_response()));
    };
    let (user, session) = match admin::require_permission(state, headers, uri, permission).await? {
        Ok(found) => found,
        Err(response) => return Ok(Err(response)),
    };
    match db::catalog_producer(&state.db, id).await? {
        Some(producer) => Ok(Ok((producer, user, session))),
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
    let producers = db::catalog_producers(&state.db).await?;
    let mut crumbs = vec![
        Crumb::link("Home", admin::WELCOME),
        Crumb::text("Producers"),
    ];
    if user.roles.can(Permission::ManageShop) {
        crumbs.push(Crumb::link("New", "/admin/NewProducer"));
    }
    let content = html! {
        (admin::breadcrumb(&crumbs))
        div.table-responsive {
            table.table {
                thead { tr { th { "Name" } th { "Enabled" } } }
                tbody {
                    @for producer in &producers {
                        tr {
                            td { a href=(path("Show", producer.id)) { (producer.name) } }
                            td { (check_mark(producer.enabled)) }
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
    let (producer, _, session) =
        match find(&state, &headers, &uri, &params, Permission::EditShopTexts).await? {
            Ok(found) => found,
            Err(response) => return Ok(response),
        };
    let changes = db::text_changes(&state.db, Texts::Producer(producer.id)).await?;
    let edit = path("Edit", producer.id);
    let content = html! {
        (admin::breadcrumb(&[
            Crumb::link("Home", admin::WELCOME),
            Crumb::link("Producers", LIST),
            Crumb::text(&producer.name),
            Crumb::link("Edit", &edit),
        ]))
        (markdown(&producer.description))
        (text_history(&changes))
    };
    Ok(admin::page(&state, session, &content))
}

/// An admin's form: everything
fn form(producer: &CatalogProducer, editing: bool) -> Markup {
    let action = if editing {
        path("Update", producer.id)
    } else {
        "/admin/CreateProducer".to_string()
    };
    let enabled = if producer.enabled { "on" } else { "off" };
    html! {
        form method="POST" action=(action) {
            (Field::new("producer", "name", "Name", &producer.name).required().autofocus().text())
            (Field::new("producer", "subject", "Subject", &producer.subject).text())
            (Field::new("producer", "description", "Description", &producer.description).textarea())
            (Field::new("producer", "enabled", "Shown on the order form", enabled).checkbox())
            (submit(if editing { "Save" } else { "Create producer" }))
        }
    }
}

/// A promoter's form: the texts they may change, the rest shown
fn text_form(producer: &CatalogProducer) -> Markup {
    html! {
        form method="POST" action=(path("Update", producer.id)) {
            p { "Name: " (producer.name) }
            p { (shown(producer.enabled)) }
            (Field::new("producer", "subject", "Subject", &producer.subject).autofocus().text())
            (Field::new("producer", "description", "Description", &producer.description).textarea())
            (submit("Save"))
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
    let blank = CatalogProducer {
        id: Uuid::nil(),
        name: String::new(),
        subject: String::new(),
        description: String::new(),
        enabled: true,
    };
    let content = html! {
        (admin::breadcrumb(&[
            Crumb::link("Home", admin::WELCOME),
            Crumb::link("Producers", LIST),
            Crumb::text("New"),
        ]))
        (form(&blank, false))
    };
    Ok(admin::page(&state, session, &content))
}

pub async fn edit(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    uri: Uri,
    Query(params): Query<Vec<(String, String)>>,
) -> Result<Response> {
    let (producer, user, session) =
        match find(&state, &headers, &uri, &params, Permission::EditShopTexts).await? {
            Ok(found) => found,
            Err(response) => return Ok(response),
        };
    let manage = user.roles.can(Permission::ManageShop);
    let show = path("Show", producer.id);
    let delete = path("Delete", producer.id);
    let mut crumbs = vec![
        Crumb::link("Home", admin::WELCOME),
        Crumb::link("Producers", LIST),
        Crumb::link(&producer.name, &show),
        Crumb::text("Edit"),
    ];
    if manage {
        crumbs.push(Crumb::text(
            html! { a href=(delete) class="js-delete back-button" { "Delete" } },
        ));
    }
    let content = html! {
        (admin::breadcrumb(&crumbs))
        @if manage { (form(&producer, true)) } @else { (text_form(&producer)) }
    };
    Ok(admin::page(&state, session, &content))
}

/// The form's fields over what the producer was, as IHP's `fill`; a
/// promoter's only over the texts they may change
fn filled(
    mut producer: CatalogProducer,
    fields: &[(String, String)],
    manage: bool,
) -> CatalogProducer {
    if manage && let Some(name) = get(fields, "name") {
        producer.name = name.to_string();
    }
    if let Some(subject) = get(fields, "subject") {
        producer.subject = subject.to_string();
    }
    if let Some(description) = get(fields, "description") {
        producer.description = description.to_string();
    }
    if manage && let Some(enabled) = get(fields, "enabled") {
        producer.enabled = is_on(enabled);
    }
    producer
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
    let blank = CatalogProducer {
        id: Uuid::nil(),
        name: String::new(),
        subject: String::new(),
        description: String::new(),
        enabled: true,
    };
    let producer = filled(blank, &fields, true);
    let id = db::create_producer(&state.db, &producer).await?;
    tracing::info!(producer = %id, "added a producer");
    session.set_text(FLASH_SUCCESS, "Producer created");
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
    let manage = user.roles.can(Permission::ManageShop);
    let after = filled(before.clone(), &fields, manage);
    db::update_producer(&state.db, user.id, &before, &after).await?;
    tracing::info!(producer = %before.id, user = %user.id, "changed a producer");
    session.set_text(FLASH_SUCCESS, "Producer updated");
    Ok(admin::with_session(
        &state,
        &session,
        admin::found(&path("Show", before.id)),
    ))
}

/// Deletes a producer, unless it has products: those go first, or the
/// producer is disabled instead
pub async fn delete(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    uri: Uri,
    Query(params): Query<Vec<(String, String)>>,
) -> Result<Response> {
    let (producer, _, mut session) =
        match find(&state, &headers, &uri, &params, Permission::ManageShop).await? {
            Ok(found) => found,
            Err(response) => return Ok(response),
        };
    if !db::delete_producer(&state.db, producer.id).await? {
        session.set_text(
            FLASH_ERROR,
            &format!(
                "Producer “{}” cannot be deleted because it has products. Delete its products first, or disable the producer instead.",
                producer.name
            ),
        );
        return Ok(admin::with_session(
            &state,
            &session,
            admin::found(&path("Edit", producer.id)),
        ));
    }
    tracing::info!(producer = %producer.id, "deleted a producer");
    session.set_text(FLASH_SUCCESS, "Producer deleted");
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
