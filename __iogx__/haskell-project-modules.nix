{ inputs # Desystemized merged inputs 
, systemized-inputs # Non-desystemized merged inputs
, config # iogx config passed to mkFlake
, pkgs # Desystemized nixpkgs (NEVER use systemized-inputs.nixpkgs.legacyPackages!)
, ghc # Current compiler
, deferPluginErrors # For Haddock generation
}:

[
  (_: {
    packages =
      let
        lib = pkgs.lib;
        mkIfDarwin = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin;
        isCross = pkgs.stdenv.hostPlatform != pkgs.stdenv.buildPlatform;
      in
      {
        # Things that need plutus-tx-plugin
        marlowe.package.buildable = !isCross; # Would also require libpq
        marlowe-actus.package.buildable = !isCross;
        marlowe-contracts.package.buildable = !isCross;
        marlowe-cli.package.buildable = !isCross;

        # These libraries rely on a TemplateHaskell splice that requires
        # git to be in the path at build time. This only seems to affect
        # Darwin builds, and including them on Linux breaks lorri, so we
        # only add these options when building on Darwin.
        marlowe-cli.components.exes.marlowe-cli.build-tools = mkIfDarwin [ pkgs.buildPackages.buildPackages.gitReallyMinimal ];

        # See https://github.com/input-output-hk/plutus/issues/1213 and
        # https://github.com/input-output-hk/plutus/pull/2865.
        marlowe.doHaddock = deferPluginErrors;
        marlowe.flags.defer-plugin-errors = deferPluginErrors;

        # Fix missing executables on the paths of the test runners. This is arguably
        # a bug, and the fix is a bit of a hack.
        marlowe.components.tests.marlowe-test.preCheck = ''
          PATH=${lib.makeBinPath [ pkgs.z3 ]}:$PATH
        '';

        marlowe-contracts.components.tests.marlowe-contracts-test.preCheck = ''
          PATH=${lib.makeBinPath [ pkgs.z3 ]}:$PATH
        '';

        marlowe-test.components.tests.marlowe-test.preCheck = ''
          PATH=${lib.makeBinPath [ pkgs.z3 ]}:$PATH
        '';

        # Note: The following two statements say that these tests should
        # _only_ run on linux. In actual fact we just don't want them
        # running on the 'mac-mini' instances, because these tests time out
        # there. In an ideal world this would be reflected here more
        # accurately.
        # TODO: Resolve this situation in a better way.
        marlowe.components.tests.marlowe-test-long-running = {
          platforms = lib.platforms.linux;
        };

        marlowe.ghcOptions = [ "-Werror" ];
        marlowe-actus.ghcOptions = [ "-Werror" ];
        marlowe-chain-sync.ghcOptions = [ "-Werror" ];
        marlowe-cli.ghcOptions = [ "-Werror" ];
        marlowe-contracts.ghcOptions = [ "-Werror" ];
        marlowe-integration.ghcOptions = [ "-Werror" ];
        marlowe-integration-tests.ghcOptions = [ "-Werror" ];
        marlowe-protocols.ghcOptions = [ "-Werror" ];
        marlowe-runtime.ghcOptions = [ "-Werror" ];
        marlowe-runtime-cli.ghcOptions = [ "-Werror" ];
        marlowe-runtime-web.ghcOptions = [ "-Werror" ];
        marlowe-test.ghcOptions = [ "-Werror" ];
      };
  })
] 

