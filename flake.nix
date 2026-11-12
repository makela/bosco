{
  description = "Bosco Falconeria's order form and admin";

  inputs = {
    # The same nixpkgs as rust-web's development so far
    nixpkgs.url = "github:NixOS/nixpkgs/0bb2eedc20e4739f29e8045034f2828ad7054f8f";
    # Builds the site with its dependencies in a derivation of their own,
    # which is reused until rust-web/Cargo.lock changes
    crane.url = "github:ipetkov/crane/v0.24.0";
  };

  outputs =
    {
      self,
      nixpkgs,
      crane,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      # Runs the site on a NixOS server, see nix/module.nix and the README
      nixosModules.default = ./nix/module.nix;

      packages = forAll (
        pkgs:
        let
          craneLib = crane.mkLib pkgs;
        in
        rec {
          # The programs: the site, the worker, the migrations and the scripts
          rust-web = pkgs.callPackage ./nix/rust-web.nix { inherit craneLib; };
          # The site's stylesheet, scripts and images
          rust-static = pkgs.callPackage ./nix/rust-static.nix { };
          default = rust-web;
        }
      );

      checks = forAll (
        pkgs:
        let
          system = pkgs.stdenv.hostPlatform.system;
        in
        {
          # The Rust tests, against a throwaway PostgreSQL
          rust-web-tests = pkgs.callPackage ./nix/rust-web.nix {
            craneLib = crane.mkLib pkgs;
            runTests = true;
          };

          # The NixOS module, evaluated
          nixos-module = import ./nix/tests/module.nix {
            inherit pkgs self;
            inherit (nixpkgs.lib) nixosSystem;
          };

          # The deployment's database steps, with bosco-migrate as the module
          # runs it
          deploy-migrations = import ./nix/tests/migrations.nix {
            inherit pkgs;
            migrate = pkgs.writeShellScriptBin "migrate" ''
              exec ${self.packages.${system}.rust-web}/bin/bosco-migrate "$@"
            '';
            bootstrapSchema = pkgs.callPackage ./nix/bootstrap-schema.nix { };
            # What it reads, so that other changes don't rerun it
            src = pkgs.lib.fileset.toSource {
              root = ./.;
              fileset = pkgs.lib.fileset.unions [
                ./db/Schema.sql
                ./db/Fixtures.sql
                ./db/Migration
              ];
            };
            ihpSchema = ./db/IHPSchema.sql;
          };
        }
      );

      # See the Justfile for what to do in it
      devShells = forAll (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.cargo
            pkgs.rustc
            pkgs.clippy
            pkgs.rustfmt
            pkgs.rust-analyzer
            pkgs.postgresql
            pkgs.tailwindcss_4
            pkgs.watchexec
            pkgs.just
          ];
          shellHook = ''
            git config core.hooksPath .githooks
          '';
        };
      });
    };
}
