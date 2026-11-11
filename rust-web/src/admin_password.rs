//! Changing one's password, the IHP app's `Admin/Controller/Passwords.hs`:
//! the old one, and the new one twice. The new one is as the IHP app
//! required it (the password package's `defaultPasswordPolicy_`): 8 to 64
//! characters, each a letter a–z or A–Z, a digit, a space or ASCII
//! punctuation. Everyone shares a demo's logins, so their passwords can't
//! be changed: one visitor would lock the others out.

use std::sync::Arc;

use axum::extract::rejection::FormRejection;
use axum::extract::{Form, State};
use axum::http::{HeaderMap, Uri};
use axum::response::Response;
use maud::html;

use crate::admin::{self, Crumb, DEMO_LOGINS};
use crate::admin_forms::{get, submit};
use crate::db::{self, AdminUser};
use crate::session::{FLASH_ERROR, FLASH_SUCCESS, Session};
use crate::{AppState, Result, password};

const NEW: &str = "/admin/NewPassword";

/// The logged-in user who may change their password; or the login page,
/// or for a demo's login, back to the start saying why
async fn require(
    state: &AppState,
    headers: &HeaderMap,
    uri: &Uri,
) -> Result<std::result::Result<(AdminUser, Session), Response>> {
    let (user, mut session) = match admin::require_user(state, headers, uri).await? {
        Ok(found) => found,
        Err(to_login) => return Ok(Err(to_login)),
    };
    if DEMO_LOGINS.iter().any(|login| login.email == user.email) {
        session.set_text(FLASH_ERROR, "The demo logins' passwords can't be changed");
        return Ok(Err(admin::with_session(
            state,
            &session,
            admin::found(admin::WELCOME),
        )));
    }
    Ok(Ok((user, session)))
}

/// What's wrong with the new password, if anything
pub fn new_password_problem(new: &str) -> Option<&'static str> {
    let length = new.chars().count();
    if !(8..=64).contains(&length) {
        return Some("The new password must be 8 to 64 characters long.");
    }
    if !new.chars().all(|c| (' '..='~').contains(&c)) {
        return Some(
            "The new password may have letters a–z and A–Z, digits, spaces and punctuation, but not letters like ä or ö.",
        );
    }
    None
}

pub async fn new(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    uri: Uri,
) -> Result<Response> {
    let (_, session) = match require(&state, &headers, &uri).await? {
        Ok(found) => found,
        Err(response) => return Ok(response),
    };
    let field = |name: &str, label: &str, autocomplete: &str| {
        html! {
            div class="flex flex-col my-6 space-y-2" {
                label class="font-medium text-gray-700" for=(name) { (label) }
                input required type="password" id=(name) name=(name) autocomplete=(autocomplete);
            }
        }
    };
    let content = html! {
        (admin::breadcrumb(&[
            Crumb::link("Home", admin::WELCOME),
            Crumb::text("Change password"),
        ]))
        article {
            form method="POST" action="/admin/UpdatePassword" {
                (field("oldPassword", "Old password", "current-password"))
                (field("newPassword", "New password", "new-password"))
                (field("confirmPassword", "Confirm new password", "new-password"))
                p class="text-gray-600 text-xs italic" {
                    "8 to 64 characters: letters a–z and A–Z, digits, spaces and punctuation."
                }
                (submit("Change password"))
            }
        }
    };
    Ok(admin::page(&state, session, &content))
}

pub async fn update(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    uri: Uri,
    form: std::result::Result<Form<Vec<(String, String)>>, FormRejection>,
) -> Result<Response> {
    let (user, mut session) = match require(&state, &headers, &uri).await? {
        Ok(found) => found,
        Err(response) => return Ok(response),
    };
    let fields = form.map(|Form(fields)| fields).unwrap_or_default();
    let field = |name: &str| get(&fields, name).unwrap_or_default().to_string();
    let (old, new, confirm) = (
        field("oldPassword"),
        field("newPassword"),
        field("confirmPassword"),
    );
    let stored = db::password_hash(&state.db, user.id)
        .await?
        .unwrap_or_default();
    // Some 130 000 rounds of SHA-256, off the threads that answer requests
    let right = tokio::task::spawn_blocking(move || password::verify(&old, &stored))
        .await
        .unwrap_or(false);
    let problem = if !right {
        Some("The old password isn't right.")
    } else if new != confirm {
        Some("The new password and its confirmation differ.")
    } else {
        new_password_problem(&new)
    };
    if let Some(problem) = problem {
        session.set_text(FLASH_ERROR, problem);
        return Ok(admin::with_session(&state, &session, admin::found(NEW)));
    }
    let hash = tokio::task::spawn_blocking(move || password::hash(&new))
        .await
        .map_err(|e| sqlx::Error::Protocol(e.to_string()))?;
    db::set_password_hash(&state.db, user.id, &hash).await?;
    tracing::info!(user = %user.id, "changed their password");
    session.set_text(FLASH_SUCCESS, "Password changed");
    Ok(admin::with_session(
        &state,
        &session,
        admin::found(admin::WELCOME),
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// As the password package's defaultPasswordPolicy_
    #[test]
    fn new_passwords_as_ihp_took_them() {
        let longest = "x".repeat(64);
        for good in ["salasana", "Oliivi-oljy 2026", "a b ~!@#", &longest] {
            assert_eq!(new_password_problem(good), None, "{good}");
        }
        let too_long = "x".repeat(65);
        for bad in ["lyhyt", "", &too_long, "Oliiviöljy 2026", "tab\there1"] {
            assert!(new_password_problem(bad).is_some(), "{bad}");
        }
    }
}
