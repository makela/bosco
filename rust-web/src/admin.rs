//! The admin's login and logout, the IHP app's `Admin/Controller/Sessions.hs`
//! with IHP's `IHP.AuthSupport.Controller.Sessions`, its welcome page,
//! `Admin/Controller/Static.hs`, and what the admin's pages share: the
//! layout, the breadcrumb and the login and permission checks. The rest of the admin is still the IHP
//! app's: they share IHP's session cookie (`session.rs`), so a login here
//! lets one into the IHP app's admin pages, and their flash messages show
//! here.
//!
//! As in IHP, a login is locked for an hour after 10 wrong passwords in a
//! row, and the login page is shown even to someone logged in.

use std::sync::Arc;

use axum::extract::{Form, Query, State};
use axum::http::{HeaderMap, StatusCode, Uri, header};
use axum::response::{IntoResponse, Response};
use maud::{DOCTYPE, Markup, html};

use crate::db::{self, AdminUser, Roles};
use crate::permission::Permission;
use crate::session::{FLASH_ERROR, FLASH_SUCCESS, REDIRECT_AFTER_LOGIN, Session};
use crate::{AppState, Params, Result, password};

pub const NEW_SESSION: &str = "/admin/NewSession";
/// The admin's start page, where a demo login goes
pub const WELCOME: &str = "/admin/Welcome";
/// IHP's `afterLoginRedirectPath`: where a login goes when it wasn't sent
/// to the login page from an admin page
const AFTER_LOGIN: &str = "/";

/// A demo's logins, one per role, that anyone can use from its login page
/// (the IHP app's `Application/Demo.hs`)
pub struct DemoLogin {
    pub role: &'static str,
    pub label: &'static str,
    pub email: &'static str,
    pub roles: Roles,
}

pub const DEMO_LOGINS: [DemoLogin; 3] = [
    DemoLogin {
        role: "admin",
        label: "Admin",
        email: "admin@demo.invalid",
        roles: Roles {
            admin: true,
            deliverer: false,
            promoter: false,
        },
    },
    DemoLogin {
        role: "orders",
        label: "Delivery person",
        email: "orders@demo.invalid",
        roles: Roles {
            admin: false,
            deliverer: true,
            promoter: false,
        },
    },
    DemoLogin {
        role: "promoter",
        label: "Promoter",
        email: "promoter@demo.invalid",
        roles: Roles {
            admin: false,
            deliverer: false,
            promoter: true,
        },
    },
];

/// A response with the session's changes saved
pub(crate) fn with_session(
    state: &AppState,
    session: &Session,
    response: impl IntoResponse,
) -> Response {
    let mut response = response.into_response();
    session.set_cookie(
        &state.session_key,
        state.secure_cookies,
        response.headers_mut(),
    );
    response
}

/// IHP's `redirectTo`, a 302
fn found(to: &str) -> impl IntoResponse + use<> {
    (StatusCode::FOUND, [(header::LOCATION, to.to_string())])
}

/// IHP's `redirectToPathSeeOther`, a 303
fn see_other(to: &str) -> impl IntoResponse + use<> {
    (StatusCode::SEE_OTHER, [(header::LOCATION, to.to_string())])
}

/// The admin's layout (`Admin/View/Layout.hs`) with the flash messages the
/// session has, which it then clears
pub(crate) fn page(state: &AppState, mut session: Session, content: &Markup) -> Response {
    let success = session.take_text(FLASH_SUCCESS);
    let error = session.take_text(FLASH_ERROR);
    let site = &state.site;
    let title = if site.demo {
        "[Demo] Manage Bosco Falconeria"
    } else {
        "Manage Bosco Falconeria"
    };
    let asset = |path: &str| match &site.asset_version {
        Some(version) => format!("{path}?v={version}"),
        None => path.to_string(),
    };
    let markup = html! {
        (DOCTYPE)
        html lang="fi" {
            head {
                meta charset="utf-8";
                meta name="viewport" content="width=device-width";
                @if site.demo {
                    meta name="robots" content="noindex, nofollow";
                }
                link rel="stylesheet" href=(asset("/static/app.css"));
                // The IHP app's scripts, in production
                @if site.asset_version.is_some() {
                    script src=(asset("/static/prod.js")) {}
                }
                title { (title) }
            }
            body {
                @if site.demo {
                    div.demo-banner role="note" {
                        "This is a demo admin. Everyone using the demo sees your changes, and none of the orders are real."
                    }
                    div.demo-ribbon aria-hidden="true" { "DEMO" }
                }
                div class="container admin-container" {
                    @if let Some(text) = success {
                        div class="bg-green-100 border border-green-500 text-green-900 px-4 py-3 rounded relative" { (text) }
                    }
                    @if let Some(text) = error {
                        div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded relative" { (text) }
                    }
                    (content)
                }
            }
        }
    };
    with_session(state, &session, markup)
}

