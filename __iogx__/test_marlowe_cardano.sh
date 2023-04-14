all_packages=(
  "aeson-via-serialise:lib:aeson-via-serialise"
  "async-components:lib:async-components"
  "base16-aeson:lib:base16-aeson"
  "cardano-integration:exe:create-testnet"
  "cardano-integration:lib:cardano-integration"
  "eventuo11y-extras:lib:eventuo11y-extras"
  "marlowe-actus:lib:marlowe-actus"
  "marlowe-actus:test:marlowe-actus-test"
  "marlowe-apps:exe:marlowe-finder"
  "marlowe-apps:exe:marlowe-oracle"
  "marlowe-apps:exe:marlowe-pipe"
  "marlowe-apps:exe:marlowe-scaling"
  "marlowe-apps:lib:marlowe-apps"
  "marlowe-cardano:lib:marlowe-cardano"
  "marlowe-chain-sync:exe:marlowe-chain-indexer"
  "marlowe-chain-sync:exe:marlowe-chain-sync"
  "marlowe-chain-sync:lib:chain-indexer"
  "marlowe-chain-sync:lib:gen"
  "marlowe-chain-sync:lib:libchainsync"
  "marlowe-chain-sync:lib:marlowe-chain-sync"
  "marlowe-chain-sync:lib:plutus-compat"
  "marlowe-chain-sync:test:marlowe-chain-sync-test"
  "marlowe-cli:exe:marlowe-cli"
  "marlowe-cli:lib:marlowe-cli"
  "marlowe-client:lib:marlowe-client"
  "marlowe-contracts:lib:marlowe-contracts"
  "marlowe-contracts:test:marlowe-contracts-test"
  "marlowe-integration-tests:exe:marlowe-integration-tests"
  "marlowe-integration:exe:marlowe-integration-example"
  "marlowe-integration:lib:marlowe-integration"
  "marlowe-protocols:lib:marlowe-protocols"
  "marlowe-runtime-cli:exe:marlowe-runtime-cli"
  "marlowe-runtime-web:exe:marlowe-web-server"
  "marlowe-runtime-web:lib:marlowe-runtime-web"
  "marlowe-runtime-web:lib:server"
  "marlowe-runtime-web:test:marlowe-runtime-web-test"
  "marlowe-runtime:exe:marlowe-indexer"
  "marlowe-runtime:exe:marlowe-proxy"
  "marlowe-runtime:exe:marlowe-sync"
  "marlowe-runtime:exe:marlowe-tx"
  "marlowe-runtime:lib:config"
  "marlowe-runtime:lib:discovery-api"
  "marlowe-runtime:lib:gen"
  "marlowe-runtime:lib:history-api"
  "marlowe-runtime:lib:indexer"
  "marlowe-runtime:lib:marlowe-runtime"
  "marlowe-runtime:lib:plutus-scripts"
  "marlowe-runtime:lib:proxy"
  "marlowe-runtime:lib:proxy-api"
  "marlowe-runtime:lib:sync"
  "marlowe-runtime:lib:sync-api"
  "marlowe-runtime:lib:tx"
  "marlowe-runtime:lib:tx-api"
  "marlowe-runtime:test:indexer-test"
  "marlowe-runtime:test:marlowe-runtime-test"
  "marlowe-test:exe:marlowe-reference"
  "marlowe-test:exe:marlowe-spec-client"
  "marlowe-test:lib:marlowe-test"
  "marlowe-test:test:marlowe-test"
  "plutus-ledger-ada:lib:plutus-ledger-ada"
  "plutus-ledger-aeson:lib:plutus-ledger-aeson"
  "plutus-ledger-slot:lib:plutus-ledger-slot"
)

NIX_BUILD() {
  GC_DONT_GC=1 nix build --dry-run --no-warn-dirty --accept-flake-config "$1"
}

for pkg in ${all_packages[@]}; do
  for ghc in "ghc8107"; do # Excluding ghc924 
    echo "Building .#$ghc.$pkg" 
    NIX_BUILD ".#$ghc.$pkg"
    echo "Building .#profiled.$ghc.$pkg" 
    NIX_BUILD ".#profiled.$ghc.$pkg"
  done 
done

all_devshells=(
  "default"
)

NIX_DEVELOP() {
  GC_DONT_GC=1 nix develop --dry-run --no-warn-dirty --accept-flake-config --build "$1"
}

for shell in ${all_devshells[@]}; do
  echo "Building default"
  NIX_DEVELOP
  for ghc in "ghc8107"; do # Excluding ghc924 
    echo "Building .#$ghc.$shell" 
    NIX_DEVELOP ".#$ghc.$shell"
    echo "Building .#profiled.$ghc.$shell" 
    NIX_DEVELOP ".#profiled.$ghc.$shell"
  done 
done

return 1

all_runnables=(
  "cardano-integration:exe:create-testnet"
  "marlowe-actus:test:marlowe-actus-test"
  "marlowe-apps:exe:marlowe-finder"
  "marlowe-apps:exe:marlowe-oracle"
  "marlowe-apps:exe:marlowe-pipe"
  "marlowe-apps:exe:marlowe-scaling"
  "marlowe-chain-sync:exe:marlowe-chain-indexer"
  "marlowe-chain-sync:exe:marlowe-chain-sync"
  "marlowe-chain-sync:test:marlowe-chain-sync-test"
  "marlowe-cli:exe:marlowe-cli"
  "marlowe-contracts:test:marlowe-contracts-test"
  "marlowe-integration-tests:exe:marlowe-integration-tests"
  "marlowe-integration:exe:marlowe-integration-example"
  "marlowe-runtime-cli:exe:marlowe"
  "marlowe-runtime-web:exe:marlowe-web-server"
  "marlowe-runtime-web:test:marlowe-runtime-web-test"
  "marlowe-runtime:exe:marlowe-indexer"
  "marlowe-runtime:exe:marlowe-proxy"
  "marlowe-runtime:exe:marlowe-sync"
  "marlowe-runtime:exe:marlowe-tx"
  "marlowe-runtime:test:indexer-test"
  "marlowe-runtime:test:marlowe-runtime-test"
  "marlowe-test:exe:marlowe-reference"
  "marlowe-test:exe:marlowe-spec-client"
  "marlowe-test:test:marlowe-test"
)

NIX_RUN() {
  GC_DONT_GC=1 nix run --no-warn-dirty --accept-flake-config "$1"
}

for run in ${all_runnables[@]}; do
  for ghc in "ghc8107"; do # Excluding ghc924 
    echo "Running .#$ghc.$run" 
    NIX_RUN ".#$ghc.$run"
    echo "Running .#profiled.$ghc.$run" 
    NIX_RUN ".#profiled.$ghc.$run"
  done 
done

echo "Running nix flake check"
nix flake check
