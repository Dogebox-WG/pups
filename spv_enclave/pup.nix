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
  util-linux = pkgs.util-linux;
  optee_libdogecoin = pkgs."libdogecoin-optee-host";

  spvnode = pkgs.writeScriptBin "run.sh" ''
    #!${pkgs.stdenv.shell}

    # Ensure delegated.extended.key exists
    if [ ! -f "${storageDirectory}/delegated.extended.key" ]; then
        echo "Error: delegated.extended.key not found"
        exit 1
    fi

    # Generate a mnemonic with the libdogecoin key management enclave
    if [ ! -f "${storageDirectory}/present" ]; then
        # YubiKey (TOTP) path
        { sleep 1; printf '\n'; sleep 1; printf 'y\n'; } | \
          SHELL=/run/current-system/sw/bin/bash \
          ${util-linux}/bin/script -q -e -c "${optee_libdogecoin}/bin/optee_libdogecoin -c generate_mnemonic -z" /dev/null 2>&1 | tee "${storageDirectory}/present"

        # Give the TEE a moment
        sleep 1

        # Derive a few addresses in the enclave from the mnemonic
        ADDRESS0=$(${optee_libdogecoin}/bin/optee_libdogecoin -c generate_address -z -o 0 -l 0 -i 0 | ${awk}/bin/awk '/Address generated:/ {print $3}')
        ADDRESS1=$(${optee_libdogecoin}/bin/optee_libdogecoin -c generate_address -z -o 0 -l 0 -i 1 | ${awk}/bin/awk '/Address generated:/ {print $3}')
        ADDRESS2=$(${optee_libdogecoin}/bin/optee_libdogecoin -c generate_address -z -o 0 -l 0 -i 2 | ${awk}/bin/awk '/Address generated:/ {print $3}')
    fi

    # Wait until DNS resolves 'seed.multidoge.org'
    ${host}/bin/host -w seed.multidoge.org

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
  pupEnclave = true;

  imports = [ (pkgs.nixosModules.tee-supplicant) ];

  inherit spvnode monitor logger awk host util-linux;

  services.tee-supplicant = {
    enable = true;
    trustedApplications = [
      "${pkgs.optee-os-rockchip-rk3588.devkit}/ta/023f8f1a-292a-432b-8fc4-de8471358067.ta"
      "${pkgs.optee-os-rockchip-rk3588.devkit}/ta/80a4c275-0a47-4905-8285-1486a9771a08.ta"
      "${pkgs.optee-os-rockchip-rk3588.devkit}/ta/f04a0fe7-1f5d-4b9b-abf7-619b85b4ce8c.ta"
      "${pkgs.optee-os-rockchip-rk3588.devkit}/ta/fd02c9da-306c-48c7-a49c-bbd827ae86ee.ta"
      "${pkgs.libdogecoin-optee-ta}/ta/62d95dc0-7fc2-4cb3-a7f3-c13ae4e633c4.ta"
    ];
  };
}
