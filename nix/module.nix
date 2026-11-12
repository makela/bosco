# NixOS module running copies of the site as hardened systemd services, one
# set per instance. Each instance serves one language and has its own
# database, products and orders. Import it in the server's configuration.nix
# from a clone of this repository, and put a reverse proxy such as nginx in
# front (see the README):
#
#   imports = [ /srv/bosco/nix/module.nix ];
#   services.bosco.instances = {
#     fi = {
#       baseUrl = "https://tilaus.example.fi";
#       locale = "fi";
#       smtp = {
#         host = "smtp.example.com";
#         user = "tilaus@example.fi";
#         passwordFile = "/var/lib/secrets/bosco/smtp-password";
#       };
#     };
#     fr = {
#       baseUrl = "https://commande.example.fr";
#       port = 3301;
#       locale = "fr";
#       smtp = { ... };
#     };
#     staging = {
#       flake = builtins.getFlake "git+file:///srv/bosco-staging";
#       baseUrl = "https://staging.tilaus.example.fi";
#       port = 3302;
#       bootstrapSchema = true;
#       sendEmails = false;
#     };
#     demo = {
#       baseUrl = "https://demo.tilaus.example.fi";
#       port = 3303;
#       bootstrapSchema = true;
#       demo = true;
#       sendEmails = false;
#     };
#   };
#
# Each instance <name> has three services, all running as the system user
# that owns the instance's PostgreSQL database (bosco_<name> by default):
#
# - bosco-<name>-migrate runs the migrations, before the other two start
# - bosco-<name> is the web server, on the socket bosco-<name>.socket
# - bosco-<name>-worker runs the jobs that send the order emails
#
# Their state, the session key, is in /var/lib/bosco-<name>. With
# rustWeb.enable, bosco-<name>-rust-web runs the whole site in Rust instead of
# bosco-<name>, with the same session key, and nginx sends everything to it
# (rustWeb.nginxLocations). With
# rustWorker.enable, bosco-<name>-worker runs the Rust email worker instead
# of IHP's.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;

  instances = lib.filterAttrs (_: instance: instance.enable) config.services.bosco.instances;

  instanceOptions =
    { name, config, ... }:
    {
      options = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether to run this instance.";
        };

        flake = lib.mkOption {
          type = lib.types.raw;
          default = builtins.getFlake "git+file://${toString ../.}";
          defaultText = lib.literalExpression ''builtins.getFlake "git+file:///srv/bosco"'';
          description = ''
            The checkout to run: its packages, migrations and schema. By default the
            clone this module was imported from. When the module comes from a flake
            input instead, set this to that input.
          '';
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = config.flake.packages.${system}.optimized-prod-server;
          defaultText = lib.literalExpression "flake.packages.\${system}.optimized-prod-server";
          description = "The site, with the RunProdServer and RunJobs programs and the static files.";
        };

        migratePackage = lib.mkOption {
          type = lib.types.package;
          default = config.flake.packages.${system}.migrate;
          defaultText = lib.literalExpression "flake.packages.\${system}.migrate";
          description = "IHP's migrate program, without rustWeb.enable.";
        };

        baseUrl = lib.mkOption {
          type = lib.types.str;
          example = "https://tilaus.example.fi";
          description = "Public address of the site, for links in pages and emails.";
        };

        locale = lib.mkOption {
          type = lib.types.enum [
            "fi"
            "en"
            "fr"
          ];
          default = "fi";
          description = "Language of the site and its emails (APP_LOCALE). The admin pages are in English.";
        };

        host = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1";
          description = "Address to listen on. The default only accepts local connections, e.g. from a reverse proxy.";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 3300;
          description = "Port to listen on (instance ${name}).";
        };

        database = lib.mkOption {
          type = lib.types.str;
          default = "bosco_${name}";
          description = ''
            Name of the PostgreSQL database, and of the system user that owns it and
            runs the services. The database is created if it doesn't exist.
          '';
        };

        minimumRevision = lib.mkOption {
          type = lib.types.ints.unsigned;
          default = 0;
          example = 1760540031;
          description = ''
            Migrations up to this revision are taken as applied, for a database
            whose schema_migrations table doesn't list the migrations it has.
          '';
        };

        bootstrapSchema = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Load the schema and the fixtures into the database when it has no
            tables, e.g. for a new staging instance.
          '';
        };

        sendEmails = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Whether the worker sends the order emails. Without, it only logs them,
            e.g. for a staging instance with a copy of the customers.
          '';
        };

        demo = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Whether this is a public demo (APP_DEMO). Every page, the admin
            included, gets a banner and a "DEMO" ribbon, titles start with
            [Demo], the invoice says not to pay it and search engines are
            asked not to index the site. Its admin login page offers one-click
            logins, and its data is reset every night (see demoReset). Needs
            sendEmails = false.
          '';
        };

        demoReset = {
          time = lib.mkOption {
            type = lib.types.str;
            default = "*-*-* 03:00:00";
            example = "*-*-* 04:30:00";
            description = ''
              When a demo's data is reset (systemd OnCalendar, the server's time
              zone): the catalog from the fixtures, fake payment details and a few
              seasons of made-up orders. Logins are kept. Run it now with
              systemctl start bosco-<name>-reset-demo.
            '';
          };

          package = lib.mkOption {
            type = lib.types.package;
            default = config.flake.packages.${system}.script-ResetDemo;
            defaultText = lib.literalExpression "flake.packages.\${system}.script-ResetDemo";
            description = "The ResetDemo program (Application/Script/ResetDemo.hs), without rustWeb.enable.";
          };
        };

        mail = {
          from = lib.mkOption {
            type = lib.types.str;
            default = "postmaster@boscofalconeria.it";
            example = "Example Shop <orders@example.com>";
            description = ''
              Who the order emails are from (MAIL_FROM): an address, or a name and
              an address. The SMTP account must be allowed to send as it.
            '';
          };
          replyTo = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = "Olive Oil Bosco Falconeria <oliveoil@boscofalconeria.it>";
            example = "Example Shop <shop@example.com>";
            description = "Where replies to the order emails go (MAIL_REPLY_TO), or null for the sender.";
          };
        };

        smtp = {
          host = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "smtp.example.com";
            description = "SMTP server the order emails are sent through. Needed when sendEmails is on.";
          };

          port = lib.mkOption {
            type = lib.types.port;
            default = 587;
            description = "Port of the SMTP server.";
          };

          encryption = lib.mkOption {
            type = lib.types.enum [
              "starttls"
              "tls"
              "none"
            ];
            default = "starttls";
            description = "starttls (usually port 587), tls (usually 465), or none for a local relay without a login.";
          };

          user = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "SMTP login, or null for a server that needs none.";
          };

          passwordFile = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "/var/lib/secrets/bosco/smtp-password";
            description = ''
              File with the SMTP password, outside the Nix store. Only the worker can
              read it, through systemd credentials. Needed with a user.
            '';
          };
        };

        rustWeb = {
          enable = lib.mkEnableOption ''
            the public site in Rust (rust-web/) next to the IHP app, on the same
            database: the welcome message, the order form, the invoices and the
            newsletter form, the whole admin, which shares IHP's session, and
            the static files, in place of the IHP app's web server, which then
            doesn't run. nginx sends everything to it with nginxLocations
          '';

          port = lib.mkOption {
            type = lib.types.port;
            default = config.port + 100;
            defaultText = lib.literalExpression "port + 100";
            description = "Port the Rust site listens on, at host (instance ${name}).";
          };

          package = lib.mkOption {
            type = lib.types.package;
            default = config.flake.packages.${system}.rust-web;
            defaultText = lib.literalExpression "flake.packages.\${system}.rust-web";
            description = "The Rust programs, the site and the email worker (nix/rust-web.nix).";
          };

          nginxLocations = lib.mkOption {
            type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
            readOnly = true;
            default."/".proxyPass = "http://${listenAddressOf config.host config.rustWeb.port}";
            defaultText = lib.literalExpression ''{ "/".proxyPass = "http://127.0.0.1:3400"; }'';
            description = ''
              The instance's nginx locations with the Rust site: everything to it,
              the static files included, as it serves the whole site. For an nginx
              virtual host:
              locations = config.services.bosco.instances.<name>.rustWeb.nginxLocations;
            '';
          };
        };

        rustWorker.enable = lib.mkEnableOption ''
          the email worker in Rust (bosco-worker, from rustWeb.package) instead
          of IHP's RunJobs, as the same bosco-<name>-worker service with the same
          settings. It sends the same emails from the same job table, so either
          can take over the other's jobs
        '';

        rtsFlags = lib.mkOption {
          type = lib.types.str;
          default = "-A96m -n4m -N";
          description = "Options of the GHC runtime (GHCRTS).";
        };
      };
    };

  listenAddressOf =
    host: port: if lib.hasInfix ":" host then "[${host}]:${toString port}" else "${host}:${toString port}";
  listenAddress = instance: listenAddressOf instance.host instance.port;

  # The services only read from the Nix store, write to their state directory,
  # and talk to PostgreSQL, the reverse proxy and, from the worker, SMTP.
  hardening = {
    CapabilityBoundingSet = "";
    NoNewPrivileges = true;
    PrivateDevices = true;
    PrivateTmp = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    ProtectClock = true;
    ProtectHostname = true;
    ProtectKernelLogs = true;
    ProtectKernelModules = true;
    ProtectKernelTunables = true;
    ProtectControlGroups = true;
    ProtectProc = "invisible";
    RestrictAddressFamilies = [
      "AF_UNIX"
      "AF_INET"
      "AF_INET6"
    ];
    RestrictNamespaces = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    LockPersonality = true;
    # No MemoryDenyWriteExecute: the GHC runtime may need executable memory
    SystemCallArchitectures = "native";
    SystemCallFilter = [
      "@system-service"
      "~@privileged"
    ];
    UMask = "0077";
  };

  services =
    name: instance:
    let
      state = "/var/lib/bosco-${name}";
      migrate = "bosco-${name}-migrate.service";
      databaseUrl = "postgresql:///${instance.database}?host=/run/postgresql";
      # The user too: without one, SQLx doesn't take the service's
      rustDatabaseUrl = "${databaseUrl}&user=${instance.database}";
      # The catalog in the instance's language, Fixtures.<locale>.sql, or
      # the Finnish one, Fixtures.sql, when there's none
      fixtures =
        let
          localized = "${instance.flake}/Application/Fixtures.${instance.locale}.sql";
        in
        if builtins.pathExists localized then localized else "${instance.flake}/Application/Fixtures.sql";

      after = [
        "network.target"
        "postgresql.service"
        # Creates the databases and users in newer NixOS versions
        "postgresql-setup.service"
      ];

      environment = {
        IHP_ENV = "Production";
        IHP_BASEURL = instance.baseUrl;
        IHP_REQUEST_LOGGER_IP_ADDR_SOURCE = "FromHeader";
        DATABASE_URL = databaseUrl;
        IHP_SESSION_SECRET_FILE = "${state}/session.aes";
        PORT = toString instance.port;
        GHCRTS = instance.rtsFlags;
        APP_LOCALE = instance.locale;
        APP_DEMO = if instance.demo then "1" else "0";
        # Every program reads it at startup (Config.hs), and a demo refuses
        # to start without SEND_EMAILS=0
        SEND_EMAILS = if instance.sendEmails then "1" else "0";
        MAIL_FROM = instance.mail.from;
      }
      // lib.optionalAttrs (instance.mail.replyTo != null) {
        MAIL_REPLY_TO = instance.mail.replyTo;
      };

      serviceConfig = hardening // {
        User = instance.database;
        Group = instance.database;
        StateDirectory = "bosco-${name}";
        StateDirectoryMode = "0700";
        WorkingDirectory = state;
      };

      keygen = pkgs.writeShellScript "bosco-${name}-keygen" ''
        # The key session cookies are signed with. Remove it to log everyone out.
        if [ ! -s ${state}/session.aes ]; then
          ${lib.getExe pkgs.openssl} rand 96 > ${state}/session.aes
        fi
      '';

      bootstrap = pkgs.callPackage ./bootstrap-schema.nix {
        postgresql = config.services.postgresql.package;
      };

      smtpPassword = instance.sendEmails && instance.smtp.passwordFile != null;
    in
    {
      "bosco-${name}-migrate" = {
        description = "Bosco Falconeria migrations (${name})";
        inherit after;
        requires = [ "postgresql.service" ];
        environment = {
          # SQLx, of bosco-migrate, needs the user; psql takes it either way
          DATABASE_URL = if instance.rustWeb.enable then rustDatabaseUrl else databaseUrl;
          IHP_MIGRATION_DIR = "${instance.flake}/Application/Migration/";
          MINIMUM_REVISION = toString instance.minimumRevision;
        }
        // lib.optionalAttrs instance.bootstrapSchema {
          IHP_SCHEMA = "${instance.flake.inputs.ihp}/ihp-schema-compiler/data/IHPSchema.sql";
          APP_SCHEMA = "${instance.flake}/Application/Schema.sql";
          APP_FIXTURES = fixtures;
        };
        serviceConfig = serviceConfig // {
          Type = "oneshot";
          # Stays active, so a new version's migrations run on the next switch
          RemainAfterExit = true;
          ExecStartPre = [ keygen ] ++ lib.optional instance.bootstrapSchema (lib.getExe bootstrap);
          # With the Rust site, its bosco-migrate, which does the same
          ExecStart =
            if instance.rustWeb.enable then
              "${instance.rustWeb.package}/bin/bosco-migrate"
            else
              "${instance.migratePackage}/bin/migrate";
        };
      };

      "bosco-${name}-worker" = {
        description = "Bosco Falconeria email worker${lib.optionalString instance.rustWorker.enable " in Rust"} (${name})";
        wantedBy = [ "multi-user.target" ];
        after = after ++ [ migrate ];
        requires = [
          "postgresql.service"
          migrate
        ];
        environment =
          (
            if instance.rustWorker.enable then
              {
                DATABASE_URL = rustDatabaseUrl;
                inherit (environment) APP_LOCALE APP_DEMO SEND_EMAILS MAIL_FROM;
                RUST_LOG = "info";
              }
              // lib.optionalAttrs (environment ? MAIL_REPLY_TO) {
                inherit (environment) MAIL_REPLY_TO;
              }
            else
              environment
          )
          // lib.optionalAttrs instance.sendEmails {
            SMTP_HOST = instance.smtp.host;
            SMTP_PORT = toString instance.smtp.port;
            SMTP_ENCRYPTION = instance.smtp.encryption;
          }
          // lib.optionalAttrs (instance.sendEmails && instance.smtp.user != null) {
            SMTP_USER = instance.smtp.user;
          }
          // lib.optionalAttrs smtpPassword {
            SMTP_PASSWORD_FILE = "%d/smtp-password";
          };
        serviceConfig =
          serviceConfig
          // {
            ExecStart =
              if instance.rustWorker.enable then
                "${instance.rustWeb.package}/bin/bosco-worker"
              else
                "${instance.package}/bin/RunJobs";
            Restart = "always";
          }
          // lib.optionalAttrs instance.rustWorker.enable {
            MemoryDenyWriteExecute = true;
          }
          // lib.optionalAttrs smtpPassword {
            LoadCredential = "smtp-password:${instance.smtp.passwordFile}";
          };
      };
    }
    # The IHP app's web server, unless the Rust site serves the whole site
    // lib.optionalAttrs (!instance.rustWeb.enable) {
      "bosco-${name}" = {
        description = "Bosco Falconeria site (${name})";
        wantedBy = [ "multi-user.target" ];
        after = after ++ [ migrate ];
        requires = [
          "postgresql.service"
          migrate
          "bosco-${name}.socket"
        ];
        environment = environment // {
          IHP_SYSTEMD = "1";
        };
        serviceConfig = serviceConfig // {
          Type = "notify";
          ExecStart = "${instance.package}/bin/RunProdServer";
          Restart = "always";
          KillSignal = "SIGINT";
          WatchdogSec = "60";
          Sockets = "bosco-${name}.socket";
        };
      };
    }
    // lib.optionalAttrs instance.rustWeb.enable {
      "bosco-${name}-rust-web" =
        let
          # The IHP app's static files: the logo, and prod.css with the same
          # version in its address as the IHP app gives it, so a new one
          # isn't taken from the browser's cache
          static = instance.flake.packages.${system}.static;
          assetVersion = lib.substring 0 32 (baseNameOf "${static}");
        in
        {
          description = "Bosco Falconeria public site in Rust (${name})";
          wantedBy = [ "multi-user.target" ];
          after = after ++ [ migrate ];
          requires = [
            "postgresql.service"
            migrate
          ];
          environment = {
            DATABASE_URL = rustDatabaseUrl;
            ADDR = listenAddressOf instance.host instance.rustWeb.port;
            APP_LOCALE = instance.locale;
            APP_DEMO = if instance.demo then "1" else "0";
            # The admin's order pages say when emails are off
            SEND_EMAILS = if instance.sendEmails then "1" else "0";
            STATIC_DIR = "${static}";
            STYLESHEET = "/prod.css?v=${assetVersion}";
            # The admin's stylesheet and scripts, /static/app.css?v=…
            ASSET_VERSION = assetVersion;
            # The admin's login is in IHP's session cookie, with its key
            IHP_SESSION_SECRET_FILE = "${state}/session.aes";
            IHP_BASEURL = instance.baseUrl;
            RUST_LOG = "info";
          };
          serviceConfig = serviceConfig // {
            ExecStart = lib.getExe instance.rustWeb.package;
            Restart = "always";
            # Unlike the GHC runtime, it needs no executable memory
            MemoryDenyWriteExecute = true;
          };
        };
    }
    // lib.optionalAttrs instance.demo {
      # Started by its timer, see demoTimers
      "bosco-${name}-reset-demo" = {
        description = "Bosco Falconeria demo data reset (${name})";
        after = after ++ [ migrate ];
        requires = [
          "postgresql.service"
          migrate
        ];
        # With the Rust site, the Rust program (bosco-reset-demo), which
        # makes the same data
        environment =
          if instance.rustWeb.enable then
            {
              DATABASE_URL = rustDatabaseUrl;
              APP_DEMO = "1";
              APP_FIXTURES = fixtures;
            }
          else
            environment
            // {
              APP_FIXTURES = fixtures;
            };
        serviceConfig = serviceConfig // {
          Type = "oneshot";
          ExecStart =
            if instance.rustWeb.enable then
              "${instance.rustWeb.package}/bin/bosco-reset-demo"
            else
              "${instance.demoReset.package}/bin/ResetDemo";
        };
      };
    };

  demoTimers =
    name: instance:
    lib.nameValuePair "bosco-${name}-reset-demo" {
      description = "Nightly Bosco Falconeria demo data reset (${name})";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = instance.demoReset.time;
        # Catches up on a reset missed while the server was off
        Persistent = true;
      };
    };

  # Values two instances must not share
  duplicates = values: lib.length values != lib.length (lib.unique values);
  addresses = lib.concatLists (
    lib.mapAttrsToList (
      _: instance:
      if instance.rustWeb.enable then
        [ (listenAddressOf instance.host instance.rustWeb.port) ]
      else
        [ (listenAddress instance) ]
    ) instances
  );
  databases = lib.mapAttrsToList (_: instance: instance.database) instances;
