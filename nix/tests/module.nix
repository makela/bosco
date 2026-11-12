# Evaluates nix/module.nix with a Finnish, a French and a staging instance,
# as in the README, and checks the users, databases and services it makes. Nothing is built or started, so no virtual machine is needed.
{
  pkgs,
  nixosSystem,
  self,
}:
let
  lib = pkgs.lib;
  system = pkgs.stdenv.hostPlatform.system;

  evaluate =
    instances:
    (nixosSystem {
      modules = [
        ../module.nix
        {
          nixpkgs.hostPlatform = system;
          boot.isContainer = true;
          system.stateVersion = "25.05";
          services.bosco.instances = lib.mapAttrs (_: instance: { flake = self; } // instance) instances;
        }
      ];
    }).config;

  smtp = {
    host = "smtp.example.com";
    user = "tilaus@example.fi";
    passwordFile = "/var/lib/secrets/bosco/smtp-password";
  };

  server = evaluate {
    fi = {
      baseUrl = "https://tilaus.example.fi";
      locale = "fi";
      minimumRevision = 1760540031;
      inherit smtp;
    };
    fr = {
      baseUrl = "https://commande.example.fr";
      port = 3301;
      locale = "fr";
      bootstrapSchema = true;
      smtp = smtp // {
        user = "commande@example.fr";
        passwordFile = "/var/lib/secrets/bosco/smtp-password-fr";
      };
    };
    staging = {
      baseUrl = "https://staging.tilaus.example.fi";
      port = 3302;
      bootstrapSchema = true;
      sendEmails = false;
    };
  };

  services = server.systemd.services;
  ours = lib.filterAttrs (name: _: lib.hasPrefix "bosco-" name);
  instanceNames = [
    "fi"
    "fr"
    "staging"
  ];
  servicesOf = names: lib.concatMap (name: [ "bosco-${name}" "bosco-${name}-migrate" "bosco-${name}-worker" ]) names;

  failedAssertions =
    config:
    map (assertion: assertion.message) (
      lib.filter (
        assertion: !assertion.assertion && lib.hasPrefix "services.bosco" assertion.message
      ) config.assertions
    );

  anyMessage = text: messages: lib.any (lib.hasInfix text) messages;

  # Instances that don't send emails, so only the setting under test matters
  quiet = lib.mapAttrs (_: instance: { sendEmails = false; } // instance);

  # Whether evaluating the instance's web service fails, e.g. on a bad option
  fails = instance: !(builtins.tryEval (builtins.deepSeq (evaluate (quiet { fi = instance; })).systemd.services.bosco-fi.environment true)).success;

  tests = {
    testEachInstanceHasThreeServices = {
      expr = lib.attrNames (ours services);
      expected = lib.sort lib.lessThan (servicesOf instanceNames);
    };

    testInstancesListenLocallyOnTheirOwnPorts = {
      expr = lib.genAttrs (map (name: "bosco-${name}") instanceNames) (name: services.${name}.environment.ADDR);
      expected = {
        bosco-fi = "127.0.0.1:3300";
        bosco-fr = "127.0.0.1:3301";
        bosco-staging = "127.0.0.1:3302";
      };
    };

    testNginxSendsEverythingToTheSite = {
      expr = {
        inherit (server.services.bosco.instances.fr) nginxLocations;
        sockets = lib.attrNames (ours server.systemd.sockets);
      };
      expected = {
        nginxLocations."/".proxyPass = "http://127.0.0.1:3301";
        sockets = [ ];
      };
    };

    testIPv6AddressesGetBrackets = {
      expr =
        (evaluate (quiet {
          fi = {
            baseUrl = "https://tilaus.example.fi";
            host = "::1";
          };
        })).systemd.services.bosco-fi.environment.ADDR;
      expected = "[::1]:3300";
    };

    testWebServerEnvironment = {
      expr =
        let
          environment = services.bosco-fi.environment;
          static = "${self.packages.${system}.rust-static}";
        in
        {
          inherit (environment)
            IHP_BASEURL
            DATABASE_URL
            IHP_SESSION_SECRET_FILE
            STATIC_DIR
            SEND_EMAILS
            ;
          assetVersion = environment.ASSET_VERSION == lib.substring 0 32 (baseNameOf static);
          ihpSettings = environment ? IHP_ENV || environment ? GHCRTS || environment ? STYLESHEET;
        };
      expected = {
        IHP_BASEURL = "https://tilaus.example.fi";
        DATABASE_URL = "postgresql:///bosco_fi?host=/run/postgresql&user=bosco_fi";
        IHP_SESSION_SECRET_FILE = "/var/lib/bosco-fi/session.aes";
        STATIC_DIR = "${self.packages.${system}.rust-static}";
        SEND_EMAILS = "1";
        assetVersion = true;
        ihpSettings = false;
      };
    };

    testEachInstanceHasItsLanguage = {
      expr = lib.genAttrs (lib.filter (name: !lib.hasSuffix "-migrate" name) (servicesOf instanceNames)) (
        name: services.${name}.environment.APP_LOCALE
      );
      expected = {
        bosco-fi = "fi";
        bosco-fi-worker = "fi";
        bosco-fr = "fr";
        bosco-fr-worker = "fr";
        bosco-staging = "fi";
        bosco-staging-worker = "fi";
      };
    };

    testUnknownLanguagesAreRefused = {
      expr = fails {
        baseUrl = "https://tilaus.example.fi";
        locale = "sv";
      };
      expected = true;
    };

    testServicesRunTheSitesPrograms = {
      expr = map (name: services.${name}.serviceConfig.ExecStart) [
        "bosco-fi"
        "bosco-fi-worker"
        "bosco-fi-migrate"
      ];
      expected = [
        "${self.packages.${system}.rust-web}/bin/bosco-web"
        "${self.packages.${system}.rust-web}/bin/bosco-worker"
        "${self.packages.${system}.rust-web}/bin/bosco-migrate"
      ];
    };

    testWebServerAndWorkerWaitForTheMigrations = {
      expr = map (
        name:
        lib.elem "bosco-fi-migrate.service" services.${name}.requires
        && lib.elem "bosco-fi-migrate.service" services.${name}.after
      ) [ "bosco-fi" "bosco-fi-worker" ];
      expected = [
        true
        true
      ];
    };

    testMigrationsWaitForPostgres = {
      expr = lib.elem "postgresql.service" services.bosco-fi-migrate.after;
      expected = true;
    };

    testMigrationsComeFromTheCheckout = {
      expr = services.bosco-fi-migrate.environment.IHP_MIGRATION_DIR;
      expected = "${self}/Application/Migration/";
    };

    testMinimumRevisionIsPerInstance = {
      expr = map (name: services."bosco-${name}-migrate".environment.MINIMUM_REVISION) instanceNames;
      expected = [
        "1760540031"
        "0"
        "0"
      ];
    };

    testOnlyNewInstancesBootstrapTheirSchema = {
      expr = map (name: lib.length services."bosco-${name}-migrate".serviceConfig.ExecStartPre) instanceNames;
      expected = [
        1
        2
        2
      ];
    };

    testStagingBootstrapsFromTheCheckout = {
      expr = {
        program = lib.hasSuffix "/bin/bootstrap-schema" (lib.last services.bosco-staging-migrate.serviceConfig.ExecStartPre);
        schema = services.bosco-staging-migrate.environment.APP_SCHEMA;
      };
      expected = {
        program = true;
        schema = "${self}/Application/Schema.sql";
      };
    };

    testWorkerSendsThroughItsInstancesSmtp = {
      expr = {
        inherit (services.bosco-fr-worker.environment)
          SEND_EMAILS
          SMTP_HOST
          SMTP_PORT
          SMTP_ENCRYPTION
          SMTP_USER
          SMTP_PASSWORD_FILE
          ;
        inherit (services.bosco-fr-worker.serviceConfig) LoadCredential;
      };
      expected = {
        SEND_EMAILS = "1";
        SMTP_HOST = "smtp.example.com";
        SMTP_PORT = "587";
        SMTP_ENCRYPTION = "starttls";
        SMTP_USER = "commande@example.fr";
        SMTP_PASSWORD_FILE = "%d/smtp-password";
        LoadCredential = "smtp-password:/var/lib/secrets/bosco/smtp-password-fr";
      };
    };

    testStagingDoesNotSendEmails = {
      expr = {
        inherit (services.bosco-staging-worker.environment) SEND_EMAILS;
        smtp = services.bosco-staging-worker.environment ? SMTP_HOST;
        credential = services.bosco-staging-worker.serviceConfig ? LoadCredential;
      };
      expected = {
        SEND_EMAILS = "0";
        smtp = false;
        credential = false;
      };
    };

    testOnlyTheWorkerSeesTheSmtpPassword = {
      expr = map (name: services.${name}.serviceConfig ? LoadCredential || services.${name}.environment ? SMTP_HOST) [
        "bosco-fi"
        "bosco-fi-migrate"
      ];
      expected = [
        false
        false
      ];
    };

    testEachInstanceHasItsOwnDatabaseAndUser = {
      expr = {
        inherit (server.services.postgresql) enable ensureDatabases;
        owners = map (user: user.name) (lib.filter (user: user.ensureDBOwnership) server.services.postgresql.ensureUsers);
        systemUsers = map (name: server.users.users."bosco_${name}".isSystemUser) instanceNames;
      };
      expected = {
        enable = true;
        ensureDatabases = map (name: "bosco_${name}") instanceNames;
        owners = map (name: "bosco_${name}") instanceNames;
        systemUsers = [
          true
          true
          true
        ];
      };
    };

    testServicesRunAsTheDatabaseOwner = {
      expr = lib.mapAttrs (_: service: service.serviceConfig.User) (ours services);
      expected = lib.listToAttrs (
        lib.concatMap (
          name:
          map (service: lib.nameValuePair service "bosco_${name}") [
            "bosco-${name}"
            "bosco-${name}-migrate"
            "bosco-${name}-worker"
          ]
        ) instanceNames
      );
    };

    testServicesAreHardened = {
      expr = lib.mapAttrs (
        _: service:
        lib.getAttrs [
          "NoNewPrivileges"
          "ProtectSystem"
          "ProtectHome"
          "CapabilityBoundingSet"
          "MemoryDenyWriteExecute"
          "StateDirectory"
        ] service.serviceConfig
      ) (lib.filterAttrs (name: _: lib.hasPrefix "bosco-fi" name) services);
      expected = lib.genAttrs [ "bosco-fi" "bosco-fi-migrate" "bosco-fi-worker" ] (_: {
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        CapabilityBoundingSet = "";
        MemoryDenyWriteExecute = true;
        StateDirectory = "bosco-fi";
      });
    };

    testTheReadmeSetupPassesTheChecks = {
      expr = failedAssertions server;
      expected = [ ];
    };

    testTwoInstancesCannotShareAPort = {
      expr = anyMessage "own port" (
        failedAssertions (evaluate (quiet {
          fi.baseUrl = "https://tilaus.example.fi";
          fr.baseUrl = "https://commande.example.fr";
        }))
      );
      expected = true;
    };

    # Every service of an instance, a demo's reset too, runs a program of
    # rust-web/
    testEveryProgramIsRust = {
      expr =
        let
          config = evaluate {
            demo = {
              baseUrl = "https://demo.example.com";
              port = 3303;
              demo = true;
              sendEmails = false;
            };
          };
          ours = lib.filterAttrs (name: _: lib.hasPrefix "bosco-demo" name) config.systemd.services;
        in
        lib.sort (a: b: a < b) (lib.mapAttrsToList (_: service: baseNameOf service.serviceConfig.ExecStart) ours);
      expected = [
        "bosco-migrate"
        "bosco-reset-demo"
        "bosco-web"
        "bosco-worker"
      ];
    };

    # The site's session key is the one the migrations' keygen makes, in the
    # state directory, so logins outlive a restart
    testTheSiteUsesTheInstancesSessionKey = {
      expr = {
        key = services.bosco-fi.environment.IHP_SESSION_SECRET_FILE;
        keygen = lib.hasInfix "keygen" (toString (lib.head services.bosco-fi-migrate.serviceConfig.ExecStartPre));
        state = services.bosco-fi.serviceConfig.StateDirectory;
      };
      expected = {
        key = "/var/lib/bosco-fi/session.aes";
        keygen = true;
        state = "bosco-fi";
      };
    };

    # The email worker with its instance's SMTP settings and password, as
    # the instance's user, and nothing of IHP's
    testTheWorkerHasOnlyWhatItNeeds = {
      expr =
        let
          worker = services.bosco-fi-worker;
        in
        {
          inherit (worker.environment)
            DATABASE_URL
            APP_LOCALE
            SEND_EMAILS
            SMTP_HOST
            SMTP_USER
            SMTP_PASSWORD_FILE
            ;
          inherit (worker.serviceConfig) LoadCredential User;
          sessionKey = worker.environment ? IHP_SESSION_SECRET_FILE;
          ihpSettings = worker.environment ? IHP_ENV || worker.environment ? GHCRTS;
        };
      expected = {
        DATABASE_URL = "postgresql:///bosco_fi?host=/run/postgresql&user=bosco_fi";
        APP_LOCALE = "fi";
        SEND_EMAILS = "1";
        SMTP_HOST = "smtp.example.com";
        SMTP_USER = "tilaus@example.fi";
        SMTP_PASSWORD_FILE = "%d/smtp-password";
        LoadCredential = "smtp-password:/var/lib/secrets/bosco/smtp-password";
        User = "bosco_fi";
        sessionKey = false;
        ihpSettings = false;
      };
    };

    # The order emails' sender and reply address reach the worker: the
    # defaults, and an instance's own
    testTheMailAddressesReachTheWorker = {
      expr =
        let
          config = evaluate {
            fi = {
              baseUrl = "https://tilaus.example.fi";
              inherit smtp;
            };
            shop = {
              baseUrl = "https://shop.example.com";
              port = 3310;
              inherit smtp;
              mail = {
                from = "Example Shop <orders@example.com>";
                replyTo = null;
              };
            };
          };
          addresses =
            name:
            let
              environment = config.systemd.services."bosco-${name}-worker".environment;
            in
            lib.getAttrs (lib.filter (n: lib.hasPrefix "MAIL_" n) (lib.attrNames environment)) environment;
        in
        {
          defaults = addresses "fi";
          own = addresses "shop";
        };
      expected = {
        defaults = {
          MAIL_FROM = "postmaster@boscofalconeria.it";
          MAIL_REPLY_TO = "Olive Oil Bosco Falconeria <oliveoil@boscofalconeria.it>";
        };
        own = {
          MAIL_FROM = "Example Shop <orders@example.com>";
        };
      };
    };

    # bosco-<name>-create-user for every instance: the Rust program as the
    # instance's user on its database
    testEveryInstanceHasACreateUserCommand = {
      expr =
        let
          commands = lib.filter (p: lib.hasPrefix "bosco-" (p.name or "")) server.environment.systemPackages;
          # Its text, without building it
          script = (lib.findFirst (p: p.name == "bosco-fr-create-user") null commands).drvAttrs.text;
        in
        {
          names = lib.sort (a: b: a < b) (map (p: p.name) commands);
          asTheUser = lib.hasInfix "runuser -u bosco_fr" script;
          program = lib.hasInfix "/bin/bosco-create-user" script;
          database = lib.hasInfix "postgresql:///bosco_fr?host=/run/postgresql&user=bosco_fr" script;
        };
      expected = {
        names = map (name: "bosco-${name}-create-user") instanceNames;
        asTheUser = true;
        program = true;
        database = true;
      };
    };

    # A configuration from when the Rust site ran beside the IHP app still
    # works with rustWeb.enable and rustWorker.enable, with a warning, and
    # rustWeb.nginxLocations is the same as nginxLocations
    testTheOldRustSwitchesOnlyWarn = {
      expr =
        let
          config = evaluate (quiet {
            fi = {
              baseUrl = "https://tilaus.example.fi";
              rustWeb.enable = true;
              rustWorker.enable = true;
            };
          });
        in
        {
          failed = failedAssertions config;
          warned = anyMessage "no longer needed" config.warnings;
          locations = config.services.bosco.instances.fi.rustWeb.nginxLocations;
        };
      expected = {
        failed = [ ];
        warned = true;
        locations."/".proxyPass = "http://127.0.0.1:3300";
      };
    };

    # What can't mean anything any more stops the evaluation, saying what to
    # do instead
    testTheIhpAppsOptionsAreRefused = {
      expr = map (instance: failedAssertions (evaluate (quiet { fi = { baseUrl = "https://tilaus.example.fi"; } // instance; }))) [
        { rustWeb.enable = false; }
        { rustWeb.port = 3400; }
        { rtsFlags = "-N"; }
        { migratePackage = pkgs.hello; }
      ];
      expected = [
        [ "services.bosco.instances.fi: the IHP app is gone, so rustWeb.enable and rustWorker.enable can't be false. Remove them." ]
        [ "services.bosco.instances.fi.rustWeb.port is gone with the IHP app: set port, which the site listens on now." ]
        [ "services.bosco.instances.fi.rtsFlags is gone with the IHP app: remove it: there's no GHC runtime." ]
        [ "services.bosco.instances.fi.migratePackage is gone with the IHP app: remove it: package has bosco-migrate." ]
      ];
    };

    testTwoInstancesCannotShareADatabase = {
      expr = anyMessage "own database" (
        failedAssertions (evaluate (quiet {
          fi.baseUrl = "https://tilaus.example.fi";
          fr = {
            baseUrl = "https://commande.example.fr";
            port = 3301;
            database = "bosco_fi";
          };
        }))
      );
      expected = true;
    };

    testOnlyADemoIsMarkedAsOne = {
      expr =
        let
          demo = evaluate {
            demo = {
              baseUrl = "https://demo.tilaus.example.fi";
              demo = true;
              sendEmails = false;
            };
          };
        in
        {
          demo = map (name: demo.systemd.services.${name}.environment.APP_DEMO) [
            "bosco-demo"
            "bosco-demo-worker"
          ];
          others = map (name: services."bosco-${name}".environment.APP_DEMO) instanceNames;
          failed = failedAssertions demo;
        };
      expected = {
        demo = [
          "1"
          "1"
        ];
        others = [
          "0"
          "0"
          "0"
        ];
        failed = [ ];
      };
    };

    testADemoIsResetEveryNight = {
      expr =
        let
          demo = evaluate {
            demo = {
              baseUrl = "https://demo.tilaus.example.fi";
              demo = true;
              sendEmails = false;
            };
          };
          reset = demo.systemd.services.bosco-demo-reset-demo;
        in
        {
          program = lib.hasSuffix "/bin/bosco-reset-demo" reset.serviceConfig.ExecStart;
          inherit (reset.environment) APP_DEMO SEND_EMAILS APP_FIXTURES;
          user = reset.serviceConfig.User;
          afterMigrations = lib.elem "bosco-demo-migrate.service" reset.after;
          timer = demo.systemd.timers.bosco-demo-reset-demo.timerConfig.OnCalendar;
          othersHaveNoReset = lib.attrNames (lib.filterAttrs (name: _: lib.hasSuffix "reset-demo" name) (ours services)) == [ ];
          othersHaveNoTimer = lib.attrNames (ours server.systemd.timers) == [ ];
        };
      expected = {
        program = true;
        APP_DEMO = "1";
        SEND_EMAILS = "0";
        APP_FIXTURES = "${self}/Application/Fixtures.sql";
        user = "bosco_demo";
        afterMigrations = true;
        timer = "*-*-* 03:00:00";
        othersHaveNoReset = true;
        othersHaveNoTimer = true;
      };
    };

    # Fixtures.en.sql for an English demo; French has no catalog of its own
    # yet, so it gets the Finnish one
    testADemoHasTheCatalogInItsLanguage = {
      expr =
        let
          demo =
            locale:
            evaluate {
              demo = {
                baseUrl = "https://demo.example.com";
                inherit locale;
                demo = true;
                sendEmails = false;
                bootstrapSchema = true;
              };
            };
          fixtures = locale: {
            reset = (demo locale).systemd.services.bosco-demo-reset-demo.environment.APP_FIXTURES;
            bootstrap = (demo locale).systemd.services.bosco-demo-migrate.environment.APP_FIXTURES;
          };
        in
        {
          en = fixtures "en";
          fr = fixtures "fr";
        };
      expected = {
        en = {
          reset = "${self}/Application/Fixtures.en.sql";
          bootstrap = "${self}/Application/Fixtures.en.sql";
        };
        fr = {
          reset = "${self}/Application/Fixtures.sql";
          bootstrap = "${self}/Application/Fixtures.sql";
        };
      };
    };

    # Every program of a demo knows it is one, and that it sends no emails:
    # the worker refuses to send a demo's
    testEveryDemoProgramKnowsItIsADemoWithoutEmails = {
      expr =
        let
          demo = evaluate {
            demo = {
              baseUrl = "https://demo.tilaus.example.fi";
              demo = true;
              sendEmails = false;
            };
          };
        in
        map (name: lib.getAttrs [ "APP_DEMO" "SEND_EMAILS" ] demo.systemd.services.${name}.environment) [
          "bosco-demo"
          "bosco-demo-worker"
          "bosco-demo-reset-demo"
        ];
      expected = lib.genList (_: {
        APP_DEMO = "1";
        SEND_EMAILS = "0";
      }) 3;
    };

    testADemoCannotSendEmails = {
      expr = anyMessage "a demo must not send emails" (
        failedAssertions (evaluate {
          fi = {
            baseUrl = "https://tilaus.example.fi";
            demo = true;
            inherit smtp;
          };
        })
      );
      expected = true;
    };

    testSendingEmailsNeedsAnSmtpServer = {
      expr = anyMessage "smtp.host" (
        failedAssertions (evaluate {
          fi.baseUrl = "https://tilaus.example.fi";
        })
      );
      expected = true;
    };

    testAnSmtpLoginNeedsBothUserAndPassword = {
      expr = anyMessage "both smtp.user and smtp.passwordFile" (
        failedAssertions (evaluate {
          fi = {
            baseUrl = "https://tilaus.example.fi";
            smtp = {
              host = "smtp.example.com";
              user = "tilaus@example.fi";
            };
          };
        })
      );
      expected = true;
    };

    testAnSmtpLoginNeedsEncryption = {
      expr = anyMessage "needs encryption" (
        failedAssertions (evaluate {
          fi = {
            baseUrl = "https://tilaus.example.fi";
            smtp = smtp // {
              encryption = "none";
            };
          };
        })
      );
      expected = true;
    };
  };

  failures = lib.runTests tests;
in
pkgs.runCommand "nixos-module-tests" { } (
  if failures == [ ] then
    ''
      echo "${toString (lib.length (lib.attrNames tests))} tests passed"
      touch $out
    ''
  else
    ''
      echo ${lib.escapeShellArg (lib.generators.toPretty { } failures)} >&2
      echo "${toString (lib.length failures)} of ${toString (lib.length (lib.attrNames tests))} tests failed" >&2
      exit 1
    ''
)
