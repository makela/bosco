//! IHP's session, the `SESSION` cookie, read and written as IHP does, so
//! that a login here is a login in the IHP app's admin and the other way
//! round, and the flash messages of one show on the other's next page.
//!
//! The cookie is the clientsession library's: base64 of a Skein-MAC-512-256
//! (32 bytes), a random IV (16 bytes) and the session encrypted with
//! AES-256-CTR, all with the instance's 96-byte key (64 bytes for the MAC,
//! then 32 for AES), the file in `IHP_SESSION_SECRET_FILE`. The session is
//! cereal's encoding of the key-value pairs: a list, each string with its
//! length before it, as 8 bytes big-endian.

use std::path::Path;

use aes::cipher::{KeyIvInit, StreamCipher};
use axum::http::{HeaderMap, HeaderValue, header};
use base64::Engine;
use base64::engine::general_purpose::STANDARD as BASE64;
use subtle::ConstantTimeEq;

use crate::skein_mac::mac_512_256;

type Aes256Ctr = ctr::Ctr128BE<aes::Aes256>;

pub const COOKIE: &str = "SESSION";
/// IHP's: 30 days
const MAX_AGE: u32 = 60 * 60 * 24 * 30;

/// Where IHP keeps the logged-in user's id, as its 36 characters
pub const LOGIN: &[u8] = b"login.User";
/// Where IHP keeps the page a login should go back to, as a Text
pub const REDIRECT_AFTER_LOGIN: &[u8] = b"IHP.LoginSupport.redirectAfterLogin";
pub const FLASH_SUCCESS: &[u8] = b"flashSuccessMessage";
pub const FLASH_ERROR: &[u8] = b"flashErrorMessage";

/// The instance's session key
#[derive(Clone)]
pub struct Key {
    mac: [u8; 64],
    aes: [u8; 32],
}

impl Key {
    pub fn from_bytes(bytes: &[u8]) -> Result<Self, String> {
        if bytes.len() != 96 {
            return Err(format!(
                "a session key is 96 bytes, this one is {}",
                bytes.len()
            ));
        }
        let (mac, aes) = bytes.split_at(64);
        Ok(Self {
            mac: mac.try_into().expect("64 bytes"),
            aes: aes.try_into().expect("32 bytes"),
        })
    }

    /// The key in `path`, made there first if there's none, as IHP does
    pub fn load_or_create(path: &Path) -> Result<Self, String> {
        let error = |e: std::io::Error| format!("the session key {}: {e}", path.display());
        if !path.exists() {
            let mut bytes = [0u8; 96];
            getrandom::fill(&mut bytes).map_err(|e| e.to_string())?;
            std::fs::write(path, bytes).map_err(error)?;
            tracing::info!("made a new session key in {}", path.display());
        }
        let bytes = std::fs::read(path).map_err(error)?;
        Self::from_bytes(&bytes).map_err(|e| format!("{}: {e}", path.display()))
    }

    fn encrypt(&self, iv: [u8; 16], plain: &[u8]) -> String {
        let mut data = plain.to_vec();
        Aes256Ctr::new(&self.aes.into(), &iv.into()).apply_keystream(&mut data);
        let mut authed = iv.to_vec();
        authed.extend_from_slice(&data);
        let mut out = mac_512_256(&self.mac, &authed).to_vec();
        out.extend_from_slice(&authed);
        BASE64.encode(out)
    }

    fn decrypt(&self, cookie: &str) -> Option<Vec<u8>> {
        let bytes = BASE64.decode(cookie).ok()?;
        if bytes.len() < 48 {
            return None;
        }
        let (mac, authed) = bytes.split_at(32);
        if !bool::from(mac_512_256(&self.mac, authed).ct_eq(mac)) {
            return None;
        }
        let (iv, data) = authed.split_at(16);
        let mut data = data.to_vec();
        Aes256Ctr::new(&self.aes.into(), iv.into()).apply_keystream(&mut data);
        Some(data)
    }
}

/// A request's session. Changes to it are sent back with `set_cookie`.
#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct Session {
    /// The newest first, as IHP keeps them
    pairs: Vec<(Vec<u8>, Vec<u8>)>,
    changed: bool,
}

impl Session {
    /// The request's session; empty if it has none, or one this key didn't
    /// make, as in IHP
    pub fn from_headers(key: &Key, headers: &HeaderMap) -> Self {
        let pairs = cookie(headers, COOKIE)
            .and_then(|value| key.decrypt(value))
            .and_then(|plain| decode(&plain))
            .unwrap_or_default();
        Self {
            pairs,
            changed: false,
        }
    }

