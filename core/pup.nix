{ pkgs ? import <nixpkgs> {} }:

let
  storageDirectory = "/storage";
  dogecoind_bin = pkgs.callPackage (pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/Dogebox-WG/dogebox-nur-packages/6531e850a6e964a9cd4c36671cb9b3b7414d8044/pkgs/dogecoin-core/default.nix";
    sha256 = "sha256-bSl/IKyAV2Gnh7TNDISBVxouQTdI5jmDqTfs6qfdz2w=";
  }) {
    disableWallet = true;
    disableGUI = true;
    disableTests = true;
    enableZMQ = true;
  };

  dogecoind = pkgs.writeScriptBin "run.sh" ''
    #!${pkgs.stdenv.shell}

    # RPC Configuration (from manifest config or defaults)
    ENABLE_RPC="''${ENABLE_RPC:-1}"
    RPCUSER="''${RPC_USERNAME:-dogebox_core_pup_temporary_static_username}"
    RPCPASS="''${RPC_PASSWORD:-dogebox_core_pup_temporary_static_password}"
    RPC_PORT="''${RPC_PORT:-22555}"
    RPC_ALLOWED_IPS="''${RPC_ALLOWED_IPS:-0.0.0.0/0}"

    # Node Features (from manifest config or defaults)
    ENABLE_TXINDEX="''${ENABLE_TXINDEX:-1}"
    ENABLE_ZMQ="''${ENABLE_ZMQ:-1}"

    # Network Configuration (from manifest config or defaults)
    P2P_PORT="''${PORT:-22556}"
    MAXCONNECTIONS="''${MAXCONNECTIONS:-125}"

    # Advanced Configuration (from manifest config or defaults)
    PRUNE="''${PRUNE:-0}"
    DBCACHE="''${DBCACHE:-300}"
    DEBUG="''${DEBUG:-}"

    # User Agent Comment
    UACOMMENT="''${UACOMMENT:-}"

    # ZMQ Advanced (custom endpoints)
    ZMQ_PUBHASHTX="''${ZMQ_PUBHASHTX:-}"
    ZMQ_PUBRAWBLOCK="''${ZMQ_PUBRAWBLOCK:-}"
    ZMQ_PUBRAWTX="''${ZMQ_PUBRAWTX:-}"

    # Wallet Features (disabled by default - cannot be enabled)
    ZAPWALLETTXES="''${ZAPWALLETTXES:-0}"

    # RPC Network Binding
    RPCBIND_ADDRESS="''${RPCBIND_ADDRESS:-}"

    # Persist RPC credentials to storage for monitor/logger access
    echo "$RPCUSER" > /storage/rpcuser.txt
    echo "$RPCPASS" > /storage/rpcpassword.txt

    # Build dogecoind arguments
    if [ "$ENABLE_RPC" = "1" ] || [ "$ENABLE_RPC" = "true" ]; then
      DOGECOIND_ARGS="-port=$P2P_PORT -datadir=${storageDirectory} -rpc=1 -rpcuser=$RPCUSER -rpcpassword=$RPCPASS -rpcport=$RPC_PORT"
    else
      DOGECOIND_ARGS="-port=$P2P_PORT -datadir=${storageDirectory} -rpc=0"
    fi

    # Add RPC configuration only if RPC is enabled
    if [ "$ENABLE_RPC" = "1" ] || [ "$ENABLE_RPC" = "true" ]; then
      # Add RPC bind address (use custom if provided, otherwise use container IP)
      if [ ! -z "$RPCBIND_ADDRESS" ]; then
        DOGECOIND_ARGS="$DOGECOIND_ARGS -rpcbind=$RPCBIND_ADDRESS"
      else
        DOGECOIND_ARGS="$DOGECOIND_ARGS -rpcbind=$DBX_PUP_IP"
      fi

      # Add RPC allowed IPs (comma-separated to individual -rpcallowip flags)
      IFS=',' read -ra IPS <<< "$RPC_ALLOWED_IPS"
      for IP in "''${IPS[@]}"; do
        DOGECOIND_ARGS="$DOGECOIND_ARGS -rpcallowip=$(echo $IP | xargs)"
      done
    fi

    # Add transaction index if enabled
    if [ "$ENABLE_TXINDEX" = "1" ] || [ "$ENABLE_TXINDEX" = "true" ]; then
      DOGECOIND_ARGS="$DOGECOIND_ARGS -txindex=1"
    fi

    # Add ZMQ if enabled
    if [ "$ENABLE_ZMQ" = "1" ] || [ "$ENABLE_ZMQ" = "true" ]; then
      if [ ! -z "$ZMQ_PUBHASHBLOCK" ]; then
        DOGECOIND_ARGS="$DOGECOIND_ARGS -zmqpubhashblock=$ZMQ_PUBHASHBLOCK"
      else
        DOGECOIND_ARGS="$DOGECOIND_ARGS -zmqpubhashblock=tcp://$DBX_PUP_IP:28332"
      fi

      # Add optional ZMQ endpoints if specified
      if [ ! -z "$ZMQ_PUBHASHTX" ]; then
        DOGECOIND_ARGS="$DOGECOIND_ARGS -zmqpubhashtx=$ZMQ_PUBHASHTX"
      fi
      if [ ! -z "$ZMQ_PUBRAWBLOCK" ]; then
        DOGECOIND_ARGS="$DOGECOIND_ARGS -zmqpubrawblock=$ZMQ_PUBRAWBLOCK"
      fi
      if [ ! -z "$ZMQ_PUBRAWTX" ]; then
        DOGECOIND_ARGS="$DOGECOIND_ARGS -zmqpubrawtx=$ZMQ_PUBRAWTX"
      fi
    fi

    # Add user agent comment if specified
    if [ ! -z "$UACOMMENT" ]; then
      DOGECOIND_ARGS="$DOGECOIND_ARGS -uacomment=$UACOMMENT"
    fi

    # Add max connections if not default
    if [ ! -z "$MAXCONNECTIONS" ] && [ "$MAXCONNECTIONS" != "125" ]; then
      DOGECOIND_ARGS="$DOGECOIND_ARGS -maxconnections=$MAXCONNECTIONS"
    fi

    # Add prune if enabled (value in MB, 0 = disabled)
    if [ ! -z "$PRUNE" ] && [ "$PRUNE" != "0" ]; then
      DOGECOIND_ARGS="$DOGECOIND_ARGS -prune=$PRUNE"
    fi

    # Add database cache if not default
    if [ ! -z "$DBCACHE" ] && [ "$DBCACHE" != "300" ]; then
      DOGECOIND_ARGS="$DOGECOIND_ARGS -dbcache=$DBCACHE"
    fi

    # Add debug level if specified
    if [ ! -z "$DEBUG" ]; then
      DOGECOIND_ARGS="$DOGECOIND_ARGS -debug=$DEBUG"
    fi

    # Run dogecoind with constructed arguments
    ${dogecoind_bin}/bin/dogecoind $DOGECOIND_ARGS
  '';

  monitor = pkgs.buildGoModule {
    pname = "monitor";
    version = "0.0.1";
    src = ./monitor;
    vendorHash = null;

    systemPackages = [ dogecoind_bin ];
    
    buildPhase = ''
      export GO111MODULE=off
      export GOCACHE=$(pwd)/.gocache
      go build -ldflags "-X main.pathToDogecoind=${dogecoind_bin}" -o monitor monitor.go
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
  inherit dogecoind monitor logger;
}
