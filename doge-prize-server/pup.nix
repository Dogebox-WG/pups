{ pkgs ? import <nixpkgs> {} }:

let
  # Node.js version for Next.js
  nodejs = pkgs.nodejs_20;
  
  # Generate a secure NextAuth secret
  nextauth-secret = pkgs.runCommand "nextauth-secret" {} ''
    ${pkgs.openssl}/bin/openssl rand -base64 32 > $out
  '';
  
  # Build the Next.js application
  doge-prize-server = pkgs.buildNpmPackage {
    pname = "doge-prize-server";
    version = "1.0.0";
    src = ./.;
    
    npmDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; # This will need to be updated
    
    nativeBuildInputs = [ nodejs ];
    
    buildPhase = ''
      export HOME=$TMPDIR
      npm ci
      npm run build
    '';
    
    installPhase = ''
      mkdir -p $out
      cp -r .next $out/
      cp -r public $out/ 2>/dev/null || true
      cp package.json $out/
      cp next.config.js $out/ 2>/dev/null || true
      cp -r prisma $out/ 2>/dev/null || true
    '';
  };

  # Create a script to run the Next.js application
  run-script = pkgs.writeScriptBin "run.sh" ''
    #!${pkgs.stdenv.shell}
    
    cd ${doge-prize-server}
    
    # Set environment variables
    export NODE_ENV=production
    export CONFIG_ENV=production
    export PORT=3644
    export HOSTNAME=0.0.0.0
    
    # Database Configuration
    export DATABASE_URL="file:./prisma/dev.db"
    
    # NextAuth Configuration
    export NEXTAUTH_SECRET="$(cat ${nextauth-secret})"
    export NEXTAUTH_URL="http://localhost:3644"
    
    # Dogecoin RPC Configuration
    export DOGECOIN_RPC_HOST="127.0.0.1"
    export DOGECOIN_RPC_PORT="22555"
    export DOGECOIN_RPC_USER=""
    export DOGECOIN_RPC_PASSWORD=""
    
    # Install production dependencies
    npm ci --only=production
    
    # Run Prisma migrations if needed
    if [ -f "prisma/schema.prisma" ]; then
      npx prisma migrate deploy 2>/dev/null || true
    fi
    
    # Start the Next.js application
    exec ${nodejs}/bin/node node_modules/.bin/next start -p 3644 -H 0.0.0.0
  '';

in
{
  inherit run-script;
  "doge-prize-server" = run-script;
}
