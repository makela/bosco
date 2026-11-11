//! IHP's password hashes (pwstore-fast's `makePassword` with strength 17),
//! e.g. `sha256|17|<salt>|<hash>`: SHA-256 of the password and the salt,
//! then of that 2^17 + 1 times more, in base64. The salt is used as written,
//! in base64.

use base64::Engine;
use base64::engine::general_purpose::STANDARD as BASE64;
use sha2::{Digest, Sha256};
use subtle::ConstantTimeEq;

/// IHP's `passwordStrength`
const STRENGTH: u32 = 17;

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

/// Whether `password` is the one `stored` is a hash of. A hash that isn't
/// one of these, or too strong to check in time, matches nothing.
pub fn verify(password: &str, stored: &str) -> bool {
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

/// A new hash of `password`, with a random salt, as IHP's `hashPassword`
pub fn hash(password: &str) -> String {
    let mut salt = [0u8; 16];
    getrandom::fill(&mut salt).expect("the system's random numbers");
    let salt = BASE64.encode(salt);
    let hash = pbkdf1(password.as_bytes(), salt.as_bytes(), STRENGTH);
    format!("sha256|{STRENGTH}|{salt}|{hash}")
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
            "sha512|17|MDEyMzQ1Njc4OWFiY2RlZg==|pjd4FtSmTigPFEAxWJsMLlyZhWffudNA3BVqtAMHHmg=",
            "sha256|x|MDEyMzQ1Njc4OWFiY2RlZg==|pjd4FtSmTigPFEAxWJsMLlyZhWffudNA3BVqtAMHHmg=",
            "sha256|99|MDEyMzQ1Njc4OWFiY2RlZg==|pjd4FtSmTigPFEAxWJsMLlyZhWffudNA3BVqtAMHHmg=",
        ] {
            assert!(!verify("salasana", stored), "{stored}");
        }
    }

    #[test]
    fn makes_hashes_ihp_reads() {
        let made = hash("salasana");
        assert!(made.starts_with("sha256|17|"));
        assert_eq!(made.len(), SALASANA.len());
        assert!(verify("salasana", &made));
        assert_ne!(made, hash("salasana"), "a new salt each time");
    }
}
