//! The public forms' checks, as in the IHP app: `nonEmptyOrWhitespace`,
//! IHP's `isEmail`, `isPhone` and `isPostalCode`. Each returns the text to
//! show under the field when the value isn't accepted.

use std::sync::LazyLock;

use regex::Regex;

use crate::l10n::Text;

pub type Check = Result<(), Text>;

/// Something other than spaces
pub fn required(value: &str) -> Check {
    if value.trim().is_empty() {
        Err(Text::FieldRequired)
    } else {
        Ok(())
    }
}

/// IHP's `isEmail`, the same pattern. The value isn't trimmed first, as in
/// the IHP app, so spaces around it make it invalid.
pub fn email(value: &str) -> Check {
    static EMAIL: LazyLock<Regex> = LazyLock::new(|| {
        Regex::new(r"^[^ @]+@[^ @_+]+\.?[^ @_+-]+$").expect("a constant, valid pattern")
    });
    if EMAIL.is_match(value) {
        Ok(())
    } else {
        Err(Text::InvalidEmail)
    }
}

/// A phone number of any country with its country code, or a Finnish one
/// without. Spaces or hyphens may split the digits into groups.
///
/// - International: + or 00, then the country code (which never starts
///   with 0) and the number, 7-15 digits in all, e.g. "+39 333 123 4567".
/// - Finnish with the country code but no +: 358..., 9-12 digits.
/// - Finnish local: 0..., 7-10 digits.
pub fn phone(value: &str) -> Check {
    let stripped = value.trim();
    let well_formed = |number: &str| {
        number.starts_with(|c: char| c.is_ascii_digit())
            && number.ends_with(|c: char| c.is_ascii_digit())
            && number
                .chars()
                .all(|c| c.is_ascii_digit() || c == ' ' || c == '-')
    };
    let digits_between = |number: &str, low: usize, high: usize| {
        (low..=high).contains(&number.chars().filter(char::is_ascii_digit).count())
    };
    let international = stripped
        .strip_prefix('+')
        .or_else(|| stripped.strip_prefix("00"));
    let valid = match international {
        Some(rest) => well_formed(rest) && !rest.starts_with('0') && digits_between(rest, 7, 15),
        None => {
            well_formed(stripped)
                && ((stripped.starts_with('3') && digits_between(stripped, 9, 12))
                    || (stripped.starts_with('0') && digits_between(stripped, 7, 10)))
        }
    };
    if valid {
        Ok(())
    } else {
        Err(Text::InvalidPhone)
    }
}

/// A Finnish postal code: five digits
pub fn postal_code(value: &str) -> Check {
    let stripped = value.trim();
    if stripped.chars().count() == 5 && stripped.chars().all(|c| c.is_ascii_digit()) {
        Ok(())
    } else {
        Err(Text::InvalidPostalCode)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn phones_as_in_the_ihp_app() {
        for valid in [
            "040 123 4567",
            "050-765 4321",
            "0401112233",
            "+358 44 987 6543",
            "+39 333 123 4567",
            "0039 333 123 4567",
            "358401234567",
        ] {
            assert_eq!(phone(valid), Ok(()), "{valid}");
        }
        for invalid in [
            "",
            "123",
            "+0 123 4567",
            "040 123 456a",
            "-040 1234567",
            "(040) 123 4567",
            "0401234567890",
        ] {
            assert_eq!(phone(invalid), Err(Text::InvalidPhone), "{invalid}");
        }
    }

    #[test]
    fn emails_as_ihp_checks_them() {
        assert_eq!(email("maija.virtanen@example.fi"), Ok(()));
        for invalid in [
            "",
            "maija",
            "maija@",
            "@example.fi",
            " maija@example.fi",
            "a b@c.fi",
        ] {
            assert_eq!(email(invalid), Err(Text::InvalidEmail), "{invalid}");
        }
    }

    #[test]
    fn postal_codes_have_five_digits() {
        assert_eq!(postal_code(" 00100 "), Ok(()));
        for invalid in ["0010", "001000", "0010a", "FI-00100"] {
            assert_eq!(
                postal_code(invalid),
                Err(Text::InvalidPostalCode),
                "{invalid}"
            );
        }
    }

    #[test]
    fn required_needs_more_than_spaces() {
        assert_eq!(required(" Maija "), Ok(()));
        assert_eq!(required("  "), Err(Text::FieldRequired));
    }
}
