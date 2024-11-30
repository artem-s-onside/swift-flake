{
  description = "Swift binaries flake";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    with flake-utils.lib; with system; eachSystem [ x86_64-linux aarch64-linux aarch64-darwin ] (system:
      let
        sources = (nixpkgs.lib.importJSON ./flake.lock).nodes;
        pkgs = nixpkgs.legacyPackages.${system};
        swift = pkgs.callPackage ./build.nix { };
        derivation = { inherit swift; };
      in
      rec {
        packages = derivation // { default = swift; };
        legacyPackages = pkgs.extend overlay;
        nixosModules.default = {
          nixpkgs.overlays = [ overlay ];
        };
        overlay = final: prev: derivation;
        devShell = pkgs.mkShell {
          name = "env";
          buildInputs = [ swift ];
        };
        formatter = nixpkgs.legacyPackages.${system}.nixpkgs-fmt;
      });
}
