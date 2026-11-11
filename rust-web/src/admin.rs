//! The admin's login and logout, the IHP app's `Admin/Controller/Sessions.hs`
//! with IHP's `IHP.AuthSupport.Controller.Sessions`. The rest of the admin
//! is still the IHP app's: they share IHP's session cookie (`session.rs`),
//! so a login here lets one into the IHP app's admin pages, and their flash
//! messages show here.
//!
//! As in IHP, a login is locked for an hour after 10 wrong passwords in a
//! row, and the login page is shown even to someone logged in.

use std::sync::Arc;

use axum::extract::{Form, Query, State};
use axum::http::{HeaderMap, StatusCode, header};
use axum::response::{IntoResponse, Response};
use maud::{DOCTYPE, Markup, html};

use crate::db::{self, Roles};
use crate::session::{FLASH_ERROR, FLASH_SUCCESS, REDIRECT_AFTER_LOGIN, Session};
use crate::{AppState, Params, Result, password};

pub const NEW_SESSION: &str = "/admin/NewSession";
/// The admin's start page, where a demo login goes
const WELCOME: &str = "/admin/Welcome";
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
fn with_session(state: &AppState, session: &Session, response: impl IntoResponse) -> Response {
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
fn page(state: &AppState, mut session: Session, content: &Markup) -> Response {
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
