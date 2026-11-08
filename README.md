# Bosco Falconeria orders

Order form and admin for Bosco Falconeria's olive oil and other Sicilian
products, built with [IHP](https://ihp.digitallyinduced.com/). Customers fill
in the order form and get an invoice by email; the admin at `/admin` manages
producers, products, orders, welcome messages and payment instructions.

Each deployed instance serves one language (Finnish, English or French) and
has its own database, products and orders.

## Development

```sh
devenv up        # the site at http://localhost:8000, the IDE at :8001
make seed-dev    # orders, customers and logins to browse, in a fresh dev database
make check       # all the tests, see below
```

The dev site is in Finnish. To try another language, set `APP_LOCALE=fr` (or
`en`) in `.env` and restart `devenv up`. Texts are in
`Application/Localization.hs`; a test fails if a language misses one.

### Tests

- `Test/Main.hs`: unit tests, no database needed.
- `Test/Integration.hs`: tests that use the controllers and a database.
- `nix/tests/module.nix`: evaluates the NixOS module below.
- `nix/tests/migrations.nix`: bootstraps a staging database and migrates a
  copy of production's schema with the deployment's own programs.

`make check` runs all of them through `nix flake check`, starting its own
PostgreSQL. New files must be `git add`ed before the flake can see them. A
pre-push hook in `.githooks/` runs `make check` before every push (`git push
--no-verify` skips it). Enable it once per clone:

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

The sender is `postmaster@boscofalconeria.it` with replies to
`oliveoil@boscofalconeria.it` (`Web/Mail/Orders/Order.hs`), so the SMTP
account must be allowed to send as it, and the domain's SPF and DKIM records
should cover the SMTP server, or the emails end up as spam.

### Demo

An instance with `demo = true` (`APP_DEMO=1`) is a public demo. Every page,
the admin included, shows a banner and a "DEMO" ribbon, page titles start
with "[Demo]", the invoice says not to pay it and search engines are asked
not to index the site. A demo must have `sendEmails = false`; the module and
the server both refuse to start one that sends emails. Its invoices always
show fake payment details (IBAN `FI00 0000 0000 0000 00`, from
`Application/Demo.hs`) whatever the database holds, and its admin can't
create, edit or delete payment instructions, so no visitor can put a real
account on the demo's invoices.

The demo's admin login page has one-click logins for everyone: an admin and
a delivery person who only sees orders (`Application/Demo.hs`). Their users
are made on first use with a random password nobody knows, so they can't be
locked by typing wrong passwords, and their passwords can't be changed. Your
own admin login, made with `CreateUser`, works as usual.

Every night at 03:00 (`demoReset.time`), `bosco-<name>-reset-demo` resets
the demo's data in one transaction (`Application/DemoData.hs`). It reloads
the catalog from `Fixtures.sql`, adds fake payment details and makes up four
seasons of orders, with more each year, returning customers and prices a
few percent lower each year back. Logins are kept. The newest orders are
still waiting to be invoiced, paid or delivered. The orders differ every
day. The script refuses to run unless `APP_DEMO` is on. A new demo has no
orders until the first reset, so run it once after the first deploy:

```sh
systemctl start bosco-demo-reset-demo
```

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
