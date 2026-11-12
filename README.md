# Bosco Falconeria orders

Order form and admin for Bosco Falconeria's olive oil and other Sicilian
products. Customers fill in the order form and get an invoice by email; the
admin at `/admin` manages producers, products, customers, orders, welcome
messages and payment instructions.

Each deployed instance serves one language (Finnish, English or French) and
has its own database, products and orders. A NixOS module (`nix/module.nix`)
runs any number of them on one server.

The site was built with [IHP](https://ihp.digitallyinduced.com/) (Haskell),
and is being moved to Rust (`rust-web/`, with axum, maud and SQLx). The Rust
version now does everything the IHP app does, on the same database: the
public site, the admin, the email worker, the migrations and the scripts.
On a server, `rustWeb.enable` and `rustWorker.enable` make an instance run
the Rust version only (see "The public site in Rust" below). The Rust site
has its own build of the stylesheet and scripts (`nix/rust-static.nix`). The
IHP app is still here: it is the default, and its dev environment is the
project's. It will go once that has a Rust replacement.

## Development

```sh
devenv up        # the site at http://localhost:8000, the IDE at :8001
make seed-dev    # orders, customers and logins to browse, in a fresh dev database
make check       # all the tests, see below
```

The dev site is in Finnish. To try another language, set `APP_LOCALE=fr` (or
`en`) in `.env` and restart `devenv up`. Texts are in
`Application/Localization.hs`; a test fails if a language misses one.

`.env` is read by `.envrc`, so it only takes effect once direnv is allowed
to run it: `direnv allow` in the project directory (again whenever
`.envrc` changes; `direnv status` says "Found RC allowed 0" when it is).
Without direnv, set the variables for one run instead, e.g.
`APP_LOCALE=en devenv up`.

### Tests

- `Test/Main.hs`: unit tests, no database needed.
- `Test/Integration.hs`: tests that use the controllers and a database.
- `nix/tests/module.nix`: evaluates the NixOS module below.
- `nix/tests/migrations.nix`: bootstraps a staging database and migrates a
  copy of production's schema with the deployment's own programs.

`make check` runs all of them as the flake's checks, starting its own
PostgreSQL, and builds the app and the Rust site. A change rebuilds only
what depends on it: a change to `rust-web/` doesn't rebuild the IHP app,
and the Rust site's dependencies are compiled again only when its
`Cargo.lock` changes. It leaves out the app's optimized (`-O2`) build,
which only compiles the same code more slowly; `make check-all` runs that
too. The build's whole log is in `.devenv/check.log`. New files must be
`git add`ed before the flake can see them. A pre-push hook in `.githooks/`
runs `make check-all` before every push (`git push --no-verify` skips it).
Enable it once per clone:

```sh
git config core.hooksPath .githooks
```

## Deployment

`nix/module.nix` is a NixOS module that runs the site as hardened systemd
services, one set per instance: the web server, the worker that sends the
order emails, and the migrations, which run before the other two start. Each
instance has its own PostgreSQL database, owned by a system user of the same
name, so it needs no password. Put nginx with TLS in front. The options are
described in the module.

The server builds the site from a clone in `/srv`, like tccry.fi. The clone's
committed and staged files are used.

### Server configuration

The addresses below are examples; use the real ones.

```nix
{ config, ... }:
{
  imports = [ /srv/bosco/nix/module.nix ];

  services.bosco.instances = {
    fi = {
      baseUrl = "https://tilaus.example.fi";
      locale = "fi";
      # The last migration the database had before this deployment, see
      # "First deploy" below
      minimumRevision = 1760540031;
      smtp = {
        host = "smtp.example.com";
        user = "tilaus@example.fi";
        passwordFile = "/var/lib/secrets/bosco/smtp-password";
      };
    };
    fr = {
      baseUrl = "https://commande.example.fr";
      port = 3301;
      locale = "fr";
      # A new instance: its empty database gets the schema and the fixtures
      bootstrapSchema = true;
      smtp = {
        host = "smtp.example.com";
        user = "commande@example.fr";
        passwordFile = "/var/lib/secrets/bosco/smtp-password-fr";
      };
    };
    staging = {
      flake = builtins.getFlake "git+file:///srv/bosco-staging";
      baseUrl = "https://staging.tilaus.example.fi";
      port = 3302;
      bootstrapSchema = true;
      sendEmails = false;
    };
    # A public demo in English, its public pages in Rust (see below)
    demo = {
      baseUrl = "https://demo.tilaus.example.fi";
      port = 3303;
      locale = "en";
      bootstrapSchema = true;
      demo = true;
      sendEmails = false;
      rustWeb.enable = true; # on port 3403
    };
  };

  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    virtualHosts."tilaus.example.fi" = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:3300";
    };
    virtualHosts."commande.example.fr" = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:3301";
    };
    virtualHosts."staging.tilaus.example.fi" = {
      enableACME = true;
      forceSSL = true;
      basicAuthFile = "/var/lib/secrets/bosco/staging.htpasswd";
      locations."/".proxyPass = "http://127.0.0.1:3302";
      extraConfig = "add_header X-Robots-Tag noindex;";
    };
    # The whole site, in Rust
    virtualHosts."demo.tilaus.example.fi" = {
      enableACME = true;
      forceSSL = true;
      locations = config.services.bosco.instances.demo.rustWeb.nginxLocations;
    };
  };
  security.acme.acceptTerms = true;
  security.acme.defaults.email = "...";
  networking.firewall.allowedTCPPorts = [ 80 443 ];

  # Download IHP and GHC ready-built instead of compiling them on the server
  nix.settings.extra-substituters = [ "https://digitallyinduced.cachix.org" ];
  nix.settings.extra-trusted-public-keys = [
    "digitallyinduced.cachix.org-1:y+wQvrnxQ+PdEsCt91rmvv39qRCYzEgGQaldK26hCKE="
  ];
  nix.gc.automatic = true;

  services.postgresqlBackup = {
    enable = true;
    databases = [ "bosco_fi" "bosco_fr" ];
  };
}
```

The ports start from 3300, so the site can share a server with tccry.fi
(3200).

### Email

The worker sends each order's invoice through the instance's SMTP server:
`smtp.encryption` is `starttls` by default (usually port 587, the default), or
`tls` (usually 465). Without `sendEmails`, as on staging, it only logs which
order it would have emailed (`journalctl -u bosco-staging-worker`).

The sender is `mail.from` and replies go to `mail.replyTo`, by default
`postmaster@boscofalconeria.it` and `oliveoil@boscofalconeria.it`. The SMTP
account must be allowed to send as the sender, and its domain's SPF and DKIM
records should cover the SMTP server, or the emails end up as spam. The
pages' `og:url` is the instance's `baseUrl`.

### Demo

An instance with `demo = true` (`APP_DEMO=1`) is a public demo. Every page,
the admin included, shows a banner and a "DEMO" ribbon, page titles start
with "[Demo]", the invoice says not to pay it and search engines are asked
not to index the site. A demo must have `sendEmails = false`; the module and
the server both refuse to start one that sends emails. Its invoices always
show fake payment details (IBAN `FI00 0000 0000 0000 00`, from
`Application/Demo.hs`) whatever the database holds, and its admin can't
create, edit or delete payment instructions, so no visitor can put a real
account on the demo's invoices. For the same reason the welcome message's
text is fixed: visitors can open and close ordering, but not create, delete
or reword messages.

The demo's admin login page has one-click logins for everyone: an admin, a
delivery person and a promoter (`Application/Demo.hs`). Their users
are made on first use with a random password nobody knows, so they can't be
locked by typing wrong passwords, and their passwords can't be changed. Your
own admin login, made with `CreateUser`, works as usual.

Every night at 03:00 (`demoReset.time`), `bosco-<name>-reset-demo` resets
the demo's data in one transaction (`Application/DemoData.hs`, or with
`rustWeb.enable` its Rust port `rust-web/src/demo_data.rs`, which makes the
same data). It reloads
the catalog in the instance's language, `Fixtures.<locale>.sql` (so far
`Fixtures.en.sql`), or else the Finnish `Fixtures.sql`. The catalogs have
the same ids and prices, so a change to one belongs in the others too. It
adds fake payment details and makes up four seasons of orders, with more
each year, returning customers and prices a few percent lower each year
back. Logins are kept. The newest orders are still waiting to be invoiced,
paid or delivered. The orders differ every day. The script refuses to run
unless `APP_DEMO` is on. A new demo has no orders until the first reset,
so run it once after the first deploy:

