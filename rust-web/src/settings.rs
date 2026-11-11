//! Reading the programs' settings from the environment

use std::env;

/// The variable, or `default` when it's unset
pub fn setting(name: &str, default: &str) -> String {
    env::var(name).unwrap_or_else(|_| default.to_string())
}

/// A variable that is on or off: 1 or true, 0 or false, `default` when
/// unset or empty
pub fn flag(name: &str, default: bool) -> Result<bool, String> {
    match setting(name, "").as_str() {
        "" => Ok(default),
        "1" | "true" => Ok(true),
        "0" | "false" => Ok(false),
        other => Err(format!("{name} should be 1 or 0, got {other}")),
    }
}
