//! The pages, as the IHP app's `Web/View` renders them: the same markup and
//! classes, so `tailwind/app.css` styles both.

use std::collections::HashMap;

use maud::{DOCTYPE, Markup, PreEscaped, html};
use pulldown_cmark::{Event, Parser};
use uuid::Uuid;

use crate::db::{Customer, Invoice, NewCustomer, Producer, Product, WelcomeMessage};
use crate::l10n::{Locale, Text};
use crate::{Flash, Site};

/// The name of the field for bots only, see `honeypot_field`
pub const HONEYPOT: &str = "contact_me_by_fax_only";

/// The fake account a demo's invoices show, whatever the database has, like
/// `demoPaymentDetails`
pub const DEMO_PAYMENT_DETAILS: &str =
    "Bosco Falconeria (demo)\n\nIBAN FI00 0000 0000 0000 00\n\nBIC DEMOFIHH";

pub fn layout(site: &Site, flash: Option<Flash>, content: &Markup) -> Markup {
    let t = |text: Text| text.text(site.locale);
    let title = if site.demo {
        format!("[Demo] {}", t(Text::SiteTitle))
    } else {
        t(Text::SiteTitle).to_string()
    };
    html! {
        (DOCTYPE)
        html lang=(site.locale.code()) {
            head {
                meta charset="utf-8";
                meta name="viewport" content="width=device-width";
                meta property="og:title" content=(t(Text::SiteTitle));
                meta property="og:type" content="website";
                meta property="og:url" content="https://bosco.makela.in/";
                meta property="og:description" content=(t(Text::SiteDescription));
                @if site.demo {
                    meta name="robots" content="noindex, nofollow";
                }
                link rel="stylesheet" href=(site.stylesheet);
                title { (title) }
            }
            body {
                @if site.demo {
                    div.demo-banner role="note" { (t(Text::DemoBanner)) }
                    div.demo-ribbon aria-hidden="true" { "DEMO" }
                }
                div.container {
                    a href="http://www.boscofalconeria.it/" {
                        img src="/img/logo.jpg" alt="Bosco Falconeria logo";
                    }
                    @if let Some(flash) = flash {
                        (flash_message(site, flash))
                    }
                    (content)
                }
            }
        }
    }
}

/// IHP's Tailwind flash messages
fn flash_message(site: &Site, flash: Flash) -> Markup {
    let text = flash.text().text(site.locale);
    if flash.is_error() {
        html! { div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded relative" { (text) } }
    } else {
        html! { div class="bg-green-100 border border-green-500 text-green-900 px-4 py-3 rounded relative" { (text) } }
    }
}

/// Markdown, as the welcome message, the producers' descriptions and the
/// payment instructions are written. HTML in it is shown as text, as MMark
/// in the IHP app doesn't pass it through either.
pub fn markdown(text: &str) -> Markup {
    let events = Parser::new(text).map(|event| match event {
        Event::Html(html) | Event::InlineHtml(html) => Event::Text(html),
        other => other,
    });
    let mut out = String::new();
    pulldown_cmark::html::push_html(&mut out, events);
    PreEscaped(out)
}

/// An amount in cents in the locale's way, like the IHP app's
/// `formatMoney'`: "10,10 €" in Finnish and French, "€10.10" in English.
/// Whole euros leave out the cents, and the space before "€" doesn't break.
pub fn money(locale: Locale, cents: i64) -> String {
    let sign = if cents < 0 { "-" } else { "" };
    let cents = cents.unsigned_abs();
    let (euros, rest) = (cents / 100, cents % 100);
    let number = |separator: char| {
        if rest == 0 {
            euros.to_string()
        } else {
            format!("{euros}{separator}{rest:02}")
        }
    };
    match locale {
        Locale::En => format!("{sign}€{}", number('.')),
        Locale::Fi | Locale::Fr => format!("{sign}{}\u{a0}€", number(',')),
    }
}

pub fn index(site: &Site, message: Option<&WelcomeMessage>) -> Markup {
    let t = |text: Text| text.text(site.locale);
    html! {
        p { (markdown(message.map_or("", |m| m.text.as_str()))) }
        div.front-actions {
            @if message.is_some_and(|m| m.is_ordering_enabled) {
                a.btn-small href="/NewOrder" data-turbolinks="false" { (t(Text::FillOrder)) }
            }
            a.link href="/NewEmail" data-turbolinks="false" { (t(Text::SubscribeToNewsLetter)) }
        }
    }
}

/// What a form shows of what was filled in: the values and, under the
/// fields that weren't accepted, why
#[derive(Debug, Default)]
pub struct CustomerForm {
    pub customer: NewCustomer,
    pub errors: HashMap<&'static str, Text>,
}

/// The order form, empty or as it was sent when something has to be fixed
pub struct OrderForm<'a> {
    /// Where it's sent: `/CreateOrder`, or the admin's
    pub action: &'a str,
    pub producers: &'a [Producer],
    pub products: &'a [Product],
    pub quantities: &'a HashMap<Uuid, i64>,
    pub form: &'a CustomerForm,
    /// Ordered products that can no longer be ordered
    pub unavailable: &'a [Product],
    pub no_products_selected: bool,
}

