//! The admin's order list, `/admin/Orders`: the IHP app's `OrdersAction`
//! (`Admin/Controller/Orders.hs`, `Admin/View/Orders/Index.hs`). A year's
//! orders that weren't cancelled, searched by the customer's name, sorted,
//! and less those already invoiced, paid or delivered if asked. The order
//! pages and the buttons' actions are still the IHP app's.

use std::sync::Arc;

use axum::extract::{Query, State};
use axum::http::{HeaderMap, StatusCode, Uri};
use axum::response::{IntoResponse, Response};
use chrono::{DateTime, Utc};
use maud::{Markup, html};

use crate::admin::{self, Crumb};
use crate::db::{self, ListedOrder, Unhandled};
use crate::permission::Permission;
use crate::views::money;
use crate::{AppState, Result};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OrderBy {
    Name,
    OrderedAt,
    Price,
}

/// What the list shows, from the query string as IHP reads it: the first
/// of a repeated parameter; an empty one is as if it weren't there
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Filter {
    /// None: the last year with orders
    pub year: Option<i32>,
    pub q: String,
    pub order_by: OrderBy,
    pub descending: bool,
    pub exclude: (bool, bool, bool),
}

impl Filter {
    /// None when the year isn't a whole number
    pub fn parse(params: &[(String, String)]) -> Option<Self> {
        let get = |name: &str| {
            params
                .iter()
                .find(|(key, _)| key == name)
                .map(|(_, value)| value.as_str())
                .filter(|value| !value.is_empty())
        };
        // IHP's ParamReader Bool: "on", as checkboxes send it, or "true"
        let flag = |name| get(name).is_some_and(|v| v == "on" || v.eq_ignore_ascii_case("true"));
        let year = match get("year") {
            None => None,
            Some(text) if text.starts_with('+') => return None,
            Some(text) => Some(text.parse().ok()?),
        };
        Some(Self {
            year,
            q: get("q").unwrap_or_default().to_string(),
            order_by: match get("ordering") {
                Some("price") => OrderBy::Price,
                Some("ordered at") => OrderBy::OrderedAt,
                _ => OrderBy::Name,
            },
            descending: get("orderDir") == Some("descending"),
            exclude: (
                flag("excludeInvoiced"),
                flag("excludePaid"),
                flag("excludeDelivered"),
            ),
        })
    }
}

/// `matchesSearch`: the search, trimmed, anywhere in the text, whatever
/// the case; an empty search matches everything
fn matches(q: &str, text: &str) -> bool {
    let q = q.trim();
    q.is_empty() || text.to_lowercase().contains(&q.to_lowercase())
}

/// The orders the list shows, in its order. Searched and sorted here, as
/// in the IHP app: a year's orders are a few hundred at most. Descending is
/// ascending reversed, ties included, as there.
pub fn arrange(orders: Vec<ListedOrder>, filter: &Filter) -> Vec<ListedOrder> {
    let mut orders: Vec<ListedOrder> = orders
        .into_iter()
        .filter(|order| {
            [
                db::words(&[&order.first_name, &order.last_name]),
                order.reverse_name.clone(),
                order.billing_name.clone(),
            ]
            .iter()
            .any(|text| matches(&filter.q, text))
        })
        .collect();
    match filter.order_by {
        OrderBy::Name => orders.sort_by(|a, b| a.reverse_name.cmp(&b.reverse_name)),
        OrderBy::OrderedAt => orders.sort_by_key(|order| order.ordered_at),
        OrderBy::Price => orders.sort_by_key(|order| order.price),
    }
    if filter.descending {
        orders.reverse();
    }
    orders
}

/// IHP's `dateTime`: the time in UTC, which its scripts show in the
/// browser's time zone
pub fn date_time(at: DateTime<Utc>) -> Markup {
    let micros = at.timestamp_subsec_micros();
    let fraction = if micros == 0 {
        String::new()
    } else {
        format!(".{micros:06}").trim_end_matches('0').to_string()
    };
    let iso = format!("{}{fraction}Z", at.format("%Y-%m-%dT%H:%M:%S"));
    html! { time class="date-time" datetime=(iso) { (at.format("%d.%m.%Y, %H:%M")) } }
}

fn selected(on: bool) -> Option<&'static str> {
    on.then_some("selected")
}

struct ListView<'a> {
    orders: &'a [ListedOrder],
    filter: &'a Filter,
    year: i32,
    years: std::ops::RangeInclusive<i32>,
    can_manage: bool,
    can_create: bool,
}

