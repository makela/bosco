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

            perSystem = { pkgs, ... }: {
                ihp = {
                    appName = "bosco";
                    enable = true;
                    projectPath = ./.;
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
                        hspec
                        ihp-hspec
                    ];
                    devHaskellPackages = p: with p; [
                        cabal-install
                        hlint
                    ];
                };

                devenv.shells.default = {
                    processes = {
                        tailwind.exec = "tailwindcss -i tailwind/app.css -o static/app.css --watch=always";
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
