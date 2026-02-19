{ pkgs ? import <nixpkgs> {} }:

let
  gigawallet_bin = pkgs.buildGoModule {
  pname = "gigawallet";
  version = "1.0.1";

  src = pkgs.fetchgit {
    url = "https://github.com/dogecoinfoundation/gigawallet.git";
    rev = "refs/tags/v1.0.1";
    hash = "sha256-PIKb4WnhJVE4Cj/UqAxeB8C/7An+UvpEemubziz4YNk=";
  };

  vendorHash = "sha256-mW5SStSabjWIlLWarI0OfyCTRWRQnEbk2BXabJCJ2h4";

  nativeBuildInputs = [
    pkgs.go_1_24
    pkgs.pkg-config
  ];

  buildInputs = [
    pkgs.zeromq
  ];

  # This is needed because gigawallet depends on things that have native, vendored header files.
  proxyVendor = true;

  buildPhase = ''
    go build -tags libdogecoin -o gigawallet ./cmd/gigawallet
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp gigawallet $out/bin/
  '';
};

  gigawallet = pkgs.writeScriptBin "run.sh" ''
#!${pkgs.stdenv.shell}

if [ ! -d "/storage/.gigawallet" ]; then
  mkdir /storage/.gigawallet
fi

  cat <<EOF > /storage/.gigawallet/dogebox.toml
[WebAPI]
  adminbind = "$DBX_PUP_IP"
  adminport = "8081"
  pubbind = "$DBX_PUP_IP"
  pubport = "8082"
  pubapirooturl = "http://localhost:8082"

[Store]
DBFile = "/storage/gigawallet.db"

[gigawallet]
  network = "mainnet"

[dogecoind.mainnet]
  host    = "$DBX_IFACE_CORE_ZMQ_HOST"
  zmqport = $DBX_IFACE_CORE_ZMQ_PORT
  rpchost = "$DBX_IFACE_CORE_RPC_HOST"
  rpcport = $DBX_IFACE_CORE_RPC_PORT
  rpcpass = "dogebox_core_pup_temporary_static_password"
  rpcuser = "dogebox_core_pup_temporary_static_username"
EOF

HOME=/storage GIGA_ENV=dogebox ${gigawallet_bin}/bin/gigawallet server
  '';
in
{
  inherit gigawallet;
}