pub fn order_form(site: &Site, order: &OrderForm) -> Markup {
    let t = |text: Text| text.text(site.locale);
    html! {
        h1 { (t(Text::OrderForm)) }
        form method="POST" action=(order.action) {
            @if !order.unavailable.is_empty() {
                div.unavailable-notice role="alert" {
                    p { (t(Text::NoLongerAvailable)) }
                    ul {
                        @for product in order.unavailable {
                            li { (product.name) " (" (product.package) ")" }
                        }
                    }
                    p { (t(Text::CheckOrderAndResubmit)) }
                }
            }
            @if order.no_products_selected {
                div.unavailable-notice role="alert" {
                    p { (t(Text::NoProductsSelected)) }
                }
            }
            div class="flex flex-wrap" {
                @for producer in order.producers {
                    fieldset {
                        h2 { (producer.name) }
                        p { (markdown(&producer.description)) }
                        div.products {
                            @for product in order.products.iter().filter(|p| p.producer_id == producer.id) {
                                (product_row(site, product, order.quantities.get(&product.id)))
                            }
                        }
                    }
                }
            }
            (customer_field(site, order.form, "firstName", Text::FirstName, "given-name"))
            (customer_field(site, order.form, "lastName", Text::LastName, "family-name"))
            (customer_field(site, order.form, "billingName", Text::BillingName, "organization"))
            (customer_field(site, order.form, "email", Text::Email, "email"))
            (customer_field(site, order.form, "phone", Text::Phone, "tel"))
            (customer_field(site, order.form, "streetAddress", Text::StreetAddress, "street-address"))
            (customer_field(site, order.form, "postalCode", Text::PostalCode, "postal-code"))
            (customer_field(site, order.form, "city", Text::City, "address-level2"))
            (honeypot_field(site))
            input type="submit" value=(t(Text::Submit));
        }
    }
}

/// One product row. On phones: name and package/price on the left, the
/// quantity on the right; on wider screens in columns, see div.product in
/// tailwind/app.css.
fn product_row(site: &Site, product: &Product, quantity: Option<&i64>) -> Markup {
    html! {
        div.product {
            span.product-name { (product.name) }
            span.product-details {
                span.product-package { (product.package) }
                span.product-price { (money(site.locale, i64::from(product.price))) }
            }
            span.product-quantity {
                input type="number" min="0" name=(product.id)
                    value=(quantity.map(i64::to_string).unwrap_or_default()) aria-label=(format!("{}, {}", product.name, product.package));
                " " (Text::Pieces.text(site.locale))
            }
            span.product-description { (product.description) }
        }
    }
}

/// A text field of a customer form with its label and, when it wasn't
/// accepted, why. All but the last name and the name for the invoice are
/// required.
pub fn customer_field(
    site: &Site,
    form: &CustomerForm,
    name: &'static str,
    label: Text,
    autocomplete: &str,
) -> Markup {
    let c = &form.customer;
    let value = match name {
        "firstName" => &c.first_name,
        "lastName" => &c.last_name,
        "billingName" => &c.billing_name,
        "email" => &c.email,
        "phone" => &c.phone,
        "streetAddress" => &c.street_address,
        "postalCode" => &c.postal_code,
        _ => &c.city,
    };
    let error = form.errors.get(name);
    let id = format!("customer_{name}");
    html! {
        div class="flex flex-col my-6 space-y-2" id=(format!("form-group-{id}")) {
            label class="font-medium text-gray-700 " for=(id) { (label.text(site.locale)) }
            input type="text" name=(name) id=(id)
                required[!matches!(name, "lastName" | "billingName")]
                autocomplete=(autocomplete) value=(value)
                class=(field_class(error.is_some()));
            @if let Some(error) = error {
                div.invalid-feedback { (error.text(site.locale)) }
            }
        }
    }
}

fn field_class(invalid: bool) -> &'static str {
    if invalid {
        "form-control is-invalid"
    } else {
        "form-control"
    }
}

/// A field for bots only, in every public form. People don't see it or reach
/// it with the keyboard, screen readers skip it and browsers don't fill it
/// in, but a bot fills in every field, so a form with it filled in is
/// ignored. Off the page by CSS, not type="hidden", which bots leave alone.
fn honeypot_field(site: &Site) -> Markup {
    html! {
        div.honeypot aria-hidden="true" {
            label for=(HONEYPOT) { (Text::LeaveEmpty.text(site.locale)) }
            input type="text" name=(HONEYPOT) id=(HONEYPOT) value="" tabindex="-1" autocomplete="off";
        }
    }
}

