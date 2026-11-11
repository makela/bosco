{
    inputs = {
        # Here you can adjust the IHP version of your project
        # You can find new releases at https://github.com/digitallyinduced/ihp/releases
        ihp.url = "github:digitallyinduced/ihp/v1.6";
        nixpkgs.follows = "ihp/nixpkgs";
        flake-parts.follows = "ihp/flake-parts";
        devenv.follows = "ihp/devenv";
        systems.follows = "ihp/systems";
        devenv-root = {
            url = "file+file:///dev/null";
            flake = false;
        };
    };

    outputs = inputs@{ ihp, flake-parts, systems, ... }:
        flake-parts.lib.mkFlake { inherit inputs; } {

            systems = import systems;
            imports = [ ihp.flakeModules.default ];

            # Runs the site on a NixOS server, see nix/module.nix and the README
            flake.nixosModules.default = ./nix/module.nix;

            perSystem = { pkgs, self', ... }: {
                ihp = {
                    appName = "bosco";
                    enable = true;
                    # The app's own files only, so that a change to the Rust site, the
                    # NixOS module or the docs doesn't rebuild and retest the IHP app
                    projectPath = pkgs.lib.fileset.toSource {
                        root = ./.;
                        fileset = pkgs.lib.fileset.difference ./. (pkgs.lib.fileset.unions [
                            ./rust-web
                            ./nix
                            ./README.md
                            ./flake.nix
                            ./flake.lock
                        ]);
                    };
                    packages = with pkgs; [
                        # Native dependencies, e.g. imagemagick
                        watchman
                        tailwindcss_4
                    ];
                    haskellPackages = p: with p; [
                        # Haskell dependencies go here
                        p.ihp
                        base
                        wai
                        text
                        mmark
                        password
                        ihp-mail
                    ];
                    devHaskellPackages = p: with p; [
                        # Only in the dev shell and `nix flake check`, not in production builds
                        cabal-install
                        hlint
                        hspec
                        ihp-hspec
                    ];
                };

                # The public site in Rust, see rust-web/ and the rustWeb option
                # of nix/module.nix; the check runs its tests too
                packages.rust-web = pkgs.callPackage ./nix/rust-web.nix { };
                checks.rust-web-tests = pkgs.callPackage ./nix/rust-web.nix { runTests = true; };

                checks.nixos-module = import ./nix/tests/module.nix {
                    inherit pkgs;
                    inherit (inputs.nixpkgs.lib) nixosSystem;
                    inherit (inputs) self;
                };

                # Every Application/Script/*.hs compiles: nothing else builds
                # them, and a broken one shows only when someone runs it
                checks.scripts = pkgs.linkFarm "bosco-scripts"
                    (pkgs.lib.filterAttrs (name: _: pkgs.lib.hasPrefix "script-" name) self'.packages);

                checks.deploy-migrations = import ./nix/tests/migrations.nix {
                    inherit pkgs;
                    inherit (self'.packages) migrate;
                    bootstrapSchema = pkgs.callPackage ./nix/bootstrap-schema.nix { };
                    src = ./.;
                    ihpSchema = "${ihp}/ihp-schema-compiler/data/IHPSchema.sql";
                };

                devenv.shells.default = {
                    processes = {
                        tailwind.exec = "tailwindcss -i tailwind/app.css -o static/app.css --watch=always";
                        # The Rust site (rust-web/) at http://localhost:8003, on
                        # the dev database and with the IHP app's session key, so
                        # its admin login works on the IHP app's admin. Built and
                        # restarted when its code changes; the first build takes
                        # a few minutes. The IHP app's worker sends the emails.
                        # In rust-web's own shell, so its builds are the same as
                        # by hand there.
                        rust-web = {
                            exec = ''
                                cd "$DEVENV_ROOT/rust-web"
                                exec nix develop path:. -c watchexec --restart \
                                  --watch src --watch Cargo.toml --watch Cargo.lock \
                                  -- cargo run --bin bosco-web
                            '';
                            after = [ "devenv:processes:postgres" ];
                        };
                    };
                };
            };

        };

    nixConfig = {
        extra-substituters = [
            "https://devenv.cachix.org"
            "https://cachix.cachix.org"
            "https://digitallyinduced.cachix.org"
        ];
        extra-trusted-public-keys = [
            "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
            "cachix.cachix.org-1:eWNHQldwUO7G2VkjpnjDbWwy4KQ/HNxht7H4SSoMckM="
            "digitallyinduced.cachix.org-1:y+wQvrnxQ+PdEsCt91rmvv39qRCYzEgGQaldK26hCKE="
        ];
    };
}
