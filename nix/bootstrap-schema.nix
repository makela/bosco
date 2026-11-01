# The schema bootstrap for new staging databases, see bootstrap-schema.sh
{
  writeShellApplication,
  postgresql,
  coreutils,
  gnused,
}:
writeShellApplication {
  name = "bootstrap-schema";
  runtimeInputs = [
    postgresql
    coreutils
    gnused
  ];
  text = builtins.readFile ./bootstrap-schema.sh;
}
