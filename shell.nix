{ system ? builtins.currentSystem
, enableHaskellProfiling ? false
, packages ? import ./. { inherit system enableHaskellProfiling; }
}:
let
  inherit (packages) pkgs marlowe docs marlowe-cli dev-scripts network;
  inherit (dev-scripts) start-cardano-node run-chainseekd;
  inherit (pkgs) stdenv lib utillinux python3 nixpkgs-fmt writeShellScriptBin networks;
  inherit (marlowe) haskell stylish-haskell sphinxcontrib-haddock sphinx-markdown-tables sphinxemoji nix-pre-commit-hooks cardano-cli cardano-node;
  inherit (marlowe) writeShellScriptBinInRepoRoot;

  set-xdg = ''
    export XDG_DATA_HOME="''${XDG_DATA_HOME:-''${HOME}/.local/share}"
    mkdir -p "''${XDG_DATA_HOME}"
    export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-''${HOME}/.local/run}"
    mkdir -p "''${XDG_RUNTIME_DIR}"
  '';

  # For Sphinx, and ad-hoc usage
  sphinxTools = python3.withPackages (ps: [
    sphinxcontrib-haddock.sphinxcontrib-domaintools
    sphinx-markdown-tables
    sphinxemoji
    ps.sphinxcontrib_plantuml
    ps.sphinxcontrib-bibtex
    ps.sphinx
    ps.sphinx_rtd_theme
    ps.recommonmark
  ]);

  # Configure project pre-commit hooks
  pre-commit-check = nix-pre-commit-hooks.run {
    src = (lib.cleanSource ./.);
    tools = {
      stylish-haskell = stylish-haskell;
      nixpkgs-fmt = nixpkgs-fmt;
      shellcheck = pkgs.shellcheck;
    };
    hooks = {
      prettier = {
        enable = true;
        types_or = [ "javascript" "css" "html" ];
      };
      stylish-haskell.enable = true;
      nixpkgs-fmt = {
        enable = true;
        # While nixpkgs-fmt does exclude patterns specified in `.ignore` this
        # does not appear to work inside the hook. For now we have to thus
        # maintain excludes here *and* in `./.ignore` and *keep them in sync*.
        excludes = [ ".*nix/pkgs/haskell/materialized.*/.*" ".*/spago-packages.nix$" ".*/packages.nix$" ];
      };
      shellcheck.enable = true;
      png-optimization = {
        enable = true;
        name = "png-optimization";
        description = "Ensure that PNG files are optimized";
        entry = "${pkgs.optipng}/bin/optipng";
        files = "\\.png$";
      };
    };
  };

  nixFlakesAlias = pkgs.runCommand "nix-flakes-alias" { } ''
    mkdir -p $out/bin
    ln -sv ${pkgs.nixFlakes}/bin/nix $out/bin/nix-flakes
  '';

  # build inputs from nixpkgs ( -> ./nix/default.nix )
  nixpkgsInputs = (with pkgs; [
    arion
    cacert
    editorconfig-core-c
    ghcid
    jq
    nixFlakesAlias
    nixpkgs-fmt
    shellcheck
    sqlite-interactive
    yq
    z3
    zlib
    tmux

    # marlowe-chain-sync
    docker-compose
    postgresql
    sqitchPg
  ] ++ (lib.optionals (!stdenv.isDarwin) [ rPackages.plotly R ]));

  # local build inputs ( -> ./nix/pkgs/default.nix )
  localInputs = (with marlowe; [
    cabal-install
    cardano-cli
    cardano-node
    cardano-repo-tool
    docs.build-and-serve-docs
    fix-prettier
    fixStylishHaskell
    haskell-language-server
    haskell-language-server-wrapper
    hie-bios
    hlint
    marlowe-cli
    run-chainseekd
    start-cardano-node
    stylish-haskell
    updateMaterialized
  ]);

  defaultShellHook = ''
    ${pre-commit-check.shellHook}
  ''
  # Work around https://github.com/NixOS/nix/issues/3345, which makes
  # tests etc. run single-threaded in a nix-shell.
  # Sets the affinity to cores 0-1000 for $$ (current PID in bash)
  # Only necessary for linux - darwin doesn't even expose thread
  # affinity APIs!
  + lib.optionalString stdenv.isLinux ''
    ${utillinux}/bin/taskset -pc 0-1000 $$
  '';

  defaultShell = haskell.project.shellFor {
    nativeBuildInputs = nixpkgsInputs ++ localInputs ++ [ sphinxTools ];
    # We don't currently use this, and it's a pain to materialize, and otherwise
    # costs a fair bit of eval time.
    withHoogle = false;
    shellHook = ''
      export ACTUS_TEST_DATA_DIR=${packages.actus-tests}/tests/
      export PGUSER=postgres
      ${defaultShellHook}
    '';
  };

  develShells =
    let
      libs = [
        pkgs.glibcLocales
        pkgs.libsodium-vrf
        pkgs.lzma
        pkgs.openssl
        pkgs.secp256k1
        pkgs.zlib
      ];

      marloweCoreBuildInputs = (with marlowe; libs ++ [
        cabal-install
        docs.build-and-serve-docs
        fix-prettier
        fixStylishHaskell
        pkgs.ghcid
        pkgs.git
        pkgs.ghc
        haskell-language-server
        haskell-language-server-wrapper
        hie-bios
        hlint
        pkgs.pre-commit
        pkgs.pkgconfig
        stylish-haskell
        updateMaterialized
      ]);
      marloweCliBuildInputs = marloweCoreBuildInputs ++ [
        cardano-node
        cardano-cli
        start-cardano-node
      ];
      develShell = { buildInputs, shellHook ? "" }: pkgs.mkShell {
        name = "marlowe-core-shell";
        buildInputs = buildInputs;
        LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath libs;
        shellHook = ''
          ${defaultShellHook}
          ${shellHook}
        '';
      };
    in
    {
      marloweActus = develShell {
        buildInputs = marloweCoreBuildInputs;
        shellHook = ''
          export ACTUS_TEST_DATA_DIR=${packages.actus-tests}/tests/
        '';
      };
      marloweCli = develShell { buildInputs = marloweCliBuildInputs; };
      marloweCore = develShell { buildInputs = marloweCoreBuildInputs; };
    };
in
defaultShell // {
  marlowe-actus = develShells.marloweActus;
  marlowe-cli = develShells.marloweCli;
  marlowe-core = develShells.marloweCore;
}
