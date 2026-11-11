//! The admin's two published texts, the IHP app's
//! `Admin/Controller/WelcomeMessages.hs` and `PaymentInstructions.hs`:
//! the welcome message on the front page, which also opens and closes
//! ordering, and the payment instructions on invoices. Each has a list, a
//! page, and IHP's generated forms to write a new one, edit one and delete
//! one. Admins only. The lists are on one page: IHP's split them into
//! pages of 50, which these never reach.
//!
//! On a demo, everyone is an admin, so a visitor can't put their own words
//! or bank account in front of others: only ordering can be opened and
//! closed, and the demo's invoices show fake payment details whatever is
//! stored.

use std::sync::Arc;

use axum::extract::rejection::FormRejection;
use axum::extract::{Form, State};
use axum::http::{HeaderMap, StatusCode, Uri};
use axum::response::{IntoResponse, Response};
use maud::{Markup, html};
use uuid::Uuid;

use crate::admin::{self, Crumb};
use crate::admin_orders::time_ago;
use crate::db::{self, Published, TextKind};
use crate::permission::Permission;
use crate::query;
use crate::session::{FLASH_ERROR, FLASH_SUCCESS, Session};
use crate::views::markdown;
use crate::{AppState, Result};

/// Their names in addresses, forms and messages, as IHP's generator made
/// them
struct Names {
    /// The list's title and link, "Welcome Messages"
    plural: &'static str,
    /// In addresses: "/admin/NewWelcomeMessage"
    model: &'static str,
    /// The id's parameter, "welcomeMessageId"
    id_param: &'static str,
    /// The form's ids, "welcomeMessage_text"
    form: &'static str,
    /// On the form's button, "Create Welcomemessage"
    button: &'static str,
    /// What a demo says to a change it refuses
    demo_refusal: &'static str,
}

fn names(kind: TextKind) -> Names {
    match kind {
        TextKind::Welcome => Names {
            plural: "Welcome Messages",
            model: "WelcomeMessage",
            id_param: "welcomeMessageId",
            form: "welcomeMessage",
            button: "Welcomemessage",
            demo_refusal: "The demo's welcome message is fixed: you can open and close ordering, but not change the text",
        },
        TextKind::Payment => Names {
            plural: "Payment Instructions",
            model: "PaymentInstruction",
            id_param: "paymentInstructionId",
            form: "paymentInstruction",
            button: "Paymentinstruction",
            demo_refusal: "The demo's payment details are fixed and can't be changed",
        },
    }
}

fn list_path(kind: TextKind) -> String {
    format!("/admin/{}s", names(kind).model)
}

fn action_path(kind: TextKind, action: &str, id: Uuid) -> String {
    let n = names(kind);
    format!("/admin/{action}{}?{}={id}", n.model, n.id_param)
}

/// What a demo refuses: anything but opening and closing ordering
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Change {
    New,
    Edit,
    Delete,
}

fn refused_on_demo(kind: TextKind, change: Change) -> bool {
    match kind {
        TextKind::Welcome => change != Change::Edit,
        TextKind::Payment => true,
    }
}

/// The demo's refusal: back to the list, saying why
fn refuse(state: &AppState, mut session: Session, kind: TextKind) -> Response {
    session.set_text(FLASH_ERROR, names(kind).demo_refusal);
    admin::with_session(state, &session, admin::found(&list_path(kind)))
}

/// The id in the address, as IHP's router reads it; None is a 400
fn id_of(kind: TextKind, uri: &Uri) -> Option<Uuid> {
    let items = query::items(uri.query());
    let (_, value) = items.iter().find(|(key, _)| key == names(kind).id_param)?;
    Uuid::parse_str(value.as_deref()?).ok()
}

fn bad_request() -> Response {
    StatusCode::BAD_REQUEST.into_response()
}

/// An admin, with the session; or the response for anyone else
async fn require_admin(
    state: &AppState,
    headers: &HeaderMap,
    uri: &Uri,
) -> Result<std::result::Result<Session, Response>> {
    Ok(
        admin::require_permission(state, headers, uri, Permission::ManageShop)
            .await?
            .map(|(_, session)| session),
    )
}