/// `Admin/View/Sessions/New.hs`
fn login_form(demo: bool) -> Markup {
    html! {
        div.h-100 #sessions-new {
            div class="d-flex align-items-center" {
                div.w-100 {
                    div style="max-width: 400px" class="mx-auto mb-5" {
                        h2 { "Please login" }
                        @if demo {
                            div.demo-logins {
                                p { "Try it without an account, as an admin or as a delivery person who only sees orders:" }
                                div.demo-login-buttons {
                                    @for login in &DEMO_LOGINS {
                                        form method="POST" action={ "/admin/DemoLogin?role=" (login.role) } {
                                            button type="submit" class="btn-small" { (login.label) }
                                        }
                                    }
                                }
                            }
                        }
                        form method="POST" action="/admin/CreateSession" {
                            div.form-group {
                                input name="email" value="" type="email" class="form-control" placeholder="E-Mail" required="required" autofocus="autofocus";
                            }
                            div.form-group {
                                input name="password" type="password" class="form-control" placeholder="Password";
                            }
                            button type="submit" class="btn btn-primary btn-block" { "Login" }
                        }
                    }
                }
            }
        }
    }
}

pub async fn new_session(State(state): State<Arc<AppState>>, headers: HeaderMap) -> Response {
    let session = Session::from_headers(&state.session_key, &headers);
    page(&state, session, &login_form(state.site.demo))
}

/// Logs in with an email and password, as IHP's `createSessionAction`
pub async fn create_session(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Form(params): Form<Params>,
) -> Result<Response> {
    let (Some(email), Some(given)) = (params.get("email"), params.get("password")) else {
        return Ok(StatusCode::BAD_REQUEST.into_response());
    };
    let mut session = Session::from_headers(&state.session_key, &headers);
    let refuse = |mut session: Session, message: &str| {
        session.set_text(FLASH_ERROR, message);
        with_session(&state, &session, found(NEW_SESSION))
    };
    let Some(user) = db::user_by_email(&state.db, email).await? else {
        return Ok(refuse(session, "Invalid Credentials"));
    };
    if user.is_locked(chrono::Utc::now()) {
        return Ok(refuse(session, "User is locked"));
    }
    // Some 130 000 rounds of SHA-256, off the threads that answer requests
    let given = given.clone();
    let stored = user.password_hash.clone();
    let right = tokio::task::spawn_blocking(move || password::verify(&given, &stored))
        .await
        .unwrap_or(false);
    if !right {
        db::login_failed(&state.db, user.id).await?;
        tracing::info!(user = %user.id, "a wrong password");
        return Ok(refuse(session, "Invalid Credentials"));
    }
    session.login(user.id);
    db::login_succeeded(&state.db, user.id).await?;
    tracing::info!(user = %user.id, "logged in");
    let to = session
        .take_text(REDIRECT_AFTER_LOGIN)
        .unwrap_or_else(|| AFTER_LOGIN.to_string());
    Ok(with_session(&state, &session, see_other(&to)))
}

/// Logs out. The admin's logout link sends a POST with `_method=DELETE`,
/// as IHP's `js-delete` links do, which IHP takes as a DELETE.
pub async fn delete_session(State(state): State<Arc<AppState>>, headers: HeaderMap) -> Response {
    let mut session = Session::from_headers(&state.session_key, &headers);
    session.logout();
    with_session(&state, &session, see_other(NEW_SESSION))
}

pub async fn delete_session_by_post(
    state: State<Arc<AppState>>,
    headers: HeaderMap,
    Form(params): Form<Params>,
) -> Response {
    if params.get("_method").map(String::as_str) == Some("DELETE") {
        delete_session(state, headers).await
    } else {
        StatusCode::METHOD_NOT_ALLOWED.into_response()
    }
}

/// On a demo, logs in as one of its logins without a password
pub async fn demo_login(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Query(params): Query<Params>,
) -> Result<Response> {
    let Some(role) = params.get("role") else {
        return Ok(StatusCode::BAD_REQUEST.into_response());
    };
    let login = DEMO_LOGINS.iter().find(|login| login.role == role);
    let (true, Some(login)) = (state.site.demo, login) else {
        return Ok(crate::not_found(State(state), headers).await);
    };
    let user = db::ensure_demo_user(&state.db, login.email, login.roles, || {
        // Random, and never shown: the buttons log in without it
        let mut bytes = [0u8; 24];
        getrandom::fill(&mut bytes).expect("the system's random numbers");
        password::hash(&bytes.iter().map(|b| format!("{b:02x}")).collect::<String>())
    })
    .await?;
    let mut session = Session::from_headers(&state.session_key, &headers);
    session.login(user);
    tracing::info!(user = %user, role = login.role, "logged in to the demo");
    Ok(with_session(&state, &session, found(WELCOME)))
}

