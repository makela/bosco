# The public site in Rust (rust-web/), for nix/module.nix's rustWeb option.
# With runTests = true it is the flake check that runs its tests too, against a
# throwaway PostgreSQL, as rust-web/test.sh does; the package itself skips
# them, as they need the database.
#
# Built with crane: the dependencies in a derivation of their own, for both
# the programs and the tests, which is reused until Cargo.lock changes, so a
# change to the site compiles only the site.
{
  lib,
  craneLib,
  postgresql,
  runTests ? false,
}:
let
  common = {
    pname = "bosco-rust-web";
    version = "0.1.0";

    # The crate, and what its tests read from the IHP app: the schema and the
    # logo they ask for
    src = lib.fileset.toSource {
      root = ../.;
      fileset = lib.fileset.unions [
        ../rust-web/Cargo.toml
        ../rust-web/Cargo.lock
        ../rust-web/src
        ../rust-web/tests
        ../rust-web/test.sh
        ../Application/Schema.sql
        ../static/img/logo.jpg
      ];
    };
    cargoToml = ../rust-web/Cargo.toml;
    cargoLock = ../rust-web/Cargo.lock;
    # Into rust-web/, see crane's "workspace not at source root"
    postUnpack = ''
      cd $sourceRoot/rust-web
      sourceRoot="."
    '';
    strictDeps = true;
  };

  # The dependencies, compiled for the release build and its tests
  cargoArtifacts = craneLib.buildDepsOnly common;
in
craneLib.buildPackage (
  common
  // {
    pname = if runTests then "bosco-rust-web-tests" else "bosco-rust-web";
    inherit cargoArtifacts;

    doCheck = runTests;
    nativeCheckInputs = [ postgresql ];
    checkPhase = ''
      runHook preCheck
      bash test.sh --release
      runHook postCheck
    '';

    meta.mainProgram = "bosco-web";
  }
)
