{ pkgs ? import <nixpkgs> {} }:

let
  proxy = pkgs.buildGoModule {
    pname = "remote-proxy";
    version = "0.0.1";
    src = ./proxy;
    vendorHash = null;

    buildPhase = ''
      export GO111MODULE=off
      export GOCACHE=$(pwd)/.gocache
      go build -o remote-proxy proxy.go
    '';

    installPhase = ''
      mkdir -p $out/bin
      cp remote-proxy $out/bin/
    '';
  };

  monitor = pkgs.buildGoModule {
    pname = "remote-monitor";
    version = "0.0.1";
    src = ./monitor;
    vendorHash = null;

    buildPhase = ''
      export GO111MODULE=off
      export GOCACHE=$(pwd)/.gocache
      go build -o remote-monitor monitor.go
    '';

    installPhase = ''
      mkdir -p $out/bin
      cp remote-monitor $out/bin/
    '';
  };
in
{
  remote-proxy = proxy;
  remote-monitor = monitor;
}