pub async fn index(
    kind: TextKind,
    state: Arc<AppState>,
    headers: HeaderMap,
    uri: Uri,
) -> Result<Response> {
    let session = match require_admin(&state, &headers, &uri).await? {
        Ok(session) => session,
        Err(response) => return Ok(response),
    };
    let rows = db::all_published(&state.db, kind).await?;
    let n = names(kind);
    let mut crumbs = vec![
        Crumb::link("Home", admin::WELCOME),
        Crumb::text(html! { span { (n.plural) } }),
    ];
    let new_path = format!("/admin/New{}", n.model);
    if !state.site.demo {
        crumbs.push(Crumb::link("New", &new_path));
    }
    let content = html! {
        (admin::breadcrumb(&crumbs))
        div.table-responsive {
            table.table {
                thead {
                    tr {
                        th { "Published" }
                        @if kind == TextKind::Welcome { th { "Is Ordering Enabled" } }
                    }
                }
                tbody {
                    @for row in &rows {
                        tr {
                            td { a href=(action_path(kind, "Show", row.id)) { (time_ago(row.published_at)) } }
                            @if let Some(open) = row.is_ordering_enabled {
                                td { @if open { "✓" } }
                            }
                        }
                    }
                }
            }
        }
    };
    Ok(admin::page(&state, session, &content))
}

/// IHP's `formFor` with a textarea for the text, and for a welcome
/// message a checkbox for opening ordering
fn form(state: &AppState, kind: TextKind, text: &Published, editing: bool) -> Markup {
    let n = names(kind);
    let action = if editing {
        action_path(kind, "Update", text.id)
    } else {
        format!("/admin/Create{}", n.model)
    };
    let field = format!("{}_text", n.form);
    // A demo's welcome text is fixed
    let fixed = state.site.demo && kind == TextKind::Welcome;
    html! {
        form method="POST" action=(action) id="" class=(if editing { "edit-form" } else { "new-form" }) data-disable-javascript-submission="false" {
            div class="flex flex-col my-6 space-y-2" id={ "form-group-" (field) } {
                label class="font-medium text-gray-700" for=(field) { "Text" }
                textarea name="text" placeholder="" id=(field) class="focus:ring-blue-500 focus:border-blue-500 block w-full border-gray-300 rounded-md" disabled=[fixed.then_some("disabled")] { (text.text) }
                @if fixed {
                    p class="text-gray-600 text-xs italic" { "The demo's welcome text is fixed. You can still open and close ordering." }
                }
            }
            @if let Some(open) = text.is_ordering_enabled {
                @let field = format!("{}_isOrderingEnabled", n.form);
                div class="flex flex-col my-6 space-y-2" id={ "form-group-" (field) } {
                    div.form-check {
                        div class="flex flex-row space-x-2" {
                            div {
                                input type="checkbox" name="isOrderingEnabled" class="form-check-input" id=(field) checked=[open.then_some("checked")];
                                input type="hidden" name="isOrderingEnabled" value="off";
                            }
                            div class="flex flex-col" {
                                label class="font-medium text-gray-700 form-check-label" for=(field) { "Is Ordering Enabled" }
                            }
                        }
                    }
                }
            }
            button class="bg-blue-500 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded" type="submit" {
                (if editing { "Save " } else { "Create " }) (n.button)
            }
        }
    }
}

pub async fn new(
    kind: TextKind,
    state: Arc<AppState>,
    headers: HeaderMap,
    uri: Uri,
) -> Result<Response> {
    let session = match require_admin(&state, &headers, &uri).await? {
        Ok(session) => session,
        Err(response) => return Ok(response),
    };
    if state.site.demo && refused_on_demo(kind, Change::New) {
        return Ok(refuse(&state, session, kind));
    }
    let blank = Published {
        id: Uuid::nil(),
        text: String::new(),
        published_at: chrono::Utc::now(),
        // A new welcome message opens ordering, unless unticked
        is_ordering_enabled: (kind == TextKind::Welcome).then_some(true),
    };
    let n = names(kind);
    let list = list_path(kind);
    let content = html! {
        (admin::breadcrumb(&[
            Crumb::link("Home", admin::WELCOME),
            Crumb::link(n.plural, &list),
            Crumb::text("New"),
        ]))
        (form(&state, kind, &blank, false))
    };
    Ok(admin::page(&state, session, &content))
}

/// The text the address is about: its id read, an admin's, and found
async fn find(
    kind: TextKind,
    state: &Arc<AppState>,
    headers: &HeaderMap,
    uri: &Uri,
    change: Option<Change>,
) -> Result<std::result::Result<(Published, Session), Response>> {
    let Some(id) = id_of(kind, uri) else {
        return Ok(Err(bad_request()));
    };
    let session = match require_admin(state, headers, uri).await? {
        Ok(session) => session,
        Err(response) => return Ok(Err(response)),
    };
    if let Some(change) = change
        && state.site.demo
        && refused_on_demo(kind, change)
    {
        return Ok(Err(refuse(state, session, kind)));
    }
    match db::published(&state.db, kind, id).await? {
        Some(text) => Ok(Ok((text, session))),
        None => Ok(Err(
            crate::not_found(State(state.clone()), headers.clone()).await
        )),
    }
}

