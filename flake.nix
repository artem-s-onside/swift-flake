{
  description = "Swift binaries flake";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    with flake-utils.lib; with system; eachSystem [ x86_64-linux aarch64-linux aarch64-darwin ]
      (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};

          sources = with pkgs; {
            swift_61 = rec {
              version = "6.1-RELEASE";
              x86_64-linux = fetchurl {
                url = "https://download.swift.org/swift-${lib.toLower version}/ubi9/swift-${version}/swift-${version}-ubi9.tar.gz";
                # sha256 = lib.fakeSha256;
                hash = "sha256-oHlAFdbpz8DzfbOAht6MUk44oIZEl3NfjQJpnMWYuqM=";
              };
              aarch64-darwin = fetchurl {
                url = "https://download.swift.org/swift-${lib.toLower version}/xcode/swift-${version}/swift-${version}-osx.pkg";
                # sha256 = lib.fakeSha256;
                hash = "sha256-pwLRl2xlo85HGKEByzxF8RyW0WEYU2ZsL0XbpSPz0WU=";
              };
            };

            swift_snapshot = rec {
              version = "DEVELOPMENT-SNAPSHOT-2025-04-03-a";
              x86_64-linux = fetchurl {
                url = "https://download.swift.org/development/ubi9/swift-${version}/swift-${version}-ubi9.tar.gz";
                # sha256 = lib.fakeSha256;
                hash = "sha256-dUFNohTEYopB84p3fMV2/xnLWxGInIMD0nFsiDx0TYY=";
              };
              aarch64-darwin = fetchurl {
                url = "https://download.swift.org/development/xcode/swift-${version}/swift-${version}-osx.pkg";
                # sha256 = lib.fakeSha256;
                hash = "sha256-qBoMhhUglsDir9J2/48a84phOOQV01aBItugyvFogoI=";
              };
            };
          };

          swift = with pkgs; callPackage ./build.nix {
            inherit (sources.swift_61) version;
            src = sources.swift_61.${system};
          };
          swift_snapshot = with pkgs; callPackage ./build.nix {
            inherit (sources.swift_snapshot) version;
            src = sources.swift_snapshot.${system};
          };
          derivation = { inherit swift swift_snapshot; };
        in
        rec {
          packages = derivation // { default = swift; };
          devShells.default = pkgs.mkShell {
            name = "env";
            buildInputs = [ swift ];
          };
          checks.hashes = pkgs.runCommand "hashes" { } ''
            mkdir -p $out

            ${nixpkgs.lib.concatStringsSep "\n" (
              builtins.concatLists (
                nixpkgs.lib.mapAttrsToList (swiftName: swiftAttr:
                  nixpkgs.lib.mapAttrsToList (platform: src:
                    if builtins.isAttrs src && src ? type && src.type == "derivation"
                    then "echo '${swiftName}.${platform} hash verified: ${src}' >> $out/success"
                    else ""
                  ) swiftAttr
                ) sources
              )
            )}
          '';
          formatter = nixpkgs.legacyPackages.${system}.nixpkgs-fmt;
        }) // {
      nixosModules.default = {
        nixpkgs.overlays = [ overlays.default ];
      };
      overlays.default = final: prev: {
        inherit (self.packages.${prev.stdenv.hostPlatform.system}) swift swift_snapshot;
      };
    };
}