pub fn subscribe_form(site: &Site, form: &CustomerForm) -> Markup {
    let t = |text: Text| text.text(site.locale);
    let error = form.errors.get("email");
    html! {
        h1 { (t(Text::SubscribeToNewsLetter)) }
        form method="POST" action="/CreateEmail" {
            (customer_field(site, form, "firstName", Text::FirstName, "given-name"))
            (customer_field(site, form, "lastName", Text::LastName, "family-name"))
            div class="flex flex-col my-6 space-y-2" id="form-group-customer_email" {
                label class="font-medium text-gray-700 " for="customer_email" { (t(Text::Email)) }
                input type="text" name="email" id="customer_email" required
                    value=(form.customer.email)
                    class=(field_class(error.is_some()));
                @if let Some(error) = error {
                    div.invalid-feedback { (error.text(site.locale)) }
                }
            }
            (honeypot_field(site))
            input type="submit" value=(t(Text::Subscribe));
        }
    }
}

/// The customer's names, email, phone and address, a paragraph each
/// (`renderCustomer`)
pub fn customer_block(customer: &Customer) -> Markup {
    html! {
        div class="flex flex-wrap" {
            @for line in customer.name_lines() { p { (line) } }
            p { (customer.email) }
            p { (customer.phone) }
            @for line in customer.address_lines() { p { (line) } }
        }
    }
}

/// The order's lines under their producers, and the total, as table rows
/// (`renderProducer`, `renderTotalSum`)
pub fn invoice_rows(site: &Site, invoice: &Invoice) -> Markup {
    let t = |text: Text| text.text(site.locale);
    html! {
        @for (producer, lines) in &invoice.producers {
            tr { td colspan="4" class="font-bold" { (producer.name) } }
            @for line in lines {
                tr {
                    td.normal { (line.product.name) " (" (line.product.package) ")" }
                    td { (line.quantity) }
                    td { "*" }
                    td { (money(site.locale, i64::from(line.unit_price))) }
                    td { "=" }
                    td.last { (money(site.locale, i64::from(line.unit_price) * i64::from(line.quantity))) }
                }
            }
        }
        tr.font-bold {
            td { (t(Text::Total)) }
            td {} td {} td {} td {}
            td.last { (money(site.locale, invoice.total)) }
        }
    }
}

pub fn invoice(site: &Site, invoice: &Invoice, payment_instruction: Option<&str>) -> Markup {
    let t = |text: Text| text.text(site.locale);
    let order = &invoice.order;
    html! {
        h1 { (t(Text::Invoice)) }
        (customer_block(&order.customer))
        div.table-responsive {
            table.whitespace-nowrap {
                tbody { (invoice_rows(site, invoice)) }
            }
        }
        @match (order.paid_at, order.cancelled_at) {
            (None, None) => {
                h2 { (t(Text::PaymentInstructions)) }
                @if site.demo {
                    p.demo-do-not-pay { (t(Text::DemoDoNotPay)) }
                }
                @if let Some(text) = payment_instruction {
                    (markdown(text))
                }
            }
            (_, Some(_)) => { p.font-bold { (t(Text::InvoiceCancelled)) } }
            (Some(_), None) => { p.font-bold { (t(Text::InvoicePaid)) } }
        }
        p { (t(if site.demo { Text::DemoNoEmail } else { Text::PaymentSentToEmail })) }
    }
}

pub fn not_found(site: &Site) -> Markup {
    let t = |text: Text| text.text(site.locale);
    html! {
        h1 { (t(Text::PageNotFoundTitle)) }
        p { (t(Text::PageNotFound)) }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn money_in_finnish_and_french() {
        for locale in [Locale::Fi, Locale::Fr] {
            assert_eq!(money(locale, 5100), "51\u{a0}€");
            assert_eq!(money(locale, 1010), "10,10\u{a0}€");
            assert_eq!(money(locale, 5), "0,05\u{a0}€");
            assert_eq!(money(locale, 10_000), "100\u{a0}€");
            assert_eq!(money(locale, 100_050), "1000,50\u{a0}€");
            assert_eq!(money(locale, -1010), "-10,10\u{a0}€");
        }
    }

    #[test]
    fn money_in_english() {
        assert_eq!(money(Locale::En, 5100), "€51");
        assert_eq!(money(Locale::En, 1010), "€10.10");
        assert_eq!(money(Locale::En, 5), "€0.05");
        assert_eq!(money(Locale::En, 100_050), "€1000.50");
        assert_eq!(money(Locale::En, -1010), "-€10.10");
    }

    #[test]
    fn markdown_shows_html_as_text() {
        let html = markdown("**Tervetuloa** <script>alert(1)</script>").0;
        assert!(html.contains("<strong>Tervetuloa</strong>"));
        assert!(html.contains("&lt;script&gt;"), "{html}");
    }
}