fn list_page(state: &AppState, view: &ListView) -> Markup {
    let filter = view.filter;
    let (invoiced, paid, delivered) = filter.exclude;
    let mut crumbs = vec![Crumb::link("Home", admin::WELCOME), Crumb::text("Orders")];
    if view.can_create {
        crumbs.push(Crumb::link("New", "/admin/NewOrder"));
    }
    let checkbox = |name: &str, on: bool, label: &str| {
        html! {
            label {
                input type="checkbox" name=(name) checked=[on.then_some("checked")] onchange="this.form.submit()";
                (label)
            }
        }
    };
    html! {
        (admin::breadcrumb(&crumbs))
        form method="GET" action="/admin/Orders" {
            label {
                "Year "
                select name="year" onchange="this.form.submit()" {
                    @for year in view.years.clone() {
                        option selected=[selected(year == view.year)] { (year) }
                    }
                }
            }
            label {
                "Sort by "
                select name="ordering" onchange="this.form.submit()" {
                    option selected=[selected(filter.order_by == OrderBy::Name)] { "customer" }
                    option selected=[selected(filter.order_by == OrderBy::OrderedAt)] { "ordered at" }
                    option selected=[selected(filter.order_by == OrderBy::Price)] { "price" }
                }
            }
            label {
                "Sort direction "
                select name="orderDir" onchange="this.form.submit()" {
                    option selected=[selected(!filter.descending)] { "ascending" }
                    option selected=[selected(filter.descending)] { "descending" }
                }
            }
            br;
            (checkbox("excludeInvoiced", invoiced, "Exclude invoiced orders"))
            br;
            (checkbox("excludePaid", paid, "Exclude paid orders"))
            br;
            (checkbox("excludeDelivered", delivered, "Exclude delivered orders"))
            input type="search" placeholder="Search" name="q" value=(filter.q);
        }
        p { (view.orders.len()) " orders" }
        @if !view.orders.is_empty() {
            div.table-responsive {
                table.table {
                    thead {
                        tr {
                            th { "Ordered" } th { "Customer" } th { "Invoiced" }
                            th { "Price" } th { "Paid" } th { "Delivered" }
                        }
                    }
                    tbody {
                        @for order in view.orders {
                            tr {
                                td { a href={ "/admin/ShowOrder?orderId=" (order.id) } { (date_time(order.ordered_at)) } }
                                td { (db::words(&[&order.first_name, &order.last_name])) }
                                td { @if let Some(at) = order.invoiced_at { (date_time(at)) } }
                                td { (money(state.site.locale, order.price)) }
                                td {
                                    @if let Some(at) = order.paid_at {
                                        (date_time(at))
                                    } @else if view.can_manage {
                                        form method="POST" action={ "/admin/UpdateMarkPaidOrder?orderId=" (order.id) } {
                                            input type="submit" class="btn-small" value="Mark as paid";
                                        }
                                    }
                                }
                                td { @if let Some(at) = order.delivered_at { (date_time(at)) } }
                            }
                        }
                    }
                }
            }
        }
    }
}

pub async fn orders(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    uri: Uri,
    Query(params): Query<Vec<(String, String)>>,
) -> Result<Response> {
    let (user, session) =
        match admin::require_permission(&state, &headers, &uri, Permission::SeeOrders).await? {
            Ok(found) => found,
            Err(response) => return Ok(response),
        };
    let Some(filter) = Filter::parse(&params) else {
        return Ok(StatusCode::BAD_REQUEST.into_response());
    };
    let years = db::order_years(&state.db).await?;
    let year = filter.year.unwrap_or(*years.end());
    let exclude = Unhandled {
        invoiced: filter.exclude.0,
        paid: filter.exclude.1,
        delivered: filter.exclude.2,
    };
    let orders = arrange(db::orders_of_year(&state.db, year, exclude).await?, &filter);
    let content = list_page(
        &state,
        &ListView {
            orders: &orders,
            filter: &filter,
            year,
            years,
            can_manage: user.roles.can(Permission::ManageOrders),
            can_create: user.roles.can(Permission::CreateOrders),
        },
    );
    Ok(admin::page(&state, session, &content))
}

#[cfg(test)]
mod tests {
    use super::*;
    use uuid::Uuid;

    fn params(query: &str) -> Vec<(String, String)> {
        query
            .split('&')
            .filter(|pair| !pair.is_empty())
            .map(|pair| {
                let (key, value) = pair.split_once('=').unwrap_or((pair, ""));
                (key.to_string(), value.to_string())
            })
            .collect()
    }