pub async fn show(
    kind: TextKind,
    state: Arc<AppState>,
    headers: HeaderMap,
    uri: Uri,
) -> Result<Response> {
    let (text, session) = match find(kind, &state, &headers, &uri, None).await? {
        Ok(found) => found,
        Err(response) => return Ok(response),
    };
    let n = names(kind);
    let list = list_path(kind);
    let edit = action_path(kind, "Edit", text.id);
    let mut crumbs = vec![
        Crumb::link("Home", admin::WELCOME),
        Crumb::link(n.plural, &list),
        Crumb::text(time_ago(text.published_at)),
    ];
    if !(state.site.demo && refused_on_demo(kind, Change::Edit)) {
        crumbs.push(Crumb::link("Edit", &edit));
    }
    let content = html! {
        (admin::breadcrumb(&crumbs))
        (markdown(&text.text))
    };
    Ok(admin::page(&state, session, &content))
}

pub async fn edit(
    kind: TextKind,
    state: Arc<AppState>,
    headers: HeaderMap,
    uri: Uri,
) -> Result<Response> {
    let (text, session) = match find(kind, &state, &headers, &uri, Some(Change::Edit)).await? {
        Ok(found) => found,
        Err(response) => return Ok(response),
    };
    let content = edit_page(&state, kind, &text);
    Ok(admin::page(&state, session, &content))
}

fn edit_page(state: &AppState, kind: TextKind, text: &Published) -> Markup {
    let n = names(kind);
    let list = list_path(kind);
    let show = action_path(kind, "Show", text.id);
    let delete = action_path(kind, "Delete", text.id);
    let mut crumbs = vec![
        Crumb::link("Home", admin::WELCOME),
        Crumb::link(n.plural, &list),
        Crumb::markup_link(time_ago(text.published_at), &show),
        Crumb::text("Edit"),
    ];
    if !(state.site.demo && refused_on_demo(kind, Change::Delete)) {
        // A link in a link, as IHP's generated page has it; the inner one
        // is the js-delete link that asks and sends the DELETE
        crumbs.push(Crumb::markup_link(
            html! { a href=(delete) class="js-delete back-button" { "Delete" } },
            &delete,
        ));
    }
    html! {
        (admin::breadcrumb(&crumbs))
        (form(state, kind, text, true))
    }
}

/// The form's fields, as IHP's `fill`: the first of a repeated one (the
/// checkbox comes before its hidden "off"), the form's before the
/// address's; a field that isn't sent stays as it was
fn fill(kind: TextKind, demo: bool, text: &mut Published, form: &[(String, String)], uri: &Uri) {
    let query: Vec<(String, String)> = query::items(uri.query())
        .into_iter()
        .filter_map(|(key, value)| Some((key, value?)))
        .collect();
    let get = |name: &str| {
        form.iter()
            .chain(&query)
            .find(|(key, _)| key == name)
            .map(|(_, value)| value.as_str())
    };
    // On a demo only ordering opens and closes, see the module's comment
    if !demo && let Some(value) = get("text") {
        text.text = value.to_string();
    }
    if kind == TextKind::Welcome
        && let Some(value) = get("isOrderingEnabled")
    {
        text.is_ordering_enabled = Some(value == "on" || value.eq_ignore_ascii_case("true"));
    }
}

type FormResult = std::result::Result<Form<Vec<(String, String)>>, FormRejection>;

pub async fn create(
    kind: TextKind,
    state: Arc<AppState>,
    headers: HeaderMap,
    uri: Uri,
    form: FormResult,
) -> Result<Response> {
    let mut session = match require_admin(&state, &headers, &uri).await? {
        Ok(session) => session,
        Err(response) => return Ok(response),
    };
    if state.site.demo && refused_on_demo(kind, Change::New) {
        return Ok(refuse(&state, session, kind));
    }
    let fields = form.map(|Form(fields)| fields).unwrap_or_default();
    let mut text = Published {
        id: Uuid::nil(),
        text: String::new(),
        published_at: chrono::Utc::now(),
        is_ordering_enabled: (kind == TextKind::Welcome).then_some(false),
    };
    fill(kind, false, &mut text, &fields, &uri);
    let id = db::create_published(
        &state.db,
        kind,
        &text.text,
        text.is_ordering_enabled.unwrap_or(false),
    )
    .await?;
    tracing::info!(?kind, %id, "published");
    session.set_text(FLASH_SUCCESS, &format!("{} created", names(kind).model));
    Ok(admin::with_session(
        &state,
        &session,
        admin::found(&action_path(kind, "Show", id)),
    ))
}