    pub fn get(&self, name: &[u8]) -> Option<&[u8]> {
        self.pairs
            .iter()
            .find(|(key, _)| key == name)
            .map(|(_, value)| value.as_slice())
    }

    /// As IHP's `sessionInsert`: the value replaces any before it
    pub fn insert(&mut self, name: &[u8], value: Vec<u8>) {
        self.pairs.retain(|(key, _)| key != name);
        self.pairs.insert(0, (name.to_vec(), value));
        self.changed = true;
    }

    /// As IHP's `deleteSession`, which leaves the name with nothing
    pub fn remove(&mut self, name: &[u8]) {
        self.insert(name, Vec::new());
    }

    /// A Text set with IHP's `setSession`, as the flash messages are
    pub fn get_text(&self, name: &[u8]) -> Option<String> {
        let mut reader = Reader(self.get(name)?);
        let text = String::from_utf8(reader.bytes()?.to_vec()).ok()?;
        reader.0.is_empty().then_some(text)
    }

    pub fn set_text(&mut self, name: &[u8], text: &str) {
        let mut value = Vec::new();
        put_bytes(&mut value, text.as_bytes());
        self.insert(name, value);
    }

    /// Takes a Text out, as IHP's `getSessionAndClear`
    pub fn take_text(&mut self, name: &[u8]) -> Option<String> {
        let text = self.get_text(name)?;
        self.remove(name);
        Some(text)
    }

    /// The logged-in user's id
    pub fn user_id(&self) -> Option<uuid::Uuid> {
        let value = self.get(LOGIN)?;
        uuid::Uuid::try_parse_ascii(value).ok()
    }

    pub fn login(&mut self, user_id: uuid::Uuid) {
        self.insert(LOGIN, user_id.hyphenated().to_string().into_bytes());
    }

    pub fn logout(&mut self) {
        self.remove(LOGIN);
    }

    /// The cookie value, encrypted with a new IV
    pub fn encrypt(&self, key: &Key) -> String {
        let mut iv = [0u8; 16];
        getrandom::fill(&mut iv).expect("the system's random numbers");
        key.encrypt(iv, &encode(&self.pairs))
    }

    /// Adds the Set-Cookie that saves the session, if it changed
    pub fn set_cookie(&self, key: &Key, secure: bool, headers: &mut HeaderMap) {
        if !self.changed {
            return;
        }
        let cookie = format!(
            "{COOKIE}={}; Path=/; Max-Age={MAX_AGE}; HttpOnly; SameSite=Lax{}",
            self.encrypt(key),
            if secure { "; Secure" } else { "" }
        );
        headers.append(
            header::SET_COOKIE,
            HeaderValue::from_str(&cookie).expect("base64 is a header value"),
        );
    }
}

/// A cookie's value from the request
pub fn cookie<'a>(headers: &'a HeaderMap, name: &str) -> Option<&'a str> {
    headers
        .get_all(header::COOKIE)
        .iter()
        .filter_map(|value| value.to_str().ok())
        .flat_map(|cookies| cookies.split(';'))
        .filter_map(|cookie| cookie.trim().split_once('='))
        .find(|(key, _)| *key == name)
        .map(|(_, value)| value)
}

fn put_bytes(out: &mut Vec<u8>, bytes: &[u8]) {
    out.extend_from_slice(&(bytes.len() as u64).to_be_bytes());
    out.extend_from_slice(bytes);
}

fn encode(pairs: &[(Vec<u8>, Vec<u8>)]) -> Vec<u8> {
    let mut out = (pairs.len() as u64).to_be_bytes().to_vec();
    for (key, value) in pairs {
        put_bytes(&mut out, key);
        put_bytes(&mut out, value);
    }
    out
}

struct Reader<'a>(&'a [u8]);

impl<'a> Reader<'a> {
    fn length(&mut self) -> Option<usize> {
        let (bytes, rest) = self.0.split_first_chunk::<8>()?;
        self.0 = rest;
        usize::try_from(u64::from_be_bytes(*bytes)).ok()
    }

    fn bytes(&mut self) -> Option<&'a [u8]> {
        let length = self.length()?;
        if length > self.0.len() {
            return None;
        }
        let (bytes, rest) = self.0.split_at(length);
        self.0 = rest;
        Some(bytes)
    }
}