    #[test]
    fn reads_the_query_as_ihp() {
        let filter = Filter::parse(&params("")).unwrap();
        assert_eq!(
            filter,
            Filter {
                year: None,
                q: String::new(),
                order_by: OrderBy::Name,
                descending: false,
                exclude: (false, false, false),
            }
        );
        let filter = Filter::parse(&params(
            "year=2025&year=2026&ordering=price&orderDir=descending&excludePaid=on&excludeInvoiced=TRUE&excludeDelivered=yes&q=aalto",
        ))
        .unwrap();
        assert_eq!(filter.year, Some(2025));
        assert_eq!(filter.order_by, OrderBy::Price);
        assert!(filter.descending);
        assert_eq!(filter.exclude, (true, true, false));
        assert_eq!(filter.q, "aalto");
        assert_eq!(Filter::parse(&params("year=")).unwrap().year, None);
        assert_eq!(
            Filter::parse(&params("ordering=nonsense"))
                .unwrap()
                .order_by,
            OrderBy::Name
        );
        for bad in ["year=abc", "year=+2025", "year=2025.0"] {
            assert_eq!(Filter::parse(&params(bad)), None, "{bad}");
        }
    }

    fn order(first: &str, last: &str, billing: &str, price: i64, day: u32) -> ListedOrder {
        ListedOrder {
            id: Uuid::nil(),
            ordered_at: format!("2026-01-{day:02}T12:00:00Z").parse().unwrap(),
            invoiced_at: None,
            paid_at: None,
            delivered_at: None,
            first_name: first.into(),
            last_name: last.into(),
            reverse_name: db::words(&[last, first]).to_lowercase(),
            billing_name: billing.into(),
            price,
        }
    }

    fn names(orders: &[ListedOrder]) -> Vec<&str> {
        orders.iter().map(|o| o.first_name.as_str()).collect()
    }

    #[test]
    fn searches_and_sorts() {
        let all = || {
            vec![
                order("Äijä", "Öhman", "", 300, 3),
                order("Bertta", "Aalto", "Oliivi Oy", 100, 1),
                order("Eeva", "Aalto", "", 100, 2),
            ]
        };
        let filter = |query: &str| Filter::parse(&params(query)).unwrap();
        assert_eq!(
            names(&arrange(all(), &filter(""))),
            ["Bertta", "Eeva", "Äijä"]
        );
        assert_eq!(
            names(&arrange(all(), &filter("orderDir=descending"))),
            ["Äijä", "Eeva", "Bertta"]
        );
        // Ties keep their order, and descending reverses it
        assert_eq!(
            names(&arrange(all(), &filter("ordering=price"))),
            ["Bertta", "Eeva", "Äijä"]
        );
        assert_eq!(
            names(&arrange(
                all(),
                &filter("ordering=price&orderDir=descending")
            )),
            ["Äijä", "Eeva", "Bertta"]
        );
        assert_eq!(
            names(&arrange(all(), &filter("ordering=ordered at"))),
            ["Bertta", "Eeva", "Äijä"]
        );
        // The full name, the reversed name or the billing name, any case
        assert_eq!(names(&arrange(all(), &filter("q=  "))).len(), 3);
        assert_eq!(names(&arrange(all(), &filter("q= ÖHMAN "))), ["Äijä"]);
        assert_eq!(names(&arrange(all(), &filter("q=aalto eeva"))), ["Eeva"]);
        assert_eq!(names(&arrange(all(), &filter("q=eeva aalto"))), ["Eeva"]);
        assert_eq!(names(&arrange(all(), &filter("q=oliivi"))), ["Bertta"]);
    }

    #[test]
    fn times_as_ihp_writes_them() {
        let at = |text: &str| date_time(text.parse().unwrap()).into_string();
        assert_eq!(
            at("2026-03-01T07:00:00Z"),
            r#"<time class="date-time" datetime="2026-03-01T07:00:00Z">01.03.2026, 07:00</time>"#
        );
        assert_eq!(
            at("2025-12-03T09:30:00.123456Z"),
            r#"<time class="date-time" datetime="2025-12-03T09:30:00.123456Z">03.12.2025, 09:30</time>"#
        );
        assert!(at("2025-03-04T10:11:12.5Z").contains(r#"datetime="2025-03-04T10:11:12.5Z""#));
    }
}
