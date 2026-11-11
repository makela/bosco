//! IHP's pagination (`IHP.Pagination`) for the admin's lists, with its
//! Tailwind markup: 50 to a page by default, `?page=` and `?maxItems=` (1 to
//! 200) in the address, the pages around the current one with "..." for
//! the gaps, and a choice of page sizes. The links keep the rest of the
//! address's query.

use maud::{Markup, PreEscaped, html};

/// The pages a list is cut into
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Pagination {
    pub current_page: i64,
    pub total_items: i64,
    pub page_size: i64,
    /// Pages shown on each side of the current one
    pub window: i64,
}

/// A query string's items in order, as IHP keeps them: a name without "="
/// has no value
pub type QueryItems = Vec<(String, Option<String>)>;

/// The query string's items, decoded
pub fn query_items(query: Option<&str>) -> QueryItems {
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

/// As http-types' `renderQuery True`: letters, digits and `-_.~` as they
/// are, the rest, spaces too, as %XX
fn encode(text: &str) -> String {
    let mut out = String::new();
    for byte in text.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(byte as char)
            }
            _ => out.push_str(&format!("%{byte:02X}")),
        }
    }
    out
}

/// The first value of a query parameter, IHP's `paramOrNothing`: none when
/// it's missing or empty
fn param<'a>(items: &'a QueryItems, name: &str) -> Option<&'a str> {
    items
        .iter()
        .find(|(key, _)| key == name)
        .and_then(|(_, value)| value.as_deref())
        .filter(|value| !value.is_empty())
}

/// `page` or `maxItems` isn't a whole number: a 400
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BadPage;

/// IHP's ParamReader Int: an optional sign and digits
fn int_param(items: &QueryItems, name: &str) -> Result<Option<i64>, BadPage> {
    match param(items, name) {
        None => Ok(None),
        Some(text) => {
            let digits = text.strip_prefix(['-', '+']).unwrap_or(text);
            if digits.is_empty() || !digits.bytes().all(|b| b.is_ascii_digit()) {
                return Err(BadPage);
            }
            text.trim_start_matches('+')
                .parse()
                .map(Some)
                .map_err(|_| BadPage)
        }
    }
}

impl Pagination {
    /// The page the address asks for, of `total_items`
    pub fn from_query(items: &QueryItems, total_items: i64) -> Result<Self, BadPage> {
        let page = int_param(items, "page")?.unwrap_or(1).max(1);
        let page_size = int_param(items, "maxItems")?.unwrap_or(50).clamp(1, 200);
        Ok(Self {
            current_page: page,
            total_items,
            page_size,
            window: 5,
        })
    }

    pub fn offset(&self) -> i64 {
        (self.current_page - 1).saturating_mul(self.page_size)
    }

    fn last_page(&self) -> i64 {
        if self.page_size > 1 {
            (self.total_items - 1).div_euclid(self.page_size) + 1
        } else {
            self.total_items / self.page_size
        }
    }

    fn has_next(&self) -> bool {
        self.last_page() > self.current_page
    }

    fn has_previous(&self) -> bool {
        self.current_page > 1
    }

    /// The pages to link to, None for "..."
    fn pages(&self) -> Vec<Option<i64>> {
        let (current, window, last) = (self.current_page, self.window, self.last_page());
        let numbers: Vec<i64> = if window > last {
            (1..=last).collect()
        } else {
            let lower = if current - window < 1 {
                1
            } else if current + window > last {
                last - window * 2 + 1
            } else {
                current - window
            };
            let upper = if current + window > last {
                last
            } else if current - window < 1 {
                window * 2
            } else {
                current + window
            };
            let mut numbers = vec![1];
            numbers.extend(lower.max(1)..=upper.min(last));
            numbers.push(last);
            let mut seen = Vec::new();
            numbers.retain(|n| {
                let new = !seen.contains(n);
                seen.push(*n);
                new
            });
            numbers
        };
        let mut pages = Vec::new();
        for (i, n) in numbers.iter().enumerate() {
            pages.push(Some(*n));
            if let Some(next) = numbers.get(i + 1)
                && *next != n + 1
            {
                pages.push(None);
            }
        }
        pages
    }
}

/// The address with these query values set: replaced where they are,
/// added at the end where they aren't (`setQueryValue`)
fn url_with(path: &str, items: &QueryItems, set: &[(&str, String)]) -> String {
    let mut items = items.clone();
    for (name, value) in set {
        if items.iter().any(|(key, _)| key == name) {
            for item in items.iter_mut().filter(|(key, _)| key == name) {
                item.1 = Some(value.clone());
            }
        } else {
            items.push((name.to_string(), Some(value.clone())));
        }
    }
    if items.is_empty() {
        return path.to_string();
    }
    let query: Vec<String> = items
        .iter()
        .map(|(name, value)| match value {
            Some(value) => format!("{}={}", encode(name), encode(value)),
            None => encode(name),
        })
        .collect();
    format!("{path}?{}", query.join("&"))
}