in
{
  options.services.bosco.instances = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule instanceOptions);
    default = { };
    description = "Copies of the site to run, by name.";
  };

  config = lib.mkIf (instances != { }) {
    assertions = [
      {
        assertion = !duplicates addresses;
        message = "services.bosco.instances: each instance, and its Rust site, needs its own port (${lib.concatStringsSep ", " addresses}).";
      }
      {
        assertion = !duplicates databases;
        message = "services.bosco.instances: each instance needs its own database (${lib.concatStringsSep ", " databases}).";
      }
    ]
    ++ lib.concatLists (
      lib.mapAttrsToList (name: instance: [
        {
          assertion = !(instance.demo && instance.sendEmails);
          message = "services.bosco.instances.${name}: a demo must not send emails, set sendEmails = false.";
        }
        {
          assertion = !instance.sendEmails || instance.smtp.host != null;
          message = "services.bosco.instances.${name}: set smtp.host, or sendEmails = false.";
        }
        {
          assertion = (instance.smtp.user == null) == (instance.smtp.passwordFile == null);
          message = "services.bosco.instances.${name}: set both smtp.user and smtp.passwordFile, or neither.";
        }
        {
          assertion = instance.smtp.encryption != "none" || instance.smtp.user == null;
          message = "services.bosco.instances.${name}: an SMTP login needs encryption (starttls or tls).";
        }
      ]) instances
    );

    users.users = lib.mapAttrs' (
      _: instance:
      lib.nameValuePair instance.database {
        isSystemUser = true;
        group = instance.database;
      }
    ) instances;
    users.groups = lib.mapAttrs' (_: instance: lib.nameValuePair instance.database { }) instances;

    # Each instance's user owns its database and logs in over the local socket
    # without a password
    services.postgresql = {
      enable = true;
      ensureDatabases = databases;
      ensureUsers = map (database: {
        name = database;
        ensureDBOwnership = true;
      }) databases;
    };

    systemd.sockets = lib.mapAttrs' (
      name: instance:
      lib.nameValuePair "bosco-${name}" {
        description = "Bosco Falconeria site socket (${name})";
        wantedBy = [ "sockets.target" ];
        socketConfig = {
          ListenStream = listenAddress instance;
          Accept = false;
        };
      }
    ) (lib.filterAttrs (_: instance: !instance.rustWeb.enable) instances);

    systemd.services = lib.mkMerge (lib.mapAttrsToList services instances);
    systemd.timers = lib.mapAttrs' demoTimers (lib.filterAttrs (_: instance: instance.demo) instances);

    # bosco-<name>-create-user makes a login on the instance's database, as
    # the instance's user, with bosco-create-user from rustWeb.package:
    #   read -rs ADMIN_PASSWORD && export ADMIN_PASSWORD
    #   ADMIN_EMAIL=someone@example.com ROLES=deliverer,promoter bosco-fi-create-user
    environment.systemPackages = lib.mapAttrsToList (
      name: instance:
      pkgs.writeShellScriptBin "bosco-${name}-create-user" ''
        exec ${pkgs.util-linux}/bin/runuser -u ${instance.database} -- \
          env DATABASE_URL="postgresql:///${instance.database}?host=/run/postgresql&user=${instance.database}" \
          ${instance.rustWeb.package}/bin/bosco-create-user
      ''
    ) (lib.filterAttrs (_: instance: instance.rustWeb.enable) instances);
  };
}