```sh
systemctl start bosco-demo-reset-demo
```

### The public site in Rust

With `rustWeb.enable = true`, an instance runs the public pages, the welcome
message, the order form, the invoices and the newsletter form, from
`rust-web/` in Rust, as `bosco-<name>-rust-web` on port `rustWeb.port`
(`port` + 100 by default), in place of the IHP app's web server
`bosco-<name>`, which then doesn't run. It uses the instance's database as
the IHP app did, as the same user, and the IHP app's email worker works as
before, also for orders made in Rust. It also runs the whole
admin (`/admin/…`), the demo's one-click logins included. It reads and
writes IHP's session cookie with the instance's session key and checks and
makes IHP's password hashes, so a login in either app is a login in the
other, and logins, lockouts and changed passwords carry over both ways.
It serves the static files too, so nginx sends it everything with
`rustWeb.nginxLocations`, as for the demo above. The instance's migrations
then run with the Rust site's `bosco-migrate`, and a demo's nightly reset
with its `bosco-reset-demo`. Without it, an instance runs all of these in
IHP as before. See `rust-web/README.md` for the few differences.

Try it on the demo first. `journalctl -u bosco-demo-rust-web` shows its
requests. To go back, set `rustWeb.enable = false` and point nginx's
`locations."/"` at the IHP app's port again: the IHP app starts, on the
same data.

