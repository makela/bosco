# Bosco's public site in Rust

The IHP app's `Web/` ported to Rust ([axum](https://github.com/tokio-rs/axum),
[maud](https://maud.lambda.xyz/), [SQLx](https://github.com/launchbadge/sqlx)):
the welcome message, the order form, an order's invoice and the newsletter
form, in Finnish, English or French, demo mode included; the admin's login,
logout, welcome page (its menu) and orders (the list, an order's page and
its buttons); and the email worker, IHP's job runner with
`Web/Job/EmailOrder.hs`. It uses the IHP app's PostgreSQL database as it is,
so both can run at once: the rest of the admin stays in IHP, and either
app's worker emails the invoices of either app's orders, as each order saves
its email job the same way.

The login uses IHP's session cookie, `SESSION`, encrypted and signed as IHP
does with the IHP app's key, and IHP's password hashes, so a login here
lets one into the IHP app's admin pages, the two show each other's flash
messages, and a login IHP sent here goes back to the admin page asked for.

The addresses are the IHP app's (`/`, `/NewOrder`, `/CreateOrder`,
`/ShowOrder?orderId=…`, `/NewEmail`, `/CreateEmail`), so links in sent
emails keep working, and the markup and classes are the same, so
`tailwind/app.css` styles it.

- `src/lib.rs`: the routes and what they do
- `src/db.rs`: the queries, on the tables of `Application/Schema.sql`
- `src/views.rs`: the pages, from `Web/View`
- `src/validate.rs`: the forms' checks, from `Application/Helper/Controller.hs`
- `src/l10n.rs`: the texts, generated from `Application/Localization.hs`
- `src/worker.rs`, `src/bin/bosco-worker.rs`: the email worker, working the
  job table as IHP's job runner does
- `src/mail.rs`: the order email, from `Web/Mail/Orders/Order.hs`
- `src/admin.rs`: the admin's login and logout, from
  `Admin/Controller/Sessions.hs` and IHP's sessions controller, its layout,
  the login check every admin page makes (`require_user`), and the welcome
  page, from `Admin/Controller/Static.hs`
- `src/admin_orders.rs`: the admin's orders, from `Admin/Controller/Orders.hs`
  and `Admin/View/Orders`: the list, an order's page, and its buttons
- `src/permission.rs`: what each role may do, from
  `Application/Permission.hs`
- `src/session.rs`, `src/skein_mac.rs`: IHP's session cookie
  (clientsession's AES-256-CTR and Skein-MAC-512-256)
- `src/password.rs`: IHP's password hashes (pwstore-fast's)

## Use

`devenv up` in the project runs the site at http://localhost:8003 next to
the IHP app's (8000), on the same database, and builds and restarts it when
its code changes (the `rust-web` process in the project's `flake.nix`). The
first build takes a few minutes. Its log is the process's in `devenv up`.

The admin's login at http://localhost:8003/admin/NewSession uses the IHP
app's session key in `Config/client_session_key.aes`, so a login there works
at http://localhost:8000/admin/ too (cookies don't tell ports apart, but
`localhost` and `127.0.0.1` are different hosts to them).

`APP_LOCALE` and `APP_DEMO` work as for the IHP app; `ADDR`, `STATIC_DIR`
and `STYLESHEET` are in `src/main.rs`. To run it by hand (with `devenv up`
stopped, or another `ADDR`), in the project's dev shell (`nix develop`),
which has the database's `DATABASE_URL`:

```sh
cd rust-web
nix develop path:. -c cargo run
```

The email worker, instead of `devenv up`'s IHP worker or beside it, the same
way:

```sh
SEND_EMAILS=0 nix develop path:. -c cargo run --bin bosco-worker
```

With `SEND_EMAILS=0` it only logs the emails. Its SMTP settings are the IHP
app's, see `src/bin/bosco-worker.rs`.

`./test.sh` runs the tests against a throwaway PostgreSQL. Each test gets a
database of its own with IHP's base schema and `Application/Schema.sql`, so a
change to the schema shows here at once. Most are the IHP app's own tests of
`Web/` (`Test/Web`), ported.

## Differences from the IHP app

- **Notices** ("Order sent" and the like) are kept in a cookie by name
  rather than in IHP's session, so the two apps don't share them.
- **No JavaScript** on the public pages: they don't load `prod.js`
  (Turbolinks), which they don't need. The admin's login page does, as the
  IHP app's admin pages.
- **Redirects** go to `/` instead of `/Orders` (the same page), with 303.
- **A quantity that isn't a whole number** is answered with 400; IHP showed
  its error page. Browsers don't send one from the form.
- **Markdown** is rendered by pulldown-cmark rather than MMark; HTML in it
  is shown as text in both.
- **Pages not found** have the site's layout.
- **The email's plain-text version** has a line for each thing; IHP's ran
  them together. The email has `Date` and `Message-ID` headers, which IHP's
  left out.
- **The worker does one job at a time**; IHP's does up to 16 at once. Orders
  come one by one, so it doesn't show.
- **A login without a password field** is answered with 400; IHP's was a
  500. The login form always sends one.
- **The order list's years** start and end at midnight UTC; IHP's started
  at midnight in the database's time zone (e.g. Finnish time), but listed
  the years by UTC. Only orders in the first hours of a year can differ.
- **A year that isn't a number** in the order list's address is answered
  with 400; IHP's was a 500.
- **Access denied** (a login whose roles don't allow the page) is a page in
  the admin's layout; IHP showed its own branded page. Both are 403.
- **After "Mark as paid"** the admin goes back to the page they were on
  (the `Referer`) by its path only, so always on this site; IHP took the
  whole address.
- **A login's wrong passwords** are counted in the database (`+ 1`), so two
  at once both count; IHP counted from what it had read.

On a server, the NixOS module runs the site next to the IHP app with
`rustWeb.enable`, and the worker instead of IHP's with `rustWorker.enable`,
see "The public site in Rust" in the project's README. Its
package is `nix/rust-web.nix`, and `nix flake check` (the `rust-web-tests`
check) runs these tests too.

Not done yet: the rest of the admin: a new order from the admin, all
ordered products, customers, producers, products, welcome messages, payment
instructions, email lists and changing one's password.
