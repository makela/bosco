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
# Each instance <name> has three services, the programs of rust-web/, all
# running as the system user that owns the instance's PostgreSQL database
# (bosco_<name> by default):
#
# - bosco-<name>-migrate runs the migrations (bosco-migrate), before the
#   other two start
# - bosco-<name> is the site and its admin (bosco-web), on port; nginx sends
#   everything to it (nginxLocations)
# - bosco-<name>-worker sends the order emails (bosco-worker)
#
# A demo has a fourth, bosco-<name>-reset-demo, started every night by its
# timer. Their state, the session key, is in /var/lib/bosco-<name>.
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
          default = config.flake.packages.${system}.rust-web;
          defaultText = lib.literalExpression "flake.packages.\${system}.rust-web";
          description = "The programs: the site, the email worker, the migrations and the demo reset (nix/rust-web.nix).";
        };

        nginxLocations = lib.mkOption {
          type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
          readOnly = true;
          default."/".proxyPass = "http://${listenAddressOf config.host config.port}";
          defaultText = lib.literalExpression ''{ "/".proxyPass = "http://127.0.0.1:3300"; }'';
          description = ''
            The instance's nginx locations: everything to the site, the static
            files included. For an nginx virtual host:
            locations = config.services.bosco.instances.<name>.nginxLocations;
          '';
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

          package = removed;
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

        # The IHP app's options, from when the Rust site was its replacement
        # beside it. Kept, hidden, so an older configuration is told what to
        # change rather than that an option doesn't exist.
        rustWeb = {
          enable = lib.mkOption {
            type = lib.types.nullOr lib.types.bool;
            default = null;
            visible = false;
            description = "Was: run the Rust site instead of the IHP app's. It's the only one now.";
          };
          port = removed;
          package = removed;
          nginxLocations = lib.mkOption {
            type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
            readOnly = true;
            visible = false;
            default = config.nginxLocations;
            description = "The same as nginxLocations.";
          };
        };
        rustWorker.enable = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          visible = false;
          description = "Was: run the Rust email worker instead of the IHP app's. It's the only one now.";
        };
        migratePackage = removed;
        rtsFlags = removed;
      };
    };

  # A removed option: null unless an older configuration still sets it
  removed = lib.mkOption {
    type = lib.types.nullOr lib.types.raw;
    default = null;
    visible = false;
  };

  # What an older configuration still sets, with what to do instead
  removedOptions = instance: {
    "rustWeb.port" = { value = instance.rustWeb.port; instead = "set port, which the site listens on now"; };
    "rustWeb.package" = { value = instance.rustWeb.package; instead = "set package"; };
    "migratePackage" = { value = instance.migratePackage; instead = "remove it: package has bosco-migrate"; };
    "demoReset.package" = { value = instance.demoReset.package; instead = "remove it: package has bosco-reset-demo"; };
    "rtsFlags" = { value = instance.rtsFlags; instead = "remove it: there's no GHC runtime"; };
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
    MemoryDenyWriteExecute = true;
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
      # With the user: without one, SQLx doesn't take the service's
      databaseUrl = "postgresql:///${instance.database}?host=/run/postgresql&user=${instance.database}";
      # The catalog in the instance's language, Fixtures.<locale>.sql, or
      # the Finnish one, Fixtures.sql, when there's none
      fixtures =
        let
          localized = "${instance.flake}/db/Fixtures.${instance.locale}.sql";
        in
        if builtins.pathExists localized then localized else "${instance.flake}/db/Fixtures.sql";

      after = [
        "network.target"
        "postgresql.service"
        # Creates the databases and users in newer NixOS versions
        "postgresql-setup.service"
      ];
      requires = [
        "postgresql.service"
        migrate
      ];

      # What every program reads
      environment = {
        DATABASE_URL = databaseUrl;
        APP_LOCALE = instance.locale;
        APP_DEMO = if instance.demo then "1" else "0";
        # The admin's order pages say when emails are off, and a demo
        # refuses to send any
        SEND_EMAILS = if instance.sendEmails then "1" else "0";
        RUST_LOG = "info";
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

      # Its stylesheet, scripts and images (nix/rust-static.nix), with their
      # package's hash as the version in their addresses, so a new one isn't
      # taken from the browser's cache
      static = instance.flake.packages.${system}.rust-static;

      smtpPassword = instance.sendEmails && instance.smtp.passwordFile != null;
    in
    {
      "bosco-${name}-migrate" = {
        description = "Bosco Falconeria migrations (${name})";
        inherit after;
        requires = [ "postgresql.service" ];
        environment = {
          DATABASE_URL = databaseUrl;
          IHP_MIGRATION_DIR = "${instance.flake}/db/Migration/";
          MINIMUM_REVISION = toString instance.minimumRevision;
        }
        // lib.optionalAttrs instance.bootstrapSchema {
          IHP_SCHEMA = "${instance.flake}/db/IHPSchema.sql";
          APP_SCHEMA = "${instance.flake}/db/Schema.sql";
          APP_FIXTURES = fixtures;
        };
        serviceConfig = serviceConfig // {
          Type = "oneshot";
          # Stays active, so a new version's migrations run on the next switch
          RemainAfterExit = true;
          ExecStartPre = [ keygen ] ++ lib.optional instance.bootstrapSchema (lib.getExe bootstrap);
          ExecStart = "${instance.package}/bin/bosco-migrate";
        };
      };

      "bosco-${name}" = {
        description = "Bosco Falconeria site (${name})";
        wantedBy = [ "multi-user.target" ];
        after = after ++ [ migrate ];
        inherit requires;
        environment = environment // {
          ADDR = listenAddressOf instance.host instance.port;
          STATIC_DIR = "${static}";
          # In the stylesheet's and scripts' addresses, /static/app.css?v=…
          ASSET_VERSION = lib.substring 0 32 (baseNameOf "${static}");
          # The admin's login is in a session cookie signed with this key,
          # as the IHP app's was, so logins carried over
          IHP_SESSION_SECRET_FILE = "${state}/session.aes";
          IHP_BASEURL = instance.baseUrl;
        };
        serviceConfig = serviceConfig // {
          ExecStart = lib.getExe instance.package;
          Restart = "always";
        };
      };

      "bosco-${name}-worker" = {
        description = "Bosco Falconeria email worker (${name})";
        wantedBy = [ "multi-user.target" ];
        after = after ++ [ migrate ];
        inherit requires;
        environment =
          environment
          // {
            MAIL_FROM = instance.mail.from;
          }
          // lib.optionalAttrs (instance.mail.replyTo != null) {
            MAIL_REPLY_TO = instance.mail.replyTo;
          }
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
            ExecStart = "${instance.package}/bin/bosco-worker";
            Restart = "always";
          }
          // lib.optionalAttrs smtpPassword {
            LoadCredential = "smtp-password:${instance.smtp.passwordFile}";
          };
      };
    }
    // lib.optionalAttrs instance.demo {
      # Started by its timer, see demoTimers
      "bosco-${name}-reset-demo" = {
        description = "Bosco Falconeria demo data reset (${name})";
        after = after ++ [ migrate ];
        inherit requires;
        environment = environment // {
          APP_FIXTURES = fixtures;
        };
        serviceConfig = serviceConfig // {
          Type = "oneshot";
          ExecStart = "${instance.package}/bin/bosco-reset-demo";
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
  addresses = lib.mapAttrsToList (_: listenAddress) instances;
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
        message = "services.bosco.instances: each instance needs its own port (${lib.concatStringsSep ", " addresses}).";
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
        {
          assertion = instance.rustWeb.enable != false && instance.rustWorker.enable != false;
          message = "services.bosco.instances.${name}: the IHP app is gone, so rustWeb.enable and rustWorker.enable can't be false. Remove them.";
        }
      ]
      ++ lib.mapAttrsToList (option: removed: {
        assertion = removed.value == null;
        message = "services.bosco.instances.${name}.${option} is gone with the IHP app: ${removed.instead}.";
      }) (removedOptions instance)
      ) instances
    );

    warnings = lib.concatLists (
      lib.mapAttrsToList (
        name: instance:
        lib.optional (instance.rustWeb.enable == true || instance.rustWorker.enable == true)
          "services.bosco.instances.${name}: rustWeb.enable and rustWorker.enable are no longer needed, the site is only in Rust now; remove them."
      ) instances
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

    systemd.services = lib.mkMerge (lib.mapAttrsToList services instances);
    systemd.timers = lib.mapAttrs' demoTimers (lib.filterAttrs (_: instance: instance.demo) instances);

    # bosco-<name>-create-user makes a login on the instance's database, as
    # the instance's user, with bosco-create-user from package:
    #   read -rs ADMIN_PASSWORD && export ADMIN_PASSWORD
    #   ADMIN_EMAIL=someone@example.com ROLES=deliverer,promoter bosco-fi-create-user
    environment.systemPackages = lib.mapAttrsToList (
      name: instance:
      pkgs.writeShellScriptBin "bosco-${name}-create-user" ''
        exec ${pkgs.util-linux}/bin/runuser -u ${instance.database} -- \
          env DATABASE_URL="postgresql:///${instance.database}?host=/run/postgresql&user=${instance.database}" \
          ${instance.package}/bin/bosco-create-user
      ''
    ) instances;
  };
}
