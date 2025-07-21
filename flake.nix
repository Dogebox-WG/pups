{
  description = "This flake is used for building all pups (specifically for populating our binary caches)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/50ab793786d9de88ee30ec4e4c24fb4236fc2674";

  outputs = { self, nixpkgs }:
  let
    systems = [ "x86_64-linux" "aarch64-linux" ];
    forAllSystems = f:
      builtins.listToAttrs (map (system: { name = system; value = f system; }) systems);

    findPupFiles = dir:
      let
        recurse = path:
          let
            contents = builtins.readDir path;
          in builtins.concatLists (
            builtins.attrValues (
              builtins.mapAttrs (name: type:
                if type == "directory" then recurse (path + "/${name}")
                else if name == "pup.nix" then [ (path + "/${name}") ]
                else []
              ) contents
            )
          );
      in recurse dir;

    pupFiles = findPupFiles ./.;

  in {
    packages = forAllSystems (system:
      let
        pkgs = import nixpkgs { inherit system; };
        lib = pkgs.lib;

        makeName = path: builtins.baseNameOf (builtins.dirOf path);

        rawModules = map (file:
          let
            result = pkgs.callPackage file {};
            derivs = builtins.attrValues (lib.filterAttrs (_: v: lib.isDerivation v) result);
          in {
            name = makeName file;
            derivations = derivs;
          }
        ) pupFiles;

      in
        builtins.listToAttrs (
          map (mod: {
            name = mod.name;
            value = pkgs.buildEnv {
              name = mod.name;
              paths = mod.derivations;
            };
          }) rawModules
        )
    );
  };
}
