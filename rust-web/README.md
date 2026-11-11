# Bosco's public site in Rust

The IHP app's `Web/` ported to Rust ([axum](https://github.com/tokio-rs/axum),
[maud](https://maud.lambda.xyz/), [SQLx](https://github.com/launchbadge/sqlx)):
the welcome message, the order form, an order's invoice and the newsletter
form, in Finnish, English or French, demo mode included; the whole admin,
`Admin/`; and the email worker, IHP's job runner with
`Web/Job/EmailOrder.hs`. It uses the IHP app's PostgreSQL database as it is,
so both can run at once, and either app's worker emails the invoices of
either app's orders, as each order saves its email job the same way.

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
  and `Admin/View/Orders`: the list, an order's page and its buttons, a new
  order, and all ordered products
- `src/admin_texts.rs`: the welcome messages and payment instructions, from
  `Admin/Controller/WelcomeMessages.hs` and `PaymentInstructions.hs`, with
  IHP's generated forms
- `src/query.rs`: reading an address's query string as IHP does
- `src/admin_customers.rs`: the customers and the email lists, from
  `Admin/Controller/Customers.hs`
- `src/admin_producers.rs`: the producers, from
  `Admin/Controller/Producers.hs`, with the text history of
  `Application/TextHistory.hs`
- `src/admin_products.rs`: the products, from `Admin/Controller/Products.hs`
- `src/bin/bosco-create-user.rs`: makes a login, from
  `Application/Script/CreateUser.hs`
- `src/demo_data.rs`, `src/bin/bosco-reset-demo.rs`: the demo's nightly
  reset, from `Application/DemoData.hs`: the same made-up orders as the IHP
  app's for the same day and time
- `src/bin/bosco-seed-dev.rs`: fills a dev database with orders and logins
  to browse, from `Application/Script/SeedDevData.hs`
- `src/bin/bosco-migrate.rs`: runs the new migrations, as IHP's `migrate`;
  the deployment's migration test (`nix/tests/migrations.nix`) runs with
  both
- `src/static_files.rs`: the IHP app's static files, by their content's
  hash, as dates in the Nix store say nothing
- `src/admin_password.rs`: changing one's password, from
  `Admin/Controller/Passwords.hs`
- `src/admin_forms.rs`: the admin's form fields, as IHP's `formFor` makes
  them
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
- **Changing one's password** says what's wrong (the old password, the
  confirmation, or the new one's length and characters); IHP said only
  "Passwords do not meet the requirements". The rules are IHP's.
- **Static files** without a version in their address (the logo, the
  favicon) are asked about again on each visit, a 304 when unchanged; IHP
  let browsers keep them for a year. IHP's own development scripts
  (`/static/helpers.js`, `/static/vendor/…`) aren't served: the pages use
  `prod.js`, which has them.
- **A failed migration** stops `bosco-migrate`; IHP's `migrate` went on to
  the next, which then failed too.
- **A login without a password field** is answered with 400; IHP's was a
  500. The login form always sends one.
- **The admin's order list and all ordered products** count years from
  midnight UTC; IHP's started at midnight in the database's time zone
  (e.g. Finnish time), but listed the years by UTC. Only orders in the
  first hours of a year can differ.
- **A year that isn't a number** in the order list's address is answered
  with 400; IHP's was a 500.
- **The customer list** shows each name once, as IHP's did, but as the
  name's newest customer (the latest email and phone); IHP showed
  whichever the database gave.
- **The email lists** have a breadcrumb back to the start, as the other
  admin pages.
- **A product's form** lists the producers as the order form does, Bosco
  Falconeria first, then A to Z (IHP's in the database's order), and says
  what to fix in plain words; a product of a producer that doesn't exist
  is refused there, where IHP's was a 500.
- **Payment instructions** are listed oldest first; IHP listed them in
  whatever order the database gave, which is the same until one is edited.
- **The admin's wording and markup are tidied** where IHP's generator left
  quirks: "Create welcome message" (was "Create Welcomemessage"), "Welcome
  message created" (was "WelcomeMessage created"), sentence case in the
  menu and breadcrumbs, "1 order", "Please log in", a delete link that
  isn't inside another link, and no empty `id`s or `placeholder`s. The
  login fields have labels for screen readers.
- **The admin's lists are on one page**: IHP's were in pages of 50 (with
  `?page=` and `?maxItems=`), which only the customers ever reached, and
  those are easier to find from one page, A to Z.
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

With `rustWeb.enable` and `rustWorker.enable`, nothing of the IHP app runs
on an instance. Its code is still the source of the static files
(`prod.css`, `prod.js`), of IHP's base schema (`IHPSchema.sql`) and of the
dev environment; removing it is a later step.