/// The logged-in user, with their session; or, for someone not logged in,
/// the login page, which will come back here, as IHP's `ensureIsUser`
pub async fn require_user(
    state: &AppState,
    headers: &HeaderMap,
    uri: &Uri,
) -> Result<std::result::Result<(AdminUser, Session), Response>> {
    let mut session = Session::from_headers(&state.session_key, headers);
    if let Some(id) = session.user_id()
        && let Some(user) = db::admin_user(&state.db, id).await?
    {
        return Ok(Ok((user, session)));
    }
    session.set_text(FLASH_SUCCESS, "Please log in to access this page");
    let here = uri.path_and_query().map_or(uri.path(), |p| p.as_str());
    session.set_text(REDIRECT_AFTER_LOGIN, here);
    Ok(Err(with_session(state, &session, found(NEW_SESSION))))
}

/// The menu: what each link needs, its text and address, A to Z
const MENU: &[(Permission, &str, &str)] = &[
    (
        Permission::SeeOrderedProducts,
        "All ordered products",
        "/admin/OrderedProducts",
    ),
    (Permission::ManageShop, "Customers", "/admin/Customers"),
    (
        Permission::SeeEmailLists,
        "Emails for delivery info",
        "/admin/EmailsForDeliveryInfo",
    ),
    (
        Permission::SeeEmailLists,
        "Emails for news letter",
        "/admin/EmailsForNewsLetter",
    ),
    (Permission::SeeOrders, "Orders", "/admin/Orders"),
    (
        Permission::ManageShop,
        "Payment Instructions",
        "/admin/PaymentInstructions",
    ),
    (Permission::EditShopTexts, "Producers", "/admin/Producers"),
    (Permission::EditShopTexts, "Products", "/admin/Products"),
    (
        Permission::ManageShop,
        "Welcome Messages",
        "/admin/WelcomeMessages",
    ),
];

/// `Admin/View/Static/Welcome.hs`: the links the user's roles allow
fn welcome_page(user: &AdminUser) -> Markup {
    // A demo's logins have no password to change
    let demo_user = DEMO_LOGINS.iter().any(|login| login.email == user.email);
    html! {
        a class="js-delete js-delete-no-confirm back-button float-right p-2" href="/admin/DeleteSession" { "Logout" }
        @if !demo_user {
            a class="float-right p-2" href="/admin/NewPassword" { "Change password" }
        }
        ol.my-4 {
            @for (permission, label, url) in MENU {
                @if user.roles.can(*permission) {
                    li { a href=(url) { (label) } }
                }
            }
            @if !user.roles.any() {
                li { "Your login has no role yet: ask an admin for one." }
            }
        }
    }
}

pub async fn welcome(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    uri: Uri,
) -> Result<Response> {
    let (user, session) = match require_user(&state, &headers, &uri).await? {
        Ok(found) => found,
        Err(to_login) => return Ok(to_login),
    };
    Ok(page(&state, session, &welcome_page(&user)))
}

/// The logged-in user if they may do this; the login page for someone not
/// logged in, and "access denied" for a user who may not
/// (`requirePermission`)
pub async fn require_permission(
    state: &AppState,
    headers: &HeaderMap,
    uri: &Uri,
    permission: Permission,
) -> Result<std::result::Result<(AdminUser, Session), Response>> {
    let (user, session) = match require_user(state, headers, uri).await? {
        Ok(found) => found,
        Err(to_login) => return Ok(Err(to_login)),
    };
    if !user.roles.can(permission) {
        tracing::info!(user = %user.id, ?permission, "access denied");
        let content = html! {
            h1 { "Access denied" }
            p { "Your login may not see this page." }
            p { a href=(WELCOME) { "Back to the start" } }
        };
        let mut response = page(state, session, &content);
        *response.status_mut() = StatusCode::FORBIDDEN;
        return Ok(Err(response));
    }
    Ok(Ok((user, session)))
}

/// A step of a page's breadcrumb, a link or the page itself
pub struct Crumb<'a> {
    label: &'a str,
    url: Option<&'a str>,
}

impl<'a> Crumb<'a> {
    pub fn link(label: &'a str, url: &'a str) -> Self {
        Self {
            label,
            url: Some(url),
        }
    }

    pub fn text(label: &'a str) -> Self {
        Self { label, url: None }
    }
}

/// IHP's Tailwind breadcrumb (`renderBreadcrumb`): a chevron after each
/// step but the last
pub fn breadcrumb(crumbs: &[Crumb]) -> Markup {
    html! {
        nav class="breadcrumbs bg-white my-4" aria-label="Breadcrumb" {
            ol class="flex items-center space-x-2" role="list" {
                @for (i, crumb) in crumbs.iter().enumerate() {
                    @let last = i == crumbs.len() - 1;
                    li class={ "flex flex-row space-x-2 text-gray-600 items-center" @if last { " active" } } {
                        @if let Some(url) = crumb.url {
                            a class="hover:text-gray-700" href=(url) { (crumb.label) }
                        } @else {
                            (crumb.label)
                        }
                        @if !last {
                            svg xmlns="http://www.w3.org/2000/svg" class="flex-shrink-0 h-4 w-4 text-gray-500" fill="none" viewBox="0 0 24 24" stroke="currentColor" {
                                path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" {}
                            }
                        }
                    }
                }
            }
        }
    }
}
