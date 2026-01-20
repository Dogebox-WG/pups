{ pkgs ? import <nixpkgs> {} }:

let
  storageDirectory = "/storage";
  spvnode_bin = pkgs.callPackage (pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/Dogebox-WG/dogebox-nur-packages/77dc446e14e1fb691e67b186da013ebef92c7ca7/pkgs/libdogecoin/default.nix";
    sha256 = "sha256-9RNu1IA703gNqnpDdZ6feEI5WOBDjsOvdRaWeJBNxJg=";
  }) {
  };

  awk = pkgs.gawk;
  host = pkgs.host;

  spvnode = pkgs.writeScriptBin "run.sh" ''
    #!${pkgs.stdenv.shell}

    # Ensure delegated.extended.key exists
    if [ ! -f "${storageDirectory}/delegated.extended.key" ]; then
        echo "Error: delegated.extended.key not found"
        exit 1
    fi

    # Derive a few external addresses from the delegated extended key
    ADDRESS0=$(${spvnode_bin}/bin/such -c derive_child_keys -m "m/0/0" -p "$(cat ${storageDirectory}/delegated.extended.key)" | ${awk}/bin/awk '/p2pkh address:/ {print $3}')
    ADDRESS1=$(${spvnode_bin}/bin/such -c derive_child_keys -m "m/0/1" -p "$(cat ${storageDirectory}/delegated.extended.key)" | ${awk}/bin/awk '/p2pkh address:/ {print $3}')
    ADDRESS2=$(${spvnode_bin}/bin/such -c derive_child_keys -m "m/0/2" -p "$(cat ${storageDirectory}/delegated.extended.key)" | ${awk}/bin/awk '/p2pkh address:/ {print $3}')

    # Wait until DNS resolves 'seed.multidoge.org' and 'seed2.multidoge.org'
    sleep 1
    ${host}/bin/host -w seed.multidoge.org
    ${host}/bin/host -w seed2.multidoge.org

    # Run spvnode with the addresses
    ${spvnode_bin}/bin/spvnode \
      -c -b -p -l \
      -a "$ADDRESS0 $ADDRESS1 $ADDRESS2" \
      -w "${storageDirectory}/wallet.db" \
      -f "${storageDirectory}/headers.db" \
      -u "0.0.0.0:8888" \
      scan 2>&1 | tee -a "${storageDirectory}/output.log"
  '';

  monitor = pkgs.buildGoModule {
    pname = "monitor";
    version = "0.0.1";
    src = ./monitor;
    vendorHash = null;

    systemPackages = [ spvnode_bin ];

    buildPhase = ''
      export GO111MODULE=off
      export GOCACHE=$(pwd)/.gocache
      go build -ldflags "-X main.pathToSpvnode=${spvnode_bin}" -o monitor monitor.go
    '';

    installPhase = ''
      mkdir -p $out/bin
      cp monitor $out/bin/
    '';
  };

  logger = pkgs.buildGoModule {
    pname = "logger";
    version = "0.0.1";
    src = ./logger;
    vendorHash = null;

    buildPhase = ''
      export GO111MODULE=off
      export GOCACHE=$(pwd)/.gocache
      go build -ldflags "-X main.storageDirectory=${storageDirectory}" -o logger logger.go
    '';

    installPhase = ''
      mkdir -p $out/bin
      cp logger $out/bin/
    '';
  };

in
{
  inherit spvnode monitor logger awk host;
}
