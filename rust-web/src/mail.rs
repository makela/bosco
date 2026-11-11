//! The order email, from the IHP app's `Web/Mail/Orders/Order.hs`: the
//! invoice and the payment instructions, sent to the customer when they
//! order. Sent by the worker, see `worker.rs`.

use lettre::Message;
use lettre::message::{Mailbox, MultiPart};
use maud::{Markup, html};

use crate::db::{Invoice, words};
use crate::l10n::{Locale, Text};
use crate::views::{markdown, money};

/// The sender, and where replies go, as in the IHP app
const FROM: &str = "postmaster@boscofalconeria.it";
const REPLY_TO: &str = "Olive Oil Bosco Falconeria <oliveoil@boscofalconeria.it>";

/// The order email to the customer, in HTML and as plain text. An error is
/// for the job's last_error.
pub fn order_mail(
    locale: Locale,
    invoice: &Invoice,
    payment_instruction: Option<&str>,
) -> Result<Message, String> {
    let customer = &invoice.order.customer;
    let name = words(&[&customer.first_name, &customer.last_name]);
    let address = customer.email.trim();
    let to = Mailbox::new(
        (!name.is_empty()).then_some(name),
        address
            .parse()
            .map_err(|e| format!("the customer's email {address:?}: {e}"))?,
    );
    Message::builder()
        .from(FROM.parse().expect("FROM is an address"))
        .reply_to(REPLY_TO.parse().expect("REPLY_TO is an address"))
        .to(to)
        .subject(Text::SiteTitle.text(locale))
        // One of this machine's, which spam filters look for
        .message_id(None)
        .multipart(MultiPart::alternative_plain_html(
            plain(locale, invoice, payment_instruction),
            html(locale, invoice, payment_instruction).into_string(),
        ))
        .map_err(|e| e.to_string())
}

/// The IHP app's email, with inline styles as email programs want them
pub fn html(locale: Locale, invoice: &Invoice, payment_instruction: Option<&str>) -> Markup {
    let t = |text: Text| text.text(locale);
    let customer = &invoice.order.customer;
    html! {
        h1 { (t(Text::Invoice)) }
        div {
            @for line in customer.name_lines() { p { (line) } }
            p { (customer.email) }
            p { (customer.phone) }
            @for line in customer.address_lines() { p { (line) } }
        }
        table style="white-space: nowrap" {
            tbody {
                @for (producer, lines) in &invoice.producers {
                    tr { td colspan="4" style="font-weight: bold" { (producer.name) } }
                    @for line in lines {
                        tr {
                            td { (line.product.name) " (" (line.product.package) ")" }
                            td { (line.quantity) }
                            td { "*" }
                            td { (money(locale, i64::from(line.unit_price))) }
                            td { "=" }
                            td style="text-align: right" {
                                (money(locale, i64::from(line.unit_price) * i64::from(line.quantity)))
                            }
                        }
                    }
                }
                tr style="font-weight: bold" {
                    td { (t(Text::Total)) }
                    td {} td {} td {} td {}
                    td style="text-align: right" { (money(locale, invoice.total)) }
                }
            }
        }
        h2 { (t(Text::PaymentInstructions)) }
        @if let Some(text) = payment_instruction { (markdown(text)) }
    }
}

