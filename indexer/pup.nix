{ pkgs ? import <nixpkgs> {} }:

let
  postgres = pkgs.postgresql_16;
  storageDirectory = "/storage";

  indexer-bin = pkgs.buildGoModule {
    pname = "indexer";
    version = "0.0.1";
    src = builtins.fetchGit {
      url = "https://github.com/dogeorg/indexer.git";
      ref = "feature/balances-cache";
    };
    vendorHash = "sha256-BR8PgFgi7KoHQLfKprrHfLhh939JAhanW5JzOMLrx8M=";

    nativeBuildInputs = [
      pkgs.go_1_24
      pkgs.pkg-config
    ];

    buildInputs = [
      pkgs.sqlite
      pkgs.zeromq
    ];

    buildPhase = ''
      export CGO_ENABLED=1
      go build -o indexer .
    '';

    installPhase = ''
      mkdir -p $out/bin
      cp indexer $out/bin/
    '';
  };

  indexer = pkgs.writeShellScriptBin "run.sh" ''
    set -eu

    PGDATA="${storageDirectory}/postgres"
    PGSOCKET="${storageDirectory}/postgres-run"
    PGPORT="5432"
    PGUSER="indexer"
    PGDATABASE="indexer"
    PGPASSFILE="${storageDirectory}/postgres-password.txt"

    mkdir -p "$PGDATA" "$PGSOCKET"

    if [ ! -f "$PGPASSFILE" ]; then
      printf '%s\n' "''${INDEXER_DB_PASSWORD:-dogebox_indexer_pup_temporary_static_password}" > "$PGPASSFILE"
      chmod 600 "$PGPASSFILE"
    fi
    PGPASSWORD="$(cat "$PGPASSFILE")"
    export PGPASSWORD

    if [ ! -s "$PGDATA/PG_VERSION" ]; then
      ${postgres}/bin/initdb \
        -D "$PGDATA" \
        --username=postgres \
        --auth-local=trust \
        --auth-host=scram-sha-256

      cat >> "$PGDATA/pg_hba.conf" <<EOF
host all all 0.0.0.0/0 scram-sha-256
EOF
    fi

    ${postgres}/bin/pg_ctl \
      -D "$PGDATA" \
      -o "-h $DBX_PUP_IP -k $PGSOCKET -p $PGPORT" \
      -w start

    stop_postgres() {
      ${postgres}/bin/pg_ctl -D "$PGDATA" -m fast -w stop >/dev/null 2>&1 || true
    }
    trap stop_postgres EXIT INT TERM

    if ! ${postgres}/bin/psql -h "$PGSOCKET" -p "$PGPORT" -U postgres -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname = '$PGUSER'" | grep -q 1; then
      ${postgres}/bin/psql -h "$PGSOCKET" -p "$PGPORT" -U postgres -d postgres -c "CREATE USER $PGUSER WITH PASSWORD '$PGPASSWORD'"
    fi

    if ! ${postgres}/bin/psql -h "$PGSOCKET" -p "$PGPORT" -U postgres -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '$PGDATABASE'" | grep -q 1; then
      ${postgres}/bin/createdb -h "$PGSOCKET" -p "$PGPORT" -U postgres -O "$PGUSER" "$PGDATABASE"
    fi

    ${indexer-bin}/bin/indexer \
      -dburl="postgres://$PGUSER:$PGPASSWORD@/$PGDATABASE?host=$PGSOCKET&sslmode=disable" \
      -rpchost="$DBX_IFACE_CORE_RPC_HOST" \
      -rpcport="$DBX_IFACE_CORE_RPC_PORT" \
      -rpcuser="dogebox_core_pup_temporary_static_username" \
      -rpcpass="dogebox_core_pup_temporary_static_password" \
      -zmqhost="$DBX_IFACE_CORE_ZMQ_HOST" \
      -zmqport="$DBX_IFACE_CORE_ZMQ_PORT" \
      -bindapi="$DBX_PUP_IP:8000" \
      -chain="mainnet" \
      -startingheight="''${STARTING_HEIGHT:-0}" \
      -cache-balances="''${CACHE_BALANCES:-true}"
  '';

  monitor = pkgs.buildGoModule {
    pname = "indexer-monitor";
    version = "0.0.1";
    src = ./monitor;
    vendorHash = null;

    buildPhase = ''
      export GO111MODULE=off
      export GOCACHE=$(pwd)/.gocache
      go build -o monitor monitor.go
    '';

    installPhase = ''
      mkdir -p $out/bin
      cp monitor $out/bin/
    '';
  };
in
{
  inherit indexer monitor;
}
