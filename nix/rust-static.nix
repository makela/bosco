# The Rust site's static files, for STATIC_DIR: the stylesheet, built with
# Tailwind from tailwind/app.css for the Rust site's markup only, the
# scripts, the logo and the favicon. Its own package, so that its version
# (ASSET_VERSION, in the files' addresses) changes only when they do.
{
  lib,
  stdenvNoCC,
  tailwindcss_4,
}:
stdenvNoCC.mkDerivation {
  pname = "bosco-rust-static";
  version = "0.1.0";

  # Tailwind takes the classes from the files around it, so only the
  # stylesheet's source, the Rust site's code and the files to copy
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../tailwind/app.css
      ../rust-web/src
      ../static/app.js
      ../static/admin.js
      ../static/favicon.ico
      ../static/img
    ];
  };

  nativeBuildInputs = [ tailwindcss_4 ];

  buildPhase = ''
    runHook preBuild
    tailwindcss -i tailwind/app.css -o app.css --minify
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r app.css static/app.js static/admin.js static/favicon.ico static/img $out/
    runHook postInstall
  '';
}
