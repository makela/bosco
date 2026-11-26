//! The admin's password hashes: bcrypt (`$2b$12$…`) for new ones, and the
//! IHP app's for those from before, until their user next logs in
//! (`needs_rehash`).
//!
//! IHP's are pwstore-fast's `makePassword` with strength 17, e.g.
//! `sha256|17|<salt>|<hash>`: SHA-256 of the password and the salt, then of
//! that 2^17 + 1 times more, in base64, the salt used as written. That's
//! fast to compute on a GPU, which bcrypt isn't.

use base64::Engine;
use base64::engine::general_purpose::STANDARD as BASE64;
use sha2::{Digest, Sha256};
use subtle::ConstantTimeEq;

/// bcrypt's cost for new hashes: some 0.25 s a check
pub const COST: u32 = 12;

fn is_bcrypt(stored: &str) -> bool {
    ["$2a$", "$2b$", "$2y$"]
        .iter()
        .any(|prefix| stored.starts_with(prefix))
}

/// A bcrypt hash's cost, e.g. 12 of `$2b$12$…`
fn bcrypt_cost(stored: &str) -> Option<u32> {
    stored.get(4..6)?.parse().ok()
}

/// Whether `password` is the one `stored` is a hash of, bcrypt or IHP's.
/// A hash that's neither, or too strong to check in time, matches nothing.
pub fn verify(password: &str, stored: &str) -> bool {
    if is_bcrypt(stored) {
        bcrypt::verify(password, stored).unwrap_or(false)
    } else {
        verify_ihp(password, stored)
    }
}

/// A new hash of `password`: bcrypt, with a random salt
pub fn hash(password: &str) -> String {
    bcrypt::hash(password, COST).expect("bcrypt takes a password of up to 64 characters")
}

/// Whether a hash that `verify` just took is to be replaced with a new
/// one: an IHP app's, or a bcrypt one weaker than `COST`
pub fn needs_rehash(stored: &str) -> bool {
    !is_bcrypt(stored) || bcrypt_cost(stored).is_none_or(|cost| cost < COST)
}

fn pbkdf1(password: &[u8], salt: &[u8], strength: u32) -> String {
    let mut hash: [u8; 32] = Sha256::new()
        .chain_update(password)
        .chain_update(salt)
        .finalize()
        .into();
    // 2^strength + 1 more, as pwstore-fast does
    for _ in 0..=(1u64 << strength) {
        hash = Sha256::digest(hash).into();
    }
    BASE64.encode(hash)
}

fn verify_ihp(password: &str, stored: &str) -> bool {
    let parts: Vec<&str> = stored.split('|').collect();
    let [algorithm, strength, salt, hash] = parts[..] else {
        return false;
    };
    let Ok(strength) = strength.parse::<u32>() else {
        return false;
    };
    if algorithm != "sha256" || hash.len() != 44 || strength > 24 {
        return false;
    }
    pbkdf1(password.as_bytes(), salt.as_bytes(), strength)
        .as_bytes()
        .ct_eq(hash.as_bytes())
        .into()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Made with pwstore-fast in IHP's dev shell, of the password's UTF-8
    /// as IHP hashes it
    const SALASANA: &str =
        "sha256|17|MDEyMzQ1Njc4OWFiY2RlZg==|pjd4FtSmTigPFEAxWJsMLlyZhWffudNA3BVqtAMHHmg=";

    #[test]
    fn checks_ihps_hashes() {
        assert!(verify("salasana", SALASANA));
        assert!(!verify("Salasana", SALASANA));
        assert!(!verify("", SALASANA));
        assert!(verify(
            "pässwörd",
            "sha256|4|ZmVkY2JhOTg3NjU0MzIxMA==|RL/Izi/Yr3jOTTtiDWr/ODzYXEVhgWPFNT+OmzFOgf8="
        ));
        // As IHP made it, with a random salt
        assert!(verify(
            "Oliivi-öljy 2026",
            "sha256|17|mAE53Z11AJe+uhJ71nl/jQ==|OdKuuNHwYNTt8F9woQDDvk4uXqDcktQr4lBF0U5x1Wg="
        ));
    }

    #[test]
    fn other_hashes_match_nothing() {
        for stored in [
            "",
            "x",
            "salasana",
            "$2b$",
            "sha512|17|MDEyMzQ1Njc4OWFiY2RlZg==|pjd4FtSmTigPFEAxWJsMLlyZhWffudNA3BVqtAMHHmg=",
            "sha256|x|MDEyMzQ1Njc4OWFiY2RlZg==|pjd4FtSmTigPFEAxWJsMLlyZhWffudNA3BVqtAMHHmg=",
            "sha256|99|MDEyMzQ1Njc4OWFiY2RlZg==|pjd4FtSmTigPFEAxWJsMLlyZhWffudNA3BVqtAMHHmg=",
        ] {
            assert!(!verify("salasana", stored), "{stored}");
        }
    }

    #[test]
    fn makes_bcrypt_hashes_of_its_cost() {
        let made = hash("salasana");
        assert!(made.starts_with("$2b$12$"), "{made}");
        assert!(verify("salasana", &made));
        assert!(!verify("salasana1", &made));
        assert_ne!(made, hash("salasana"), "a new salt each time");
        assert!(!needs_rehash(&made));
    }

    #[test]
    fn replaces_ihps_hashes_and_weaker_bcrypt_ones() {
        assert!(needs_rehash(SALASANA));
        // htpasswd -B's cost
        let weak = bcrypt::hash("salasana", 5).unwrap();
        assert!(verify("salasana", &weak));
        assert!(needs_rehash(&weak));
    }
}
