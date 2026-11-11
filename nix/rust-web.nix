# The public site in Rust (rust-web/), for nix/module.nix's rustWeb option.
# With runTests = true it is the flake check that runs its tests too, against a
# throwaway PostgreSQL, as rust-web/test.sh does; the package itself skips
# them, as they need the database.
{
  lib,
  rustPlatform,
  postgresql,
  runTests ? false,
}:
rustPlatform.buildRustPackage {
  pname = if runTests then "bosco-rust-web-tests" else "bosco-rust-web";
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
  cargoRoot = "rust-web";
  buildAndTestSubdir = "rust-web";
  cargoLock.lockFile = ../rust-web/Cargo.lock;

  doCheck = runTests;
  nativeCheckInputs = [ postgresql ];
  checkPhase = ''
    runHook preCheck
    (cd rust-web && bash test.sh --release)
    runHook postCheck
  '';

  meta.mainProgram = "bosco-web";
}