pub async fn update(
    kind: TextKind,
    state: Arc<AppState>,
    headers: HeaderMap,
    uri: Uri,
    form: FormResult,
) -> Result<Response> {
    let (mut text, mut session) =
        match find(kind, &state, &headers, &uri, Some(Change::Edit)).await? {
            Ok(found) => found,
            Err(response) => return Ok(response),
        };
    let fields = form.map(|Form(fields)| fields).unwrap_or_default();
    fill(kind, state.site.demo, &mut text, &fields, &uri);
    db::update_published(&state.db, kind, &text).await?;
    tracing::info!(?kind, id = %text.id, "updated");
    session.set_text(FLASH_SUCCESS, &format!("{} updated", names(kind).model));
    Ok(admin::with_session(
        &state,
        &session,
        admin::found(&action_path(kind, "Show", text.id)),
    ))
}

pub async fn delete(
    kind: TextKind,
    state: Arc<AppState>,
    headers: HeaderMap,
    uri: Uri,
) -> Result<Response> {
    let (text, mut session) = match find(kind, &state, &headers, &uri, Some(Change::Delete)).await?
    {
        Ok(found) => found,
        Err(response) => return Ok(response),
    };
    db::delete_published(&state.db, kind, text.id).await?;
    tracing::info!(?kind, id = %text.id, "deleted");
    session.set_text(FLASH_SUCCESS, &format!("{} deleted", names(kind).model));
    Ok(admin::with_session(
        &state,
        &session,
        admin::found(&list_path(kind)),
    ))
}

/// The js-delete link's POST with `_method=DELETE`
pub async fn delete_by_post(
    kind: TextKind,
    state: Arc<AppState>,
    headers: HeaderMap,
    uri: Uri,
    form: std::result::Result<Form<crate::Params>, FormRejection>,
) -> Result<Response> {
    if !admin::is_delete(form) {
        return Ok(StatusCode::METHOD_NOT_ALLOWED.into_response());
    }
    delete(kind, state, headers, uri).await
}

/// The routes of both, at IHP's addresses, with the methods IHP's
/// AutoRoute takes for each
pub fn routes(mut router: axum::Router<Arc<AppState>>) -> axum::Router<Arc<AppState>> {
    use axum::routing::{MethodRouter, delete as delete_, get, post};
    type Page = fn(TextKind, Arc<AppState>, HeaderMap, Uri) -> futures_page::Page;
    for kind in [TextKind::Welcome, TextKind::Payment] {
        let model = names(kind).model;
        // A page any of GET, HEAD or POST shows
        let page = |f: Page| -> MethodRouter<Arc<AppState>> {
            let handler = move |State(state): State<Arc<AppState>>,
                                headers: HeaderMap,
                                uri: Uri| f(kind, state, headers, uri);
            get(handler).post(handler)
        };
        let change =
            move |State(state): State<Arc<AppState>>,
                  headers: HeaderMap,
                  uri: Uri,
                  form: FormResult| { update(kind, state, headers, uri, form) };
        router = router
            .route(&list_path(kind), page(|k, s, h, u| Box::pin(index(k, s, h, u))))
            .route(&format!("/admin/New{model}"), page(|k, s, h, u| Box::pin(new(k, s, h, u))))
            .route(&format!("/admin/Show{model}"), page(|k, s, h, u| Box::pin(show(k, s, h, u))))
            .route(&format!("/admin/Edit{model}"), page(|k, s, h, u| Box::pin(edit(k, s, h, u))))
            .route(
                &format!("/admin/Create{model}"),
                post(move |State(state): State<Arc<AppState>>, headers: HeaderMap, uri: Uri, form: FormResult| {
                    create(kind, state, headers, uri, form)
                }),
            )
            .route(&format!("/admin/Update{model}"), post(change).patch(change))
            .route(
                &format!("/admin/Delete{model}"),
                delete_(move |State(state): State<Arc<AppState>>, headers: HeaderMap, uri: Uri| delete(kind, state, headers, uri)).post(
                    move |State(state): State<Arc<AppState>>,
                          headers: HeaderMap,
                          uri: Uri,
                          form: std::result::Result<Form<crate::Params>, FormRejection>| {
                        delete_by_post(kind, state, headers, uri, form)
                    },
                ),
            );
    }
    router
}

mod futures_page {
    /// A page handler's future, boxed so the four pages share a type
    pub type Page = std::pin::Pin<
        Box<dyn std::future::Future<Output = crate::Result<axum::response::Response>> + Send>,
    >;
}
