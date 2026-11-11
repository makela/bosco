# Bosco's public site in Rust

The IHP app's `Web/` ported to Rust ([axum](https://github.com/tokio-rs/axum),
[maud](https://maud.lambda.xyz/), [SQLx](https://github.com/launchbadge/sqlx)):
the welcome message, the order form, an order's invoice and the newsletter
form, in Finnish, English or French, demo mode included. It uses the IHP
app's PostgreSQL database as it is, so both can run at once: the admin and
the job worker stay in IHP, and the worker emails the invoices of orders
made here too, as each order saves its email job like the IHP app does.

The addresses are the IHP app's (`/`, `/NewOrder`, `/CreateOrder`,
`/ShowOrder?orderId=…`, `/NewEmail`, `/CreateEmail`), so links in sent
emails keep working, and the markup and classes are the same, so
`tailwind/app.css` styles it.

- `src/lib.rs`: the routes and what they do
- `src/db.rs`: the queries, on the tables of `Application/Schema.sql`
- `src/views.rs`: the pages, from `Web/View`
- `src/validate.rs`: the forms' checks, from `Application/Helper/Controller.hs`
- `src/l10n.rs`: the texts, generated from `Application/Localization.hs`

## Use

With `devenv up` running in the project (the database, and Tailwind writing
`static/app.css`), in another terminal:

```sh
cd rust-web
nix develop path:.
DATABASE_URL="postgres:///app?host=$(ls -d /tmp/devenv-*/postgres)" cargo run
# http://127.0.0.1:8002
```

`APP_LOCALE` and `APP_DEMO` work as for the IHP app; `ADDR`, `STATIC_DIR`
and `STYLESHEET` are in `src/main.rs`.

`./test.sh` runs the tests against a throwaway PostgreSQL. Each test gets a
database of its own with IHP's base schema and `Application/Schema.sql`, so a
change to the schema shows here at once. Most are the IHP app's own tests of
`Web/` (`Test/Web`), ported.

## Differences from the IHP app

- **Notices** ("Order sent" and the like) are kept in a cookie by name
  rather than in IHP's session, so the two apps don't share them.
- **No JavaScript**: the pages don't load `prod.js` (Turbolinks); the public
  pages don't need it.
- **Redirects** go to `/` instead of `/Orders` (the same page), with 303.
- **A quantity that isn't a whole number** is answered with 400; IHP showed
  its error page. Browsers don't send one from the form.
- **Markdown** is rendered by pulldown-cmark rather than MMark; HTML in it
  is shown as text in both.
- **Pages not found** have the site's layout.

Not done yet: a NixOS module to run it in place of the IHP app's public
pages, and the admin.
