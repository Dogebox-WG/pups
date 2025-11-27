{ pkgs ? import <nixpkgs> {} }:

let
  proxy = pkgs.buildGoModule {
    pname = "rpc-proxy";
    version = "0.0.1";
    src = ./proxy;
    vendorHash = null;

    buildPhase = ''
      export GO111MODULE=off
      export GOCACHE=$(pwd)/.gocache
      go build -o rpc-proxy proxy.go
    '';

    installPhase = ''
      mkdir -p $out/bin
      cp rpc-proxy $out/bin/
    '';
  };
in
{
  rpc-proxy = proxy;
}