With `rustWorker.enable = true`, the instance's email worker,
`bosco-<name>-worker`, runs `bosco-worker` from `rust-web/` instead of IHP's
`RunJobs`, with the same SMTP settings. It sends the same order emails from
the same jobs, with a readable plain-text version and the `Date` and
`Message-ID` headers IHP's left out. Jobs carry over either way, so
switching back and forth loses none. `journalctl -u bosco-<name>-worker`
logs each email sent or failed. It works without `rustWeb.enable`, and
the other way round. With both, nothing of the IHP app runs on the
instance: its site, worker, migrations and demo reset are all Rust's.

### Users and roles

A login has one or more roles, and may do whatever any of them allows
(`Application/Permission.hs`):

- admin: everything;
- deliverer: sees orders and their details, takes orders for customers in
  the admin and marks orders delivered;
- promoter: sees orders and their details, the email lists and all ordered
  products (how much of each was ordered, per year), and edits
  the shop's texts, e.g. to translate them: products' names, descriptions
  and packages, producers' subjects and descriptions. Not prices, producer
  names, or which products and producers there are and are shown.

Every change to a product's or producer's texts, by anyone, is kept with who
made it, when, and the text before and after (`text_changes`). A product's
and a producer's page in the admin list them, newest first.

Only an admin marks orders invoiced or paid, cancels them, emails invoices
again and manages the shop. On an instance with `rustWeb.enable`,
`bosco-<name>-create-user` makes logins, as root:

```sh
read -rs ADMIN_PASSWORD && export ADMIN_PASSWORD
ADMIN_EMAIL=someone@example.com ROLES=deliverer,promoter bosco-fi-create-user
```

Without it, `CreateUser` does, on the server as the instance's user:

```sh
read -rs ADMIN_PASSWORD && export ADMIN_PASSWORD
ADMIN_EMAIL=someone@example.com ROLES=deliverer,promoter run-script Application/Script/CreateUser.hs
```

`ROLES` is `admin` when not given. An existing login's roles change in SQL,
e.g. `UPDATE users SET is_promoter = true WHERE email = '...'`.

### Secrets

None of these go into the Nix store, which every user of the server can read.

- `/var/lib/secrets/bosco/smtp-password` (one per instance): the SMTP
  password, readable by root only. The worker gets it as a systemd
  credential.
- `/var/lib/secrets/bosco/staging.htpasswd`: the password for the staging
  site, made with `htpasswd -c <file> <user>`. nginx reads it, so
  `root:nginx`, mode 0640.
- `/var/lib/bosco-<instance>/session.aes`: the key the session cookies are
  signed with. Made at the first start; removing it logs everyone out.

### First deploy

1. Find the last migration the current database has. If it has a
   `schema_migrations` table, that lists them:
   `SELECT max(revision) FROM schema_migrations`. Otherwise it is the newest
   file in `Application/Migration/` that was applied by hand. Set it as the
   `fi` instance's `minimumRevision` (1760540031 above).
2. Clone the repository to `/srv/bosco`, add the configuration above and run
   `sudo nixos-rebuild switch`. The first build takes a while and needs
   several gigabytes of disk. The `fi` migrations fail on its new empty
   database, so that site doesn't start yet.
3. Copy the data from the old server, as the new owner:

   ```sh
   pg_dump --no-owner --no-acl <old database> > bosco.sql  # on the old server
   sudo -u bosco_fi psql bosco_fi < bosco.sql             # on the new one
   ```

4. Put the SMTP password in place. To keep the admins logged in, use the old
   `Config/client_session_key.aes` as `/var/lib/bosco-fi/session.aes`.
5. Start it: `sudo systemctl restart bosco-fi bosco-fi-worker`. The migrations
   after `minimumRevision` run first, see `journalctl -u bosco-fi-migrate`.

### A new language

An instance like `fr` above starts with an empty database. With
`bootstrapSchema = true` it gets the schema and the fixtures by itself:
Finnish producers and products to translate in its admin, and a welcome
message to replace. It has no admin logins yet; copy the existing ones, with
their passwords, from the Finnish instance:

```sh
sudo -u postgres sh -c 'pg_dump --data-only --table=users bosco_fi | psql bosco_fr'
```

### Staging

The staging instance runs a second clone, `/srv/bosco-staging`, so a branch can
be tried before it goes live:

```sh
git -C /srv/bosco-staging switch <branch>
sudo nixos-rebuild switch
```

Its empty database gets the schema and the fixtures by itself. It doesn't send
emails. For real content, load a copy of production's dump as above. It holds
the customers' names, addresses and phone numbers, so keep the password on the
staging site.

### Publishing

```sh
cd /srv/bosco
git pull
sudo nixos-rebuild switch
```

New migrations run before the sites and workers restart. If one fails, they
don't start: see `journalctl -u bosco-fi-migrate`. Logs are in
`journalctl -u bosco-fi -u bosco-fi-worker`.

`sudo nixos-rebuild switch --rollback` returns to the previous version of the
code, but not of the database. After a migration, roll back only to a version
that works with the migrated schema.