/// The same as plain text, for email programs that don't show HTML. The IHP
/// app sent its HTML with the tags taken out, which ran the lines together.
pub fn plain(locale: Locale, invoice: &Invoice, payment_instruction: Option<&str>) -> String {
    let t = |text: Text| text.text(locale);
    let customer = &invoice.order.customer;
    let mut out = format!("{}\n\n", t(Text::Invoice));
    for line in customer.name_lines() {
        out += &format!("{line}\n");
    }
    out += &format!("{}\n{}\n", customer.email, customer.phone);
    for line in customer.address_lines() {
        out += &format!("{line}\n");
    }
    for (producer, lines) in &invoice.producers {
        out += &format!("\n{}\n", producer.name);
        for line in lines {
            out += &format!(
                "{} ({}): {} * {} = {}\n",
                line.product.name,
                line.product.package,
                line.quantity,
                money(locale, i64::from(line.unit_price)),
                money(
                    locale,
                    i64::from(line.unit_price) * i64::from(line.quantity)
                ),
            );
        }
    }
    out += &format!("\n{}: {}\n", t(Text::Total), money(locale, invoice.total));
    out += &format!("\n{}\n", t(Text::PaymentInstructions));
    if let Some(text) = payment_instruction {
        out += &format!("\n{}\n", text.trim());
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::{Customer, Order, OrderLine, Producer, Product};
    use uuid::Uuid;

    fn invoice() -> Invoice {
        let bosco = Producer {
            id: Uuid::nil(),
            name: "Bosco Falconeria".into(),
            description: String::new(),
        };
        let line = |name: &str, package: &str, price, quantity| OrderLine {
            quantity,
            unit_price: price,
            product: Product {
                id: Uuid::nil(),
                producer_id: bosco.id,
                name: name.into(),
                description: String::new(),
                package: package.into(),
                price,
                ordering: None,
            },
        };
        Invoice {
            order: Order {
                ordered_at: chrono::DateTime::UNIX_EPOCH,
                invoiced_at: None,
                paid_at: None,
                delivered_at: None,
                cancelled_at: None,
                customer: Customer {
                    email: "anna@example.com".into(),
                    phone: "040 123 4567".into(),
                    first_name: "Anna-Liisa".into(),
                    last_name: "Virtanen".into(),
                    street_address: "Testikatu 1".into(),
                    postal_code: "00100".into(),
                    city: "Helsinki".into(),
                    billing_name: "Oliivi Oy".into(),
                },
            },
            producers: vec![(
                bosco.clone(),
                vec![
                    line("Olive oil", "3 l", 5100, 1),
                    line("Honey", "250 g", 1010, 3),
                ],
            )],
            total: 8130,
        }
    }

    #[test]
    fn html_is_the_ihp_apps_email() {
        let html = html(Locale::En, &invoice(), Some("Pay to **FI12 3456**")).into_string();
        assert!(
            html.starts_with("<h1>Invoice</h1><div><p>Oliivi Oy</p><p>Anna-Liisa Virtanen</p>")
        );
        assert!(html.contains(
            "<p>anna@example.com</p><p>040 123 4567</p><p>Testikatu 1</p><p>00100 Helsinki</p>"
        ));
        assert!(html.contains(
            r#"<tr><td colspan="4" style="font-weight: bold">Bosco Falconeria</td></tr>"#
        ));
        assert!(html.contains(
            r#"<tr><td>Honey (250 g)</td><td>3</td><td>*</td><td>€10.10</td><td>=</td><td style="text-align: right">€30.30</td></tr>"#
        ));
        assert!(html.contains(r#"<td style="text-align: right">€81.30</td>"#));
        assert!(
            html.contains("<h2>Payment instructions</h2><p>Pay to <strong>FI12 3456</strong></p>"),
            "{html}"
        );
    }

    #[test]
    fn plain_text_has_a_line_for_each_thing() {
        let text = plain(Locale::Fi, &invoice(), Some("Maksa tilille **FI12 3456**"));
        assert_eq!(
            text,
            "Lasku\n\
             \n\
             Oliivi Oy\n\
             Anna-Liisa Virtanen\n\
             anna@example.com\n\
             040 123 4567\n\
             Testikatu 1\n\
             00100 Helsinki\n\
             \n\
             Bosco Falconeria\n\
             Olive oil (3 l): 1 * 51\u{a0}€ = 51\u{a0}€\n\
             Honey (250 g): 3 * 10,10\u{a0}€ = 30,30\u{a0}€\n\
             \n\
             Yhteensä: 81,30\u{a0}€\n\
             \n\
             Maksuohjeet\n\
             \n\
             Maksa tilille **FI12 3456**\n"
        );
    }

    #[test]
    fn the_mail_goes_to_the_customer_by_name() {
        let message = order_mail(Locale::En, &invoice(), None).unwrap();
        let headers = String::from_utf8(message.formatted()).unwrap();
        assert!(
            headers.contains("To: \"Anna-Liisa Virtanen\" <anna@example.com>"),
            "{headers}"
        );
        assert!(headers.contains("From: postmaster@boscofalconeria.it"));
        assert!(
            headers
                .contains("Reply-To: \"Olive Oil Bosco Falconeria\" <oliveoil@boscofalconeria.it>")
        );
        assert!(headers.contains("Subject: Bosco Falconeria Olive Oil Order"));
        assert!(headers.contains("multipart/alternative"));
        assert!(headers.contains("Message-ID: <"));
    }

    #[test]
    fn a_bad_address_is_an_error_for_the_job() {
        let mut invoice = invoice();
        invoice.order.customer.email = "not an address".into();
        let error = order_mail(Locale::En, &invoice, None).unwrap_err();
        assert!(error.contains("\"not an address\""), "{error}");
    }
}
