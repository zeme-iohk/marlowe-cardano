{ inputs # Desystemized merged inputs 
, systemized-inputs # Non-desystemized merged inputs
, config # iogx config passed to mkFlake
, pkgs # Desystemized nixpkgs (NEVER use systemized-inputs.nixpkgs.legacyPackages!)
}:
{
  operables = import ./marlowe-cardano/deploy/operables.nix
    { inherit inputs pkgs; };

  oci-images = import ./marlowe-cardano/deploy/oci-images.nix
    { inherit inputs pkgs; };

  nomadTasks = import ./marlowe-cardano/deploy/nomadTasks.nix
    { inherit inputs; };

  networks = import ./marlowe-cardano/networks.nix
    { inherit inputs pkgs; };

  packages.compose-spec = import ./marlowe-cardano/compose-spec.nix
    { inherit inputs pkgs; };

  packages.entrypoints = import ./marlowe-cardano/bitte
    { inherit inputs pkgs; };

  # TODO can this line be simplified even more?
} #// inputs.tullia.fromSimple pkgs.stdenv.system (import ./marlowe-cardano/tullia.nix)
