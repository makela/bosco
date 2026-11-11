# Evaluates nix/module.nix with a Finnish, a French and a staging instance,
# as in the README, and checks the users, databases, sockets and services it
# makes. Nothing is built or started, so no virtual machine is needed.
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
      expr = lib.mapAttrs (_: socket: socket.socketConfig.ListenStream) (ours server.systemd.sockets);
      expected = {
        bosco-fi = "127.0.0.1:3300";
        bosco-fr = "127.0.0.1:3301";
        bosco-staging = "127.0.0.1:3302";
      };
    };

    testIPv6AddressesGetBrackets = {
      expr =
        (evaluate (quiet {
          fi = {
            baseUrl = "https://tilaus.example.fi";
            host = "::1";
          };
        })).systemd.sockets.bosco-fi.socketConfig.ListenStream;
      expected = "[::1]:3300";
    };

    testWebServerEnvironment = {
      expr = lib.getAttrs [
        "IHP_ENV"
        "IHP_BASEURL"
        "DATABASE_URL"
        "IHP_SESSION_SECRET_FILE"
        "IHP_REQUEST_LOGGER_IP_ADDR_SOURCE"
        "IHP_SYSTEMD"
      ] services.bosco-fi.environment;
      expected = {
        IHP_ENV = "Production";
        IHP_BASEURL = "https://tilaus.example.fi";
        DATABASE_URL = "postgresql:///bosco_fi?host=/run/postgresql";
        IHP_SESSION_SECRET_FILE = "/var/lib/bosco-fi/session.aes";
        IHP_REQUEST_LOGGER_IP_ADDR_SOURCE = "FromHeader";
        IHP_SYSTEMD = "1";
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
        "${self.packages.${system}.optimized-prod-server}/bin/RunProdServer"
        "${self.packages.${system}.optimized-prod-server}/bin/RunJobs"
        "${self.packages.${system}.migrate}/bin/migrate"
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
          "StateDirectory"
        ] service.serviceConfig
      ) (lib.filterAttrs (name: _: lib.hasPrefix "bosco-fi" name) services);
      expected = lib.genAttrs [ "bosco-fi" "bosco-fi-migrate" "bosco-fi-worker" ] (_: {
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        CapabilityBoundingSet = "";
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

    # A demo with the public pages in Rust: its own service next to IHP's,
    # on the same database as the same user, and nginx locations for both
    testTheRustSiteRunsBesideTheIhpApp = {
      expr =
        let
          demo = evaluate {
            demo = {
              baseUrl = "https://demo.example.com";
              port = 3303;
              locale = "en";
              demo = true;
              sendEmails = false;
              rustWeb.enable = true;
            };
          };
          rust = demo.systemd.services.bosco-demo-rust-web;
          static = "${self.packages.${system}.static}";
        in
        {
          program = lib.hasSuffix "/bin/bosco-web" rust.serviceConfig.ExecStart;
          inherit (rust.environment)
            DATABASE_URL
            ADDR
            APP_LOCALE
            APP_DEMO
            SEND_EMAILS
            STATIC_DIR
            IHP_SESSION_SECRET_FILE
            IHP_BASEURL
            ;
          stylesheet = rust.environment.STYLESHEET == "/prod.css?v=${lib.substring 0 32 (baseNameOf static)}";
          assetVersion = rust.environment.ASSET_VERSION == lib.substring 0 32 (baseNameOf static);
          # The same key as the IHP app's
          sessionKey = rust.environment.IHP_SESSION_SECRET_FILE == demo.systemd.services.bosco-demo.environment.IHP_SESSION_SECRET_FILE;
          user = rust.serviceConfig.User;
          afterMigrations = lib.elem "bosco-demo-migrate.service" rust.after;
          ihpStillRuns = demo.systemd.services ? bosco-demo && demo.systemd.services ? bosco-demo-worker;
          locations = demo.services.bosco.instances.demo.rustWeb.nginxLocations;
        };
      expected = {
        program = true;
        DATABASE_URL = "postgresql:///bosco_demo?host=/run/postgresql&user=bosco_demo";
        ADDR = "127.0.0.1:3403";
        APP_LOCALE = "en";
        APP_DEMO = "1";
        SEND_EMAILS = "0";
        STATIC_DIR = "${self.packages.${system}.static}";
        IHP_SESSION_SECRET_FILE = "/var/lib/bosco-demo/session.aes";
        IHP_BASEURL = "https://demo.example.com";
        stylesheet = true;
        assetVersion = true;
        sessionKey = true;
        user = "bosco_demo";
        afterMigrations = true;
        ihpStillRuns = true;
        locations = {
          "= /".proxyPass = "http://127.0.0.1:3403";
          "= /Orders".proxyPass = "http://127.0.0.1:3403";
          "= /NewOrder".proxyPass = "http://127.0.0.1:3403";
          "= /CreateOrder".proxyPass = "http://127.0.0.1:3403";
          "= /ShowOrder".proxyPass = "http://127.0.0.1:3403";
          "= /NewEmail".proxyPass = "http://127.0.0.1:3403";
          "= /CreateEmail".proxyPass = "http://127.0.0.1:3403";
          "= /admin/".proxyPass = "http://127.0.0.1:3403";
          "= /admin/Welcome".proxyPass = "http://127.0.0.1:3403";
          "= /admin/Orders".proxyPass = "http://127.0.0.1:3403";
          "= /admin/ShowOrder".proxyPass = "http://127.0.0.1:3403";
          "= /admin/UpdateMarkPaidOrder".proxyPass = "http://127.0.0.1:3403";
          "= /admin/UpdateInvoiceOrder".proxyPass = "http://127.0.0.1:3403";
          "= /admin/UpdateDeliverOrder".proxyPass = "http://127.0.0.1:3403";
          "= /admin/UpdateSendInvoiceOrder".proxyPass = "http://127.0.0.1:3403";
          "= /admin/DeleteCancelOrder".proxyPass = "http://127.0.0.1:3403";
          "= /admin/NewSession".proxyPass = "http://127.0.0.1:3403";
          "= /admin/CreateSession".proxyPass = "http://127.0.0.1:3403";
          "= /admin/DeleteSession".proxyPass = "http://127.0.0.1:3403";
          "= /admin/DemoLogin".proxyPass = "http://127.0.0.1:3403";
          "/".proxyPass = "http://127.0.0.1:3303";
        };
      };
    };

    # The Rust email worker in the same service, with the same SMTP settings
    # and password, as the same user
    testTheRustWorkerTakesOverTheWorkerService = {
      expr =
        let
          worker =
            (evaluate {
              fi = {
                baseUrl = "https://tilaus.example.fi";
                locale = "fi";
                inherit smtp;
                rustWorker.enable = true;
              };
            }).systemd.services.bosco-fi-worker;
        in
        {
          program = lib.hasSuffix "/bin/bosco-worker" worker.serviceConfig.ExecStart;
          inherit (worker.environment)
            DATABASE_URL
            APP_LOCALE
            SEND_EMAILS
            SMTP_HOST
            SMTP_USER
            SMTP_PASSWORD_FILE
            ;
          inherit (worker.serviceConfig) LoadCredential User MemoryDenyWriteExecute;
          ihpSettings = worker.environment ? IHP_ENV || worker.environment ? GHCRTS;
        };
      expected = {
        program = true;
        DATABASE_URL = "postgresql:///bosco_fi?host=/run/postgresql&user=bosco_fi";
        APP_LOCALE = "fi";
        SEND_EMAILS = "1";
        SMTP_HOST = "smtp.example.com";
        SMTP_USER = "tilaus@example.fi";
        SMTP_PASSWORD_FILE = "%d/smtp-password";
        LoadCredential = "smtp-password:/var/lib/secrets/bosco/smtp-password";
        User = "bosco_fi";
        MemoryDenyWriteExecute = true;
        ihpSettings = false;
      };
    };

    testWorkersStayInIhpUnlessAsked = {
      expr = map (name: lib.hasSuffix "/bin/RunJobs" services."bosco-${name}-worker".serviceConfig.ExecStart) instanceNames;
      expected = [
        true
        true
        true
      ];
    };

    testOnlyAnInstanceThatAsksRunsTheRustSite = {
      expr = lib.attrNames (lib.filterAttrs (name: _: lib.hasSuffix "-rust-web" name) services);
      expected = [ ];
    };

    testTheRustSiteNeedsAPortOfItsOwn = {
      expr = anyMessage "own port" (
        failedAssertions (evaluate (quiet {
          fi = {
            baseUrl = "https://tilaus.example.fi";
            rustWeb.enable = true;
          };
          fr = {
            baseUrl = "https://commande.example.fr";
            port = 3400; # the Rust site's of fi
          };
        }))
      );
      expected = true;
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
          program = lib.hasSuffix "/bin/ResetDemo" reset.serviceConfig.ExecStart;
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

    # Config.hs refuses to start a demo without SEND_EMAILS=0, so every
    # program of a demo needs both settings, not only the worker
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
