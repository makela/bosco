//! An address's query string, read as IHP reads it: its items in order,
//! decoded, and a name without "=" has no value.

/// The items in order
pub type Items = Vec<(String, Option<String>)>;

/// The query string's items, decoded
pub fn items(query: Option<&str>) -> Items {
    query
        .unwrap_or_default()
        .split('&')
        .filter(|item| !item.is_empty())
        .map(|item| match item.split_once('=') {
            Some((name, value)) => (decode(name), Some(decode(value))),
            None => (decode(item), None),
        })
        .collect()
}

fn decode(text: &str) -> String {
    let bytes = text.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        match bytes[i] {
            b'+' => out.push(b' '),
            b'%' if i + 2 < bytes.len() => {
                let hex = std::str::from_utf8(&bytes[i + 1..i + 3]).ok();
                match hex.and_then(|hex| u8::from_str_radix(hex, 16).ok()) {
                    Some(byte) => {
                        out.push(byte);
                        i += 2;
                    }
                    None => out.push(b'%'),
                }
            }
            byte => out.push(byte),
        }
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_the_query() {
        assert_eq!(
            items(Some("q=a+b%C3%A4&flag&x=%zz")),
            [
                ("q".to_string(), Some("a bä".to_string())),
                ("flag".to_string(), None),
                ("x".to_string(), Some("%zz".to_string()))
            ]
        );
        assert_eq!(items(None), []);
    }
}
