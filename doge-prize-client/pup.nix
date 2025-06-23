{ pkgs ? import <nixpkgs> {} }:

let
  # Node.js version for Next.js
  nodejs = pkgs.nodejs_20;
  
  # Build the Next.js application
  doge-prize-client = pkgs.buildNpmPackage {
    pname = "doge-prize-client";
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
    '';
  };

  # Create a script to run the Next.js application
  run-script = pkgs.writeScriptBin "run.sh" ''
    #!${pkgs.stdenv.shell}
    
    cd ${doge-prize-client}
    
    # Set environment variables
    export NODE_ENV=production
    export CONFIG_ENV=production
    export PORT=3643
    export HOSTNAME=0.0.0.0
    
    # Install production dependencies
    npm ci --only=production
    
    # Start the Next.js application
    exec ${nodejs}/bin/node node_modules/.bin/next start -p 3643 -H 0.0.0.0
  '';

in
{
  inherit run-script;
  "doge-prize-client" = run-script;
}
