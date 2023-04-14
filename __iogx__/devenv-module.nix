{ inputs # Desystemized merged inputs 
, systemized-inputs # Non-desystemized merged inputs
, config # iogx config passed to mkFlake
, pkgs # Desystemized nixpkgs (NEVER use systemized-inputs.nixpkgs.legacyPackages!)
}:

let
  scripts = import ./marlowe-cardano/scripts.nix { inherit inputs pkgs; };
in
{
  packages = [
    inputs.cardano-world.cardano.packages.cardano-address
    inputs.cardano-world.cardano.packages.cardano-node
    inputs.cardano-world.cardano.packages.cardano-cli
  ];

  enterShell = ''
    export PGUSER=postgres
  '';

  scripts.nix-flakes-alias.exec = scripts.nix-flakes-alias;
  scripts.re-up.exec = if pkgs.stdenv.system == "x86_64-linux" then scripts.re-up else "";
  scripts.start-cardano-node.exec = scripts.start-cardano-node;
}