fn decode(plain: &[u8]) -> Option<Vec<(Vec<u8>, Vec<u8>)>> {
    let mut reader = Reader(plain);
    let count = reader.length()?;
    // Each pair is at least its two lengths
    if count > reader.0.len() / 16 {
        return None;
    }
    let mut pairs = Vec::with_capacity(count);
    for _ in 0..count {
        let key = reader.bytes()?.to_vec();
        let value = reader.bytes()?.to_vec();
        pairs.push((key, value));
    }
    reader.0.is_empty().then_some(pairs)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn key() -> Key {
        Key::from_bytes(&(0..96).collect::<Vec<u8>>()).unwrap()
    }

    fn headers(cookie: &str) -> HeaderMap {
        let mut headers = HeaderMap::new();
        headers.insert(
            header::COOKIE,
            HeaderValue::from_str(&format!("other=1; {COOKIE}={cookie}")).unwrap(),
        );
        headers
    }

    /// A session IHP's libraries made (clientsession's `encrypt` with the
    /// key 0, 1, … 95 and the IV 100, 101, … 115, in IHP's dev shell): a
    /// failed login's message and a logged-in user
    const IHP_COOKIE: &str = "7vdLskic0TGm1irkTS7HvdxXr6ma3xJD2jFxPM4VaJxkZWZnaGlqa2xtbm9wcXJzylCin1TB/TAhXtPnO5XiEBIrVu38oE9aF4Qeywufkm3aYRvhL07Y6IkAtLqghW6zVgsU+9zaORSb1nzEjRuM+cnkBoDTf5UZszbBO3wtvttqQwu3uhyEFLkfj3Tt1CQfG1CzrAL2fCecnOfA2diJuK2TRBpLIy4XfiLFa9rkhhOm6g==";
    const USER: &str = "0c1d2e3f-4a5b-6c7d-8e9f-a0b1c2d3e4f5";

    #[test]
    fn reads_ihps_session() {
        let session = Session::from_headers(&key(), &headers(IHP_COOKIE));
        assert_eq!(session.user_id(), Some(USER.parse().unwrap()));
        assert_eq!(
            session.get_text(FLASH_ERROR).as_deref(),
            Some("Invalid Credentials")
        );
        assert_eq!(session.get_text(FLASH_SUCCESS), None);
    }

    #[test]
    fn writes_the_same_cookie_as_ihp() {
        let mut session = Session::default();
        session.login(USER.parse().unwrap());
        session.set_text(FLASH_ERROR, "Invalid Credentials");
        let iv: [u8; 16] = std::array::from_fn(|i| 100 + i as u8);
        assert_eq!(key().encrypt(iv, &encode(&session.pairs)), IHP_COOKIE);
    }

    #[test]
    fn a_changed_session_reads_back() {
        let mut session = Session::from_headers(&key(), &headers(IHP_COOKIE));
        assert_eq!(
            session.take_text(FLASH_ERROR).as_deref(),
            Some("Invalid Credentials")
        );
        session.set_text(FLASH_SUCCESS, "Päivitetty");
        session.logout();
        let mut out = HeaderMap::new();
        session.set_cookie(&key(), true, &mut out);
        let set = out[header::SET_COOKIE].to_str().unwrap();
        assert!(set.ends_with("; Path=/; Max-Age=2592000; HttpOnly; SameSite=Lax; Secure"));
        let value = set
            .strip_prefix("SESSION=")
            .unwrap()
            .split(';')
            .next()
            .unwrap();
        let read = Session::from_headers(&key(), &headers(value));
        assert_eq!(read.user_id(), None);
        assert_eq!(read.get(LOGIN), Some(&b""[..]));
        assert_eq!(read.get_text(FLASH_ERROR), None);
        assert_eq!(read.get_text(FLASH_SUCCESS).as_deref(), Some("Päivitetty"));
    }

    #[test]
    fn an_unchanged_session_sets_no_cookie() {
        let session = Session::from_headers(&key(), &headers(IHP_COOKIE));
        let mut out = HeaderMap::new();
        session.set_cookie(&key(), false, &mut out);
        assert!(out.is_empty());
    }

    #[test]
    fn a_session_another_key_made_is_empty() {
        let mut other = (0..96).collect::<Vec<u8>>();
        other[0] = 255;
        let session =
            Session::from_headers(&Key::from_bytes(&other).unwrap(), &headers(IHP_COOKIE));
        assert_eq!(session, Session::default());
        let mut tampered = BASE64.decode(IHP_COOKIE).unwrap();
        *tampered.last_mut().unwrap() ^= 1;
        let session = Session::from_headers(&key(), &headers(&BASE64.encode(tampered)));
        assert_eq!(session, Session::default());
        assert_eq!(
            Session::from_headers(&key(), &headers("nonsense")),
            Session::default()
        );
    }
}