/// IHP's `renderPagination` with Tailwind, under a list; nothing when it's
/// all on one page
pub fn render(pagination: &Pagination, path: &str, items: &QueryItems) -> Markup {
    let p = pagination;
    if p.current_page == 1 && !p.has_next() && !p.has_previous() {
        return html! {};
    }
    // The page's address keeps the filter and page size it was asked with
    let page_url = |n: i64| {
        let mut set = vec![("page", n.to_string())];
        if let Some(filter) = param(items, "filter") {
            set.push(("filter", filter.to_string()));
        }
        if let Ok(Some(max)) = int_param(items, "maxItems") {
            set.push(("maxItems", max.to_string()));
        }
        url_with(path, items, &set)
    };
    let size_url = |n: i64| {
        url_with(
            path,
            items,
            &[("maxItems", n.to_string()), ("page", "1".to_string())],
        )
    };
    let previous_url = if p.has_previous() {
        page_url(p.current_page - 1)
    } else {
        "#".to_string()
    };
    let next_url = if p.has_next() {
        page_url(p.current_page + 1)
    } else {
        "#".to_string()
    };
    let default_class = "relative inline-flex items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50";
    let disabled = |off: bool| if off { " disabled" } else { "" };
    html! {
        div class="bg-white px-4 py-3 flex items-center justify-between border-t border-gray-200 sm:px-6" {
            div class="flex-1 flex justify-between sm:hidden" {
                a href=(previous_url) class={ (default_class) (disabled(!p.has_previous())) } { "Previous" }
                a href=(next_url) class={ (default_class) (disabled(!p.has_next())) } { "Next" }
            }
            div class="hidden sm:flex-1 sm:flex sm:items-center sm:justify-between" {
                div class="text-sm text-gray-700" {
                    select class="px-4 py-3" id="maxItemsSelect" onchange="window.location.href = this.options[this.selectedIndex].dataset.url" {
                        @for n in [10, 20, 50, 100, 200] {
                            option value=(n) selected=[(n == p.page_size).then_some("selected")] data-url=(size_url(n)) { (n) " items per page" }
                        }
                    }
                }
                div {
                    nav class="relative z-0 inline-flex rounded-md shadow-sm -space-x-px" aria-label="Pagination" {
                        a href=(previous_url) class={ "relative inline-flex items-center px-2 py-2 rounded-l-md border border-gray-300 bg-white text-sm font-medium text-gray-500 hover:bg-gray-50" (disabled(!p.has_previous())) } {
                            span.sr-only { "Previous" }
                            (PreEscaped(r#"<svg class="h-5 w-5" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true"><path fill-rule="evenodd" d="M12.707 5.293a1 1 0 010 1.414L9.414 10l3.293 3.293a1 1 0 01-1.414 1.414l-4-4a1 1 0 010-1.414l4-4a1 1 0 011.414 0z" clip-rule="evenodd"></path></svg>"#))
                        }
                        @for page in p.pages() {
                            @match page {
                                Some(n) => {
                                    @let current = n == p.current_page;
                                    a href=(page_url(n)) aria-current=[current.then_some("aria-current")] class={
                                        "relative inline-flex items-center px-4 py-2 border text-sm font-medium "
                                        @if current { "z-10 bg-blue-50 border-blue-500 text-blue-600" }
                                        @else { "bg-white border-gray-300 text-gray-500 hover:bg-gray-50" }
                                    } { (n) }
                                }
                                None => {
                                    span class="relative inline-flex items-center px-4 py-2 border border-gray-300 bg-white text-sm font-medium text-gray-700" { "..." }
                                }
                            }
                        }
                        a href=(next_url) class={ "relative inline-flex items-center px-2 py-2 rounded-r-md border border-gray-300 bg-white text-sm font-medium text-gray-500 hover:bg-gray-50" (disabled(!p.has_next())) } {
                            span.sr-only { "Next" }
                            (PreEscaped(r#"<svg class="h-5 w-5" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true"><path fill-rule="evenodd" d="M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 011.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z" clip-rule="evenodd"></path></svg>"#))
                        }
                    }
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn at(page: i64, total: i64) -> Pagination {
        Pagination {
            current_page: page,
            total_items: total,
            page_size: 10,
            window: 5,
        }
    }

    #[test]
    fn pages_around_the_current_one() {
        assert_eq!(at(1, 30).pages(), [Some(1), Some(2), Some(3)]);
        let numbers =
            |p: Pagination| -> Vec<i64> { p.pages().into_iter().map(|n| n.unwrap_or(0)).collect() };
        assert_eq!(numbers(at(1, 200)), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 0, 20]);
        assert_eq!(
            numbers(at(10, 200)),
            [1, 0, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 0, 20]
        );
        assert_eq!(
            numbers(at(20, 200)),
            [1, 0, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]
        );
        assert_eq!(at(1, 0).last_page(), 0);
    }

    #[test]
    fn reads_and_writes_the_query() {
        let items = query_items(Some("q=a+b%C3%A4&flag&page=3"));
        assert_eq!(
            items,
            [
                ("q".to_string(), Some("a bä".to_string())),
                ("flag".to_string(), None),
                ("page".to_string(), Some("3".to_string()))
            ]
        );
        assert_eq!(
            url_with(
                "/admin/Customers",
                &items,
                &[("page", "4".into()), ("maxItems", "20".into())]
            ),
            "/admin/Customers?q=a%20b%C3%A4&flag&page=4&maxItems=20"
        );
        assert_eq!(Pagination::from_query(&items, 100).unwrap().offset(), 100);
        assert!(Pagination::from_query(&query_items(Some("page=x")), 1).is_err());
        let big = Pagination::from_query(&query_items(Some("maxItems=1000&page=-2")), 1).unwrap();
        assert_eq!((big.page_size, big.current_page), (200, 1));
        assert!(render(&at(1, 5), "/x", &vec![]).into_string().is_empty());
    }
}
