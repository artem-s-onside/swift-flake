{
  description = "Swift binaries flake";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";

    swift_61_linux = {
      url = "https://download.swift.org/swift-6.1-release/ubi9/swift-6.1-RELEASE/swift-6.1-RELEASE-ubi9.tar.gz";
      flake = false;
    };
    swift_61_macos = {
      url = "https://download.swift.org/swift-6.1-release/xcode/swift-6.1-RELEASE/swift-6.1-RELEASE-osx.pkg";
      flake = false;
    };

    swift_snapshot_linux = {
      url = "https://download.swift.org/development/ubi9/swift-DEVELOPMENT-SNAPSHOT-2025-03-28-a/swift-DEVELOPMENT-SNAPSHOT-2025-03-28-a-ubi9.tar.gz";
      flake = false;
    };
    swift_snapshot_macos = {
      url = "https://download.swift.org/development/xcode/swift-DEVELOPMENT-SNAPSHOT-2025-03-28-a/swift-DEVELOPMENT-SNAPSHOT-2025-03-28-a-osx.pkg";
      flake = false;
    };
  };

  outputs =
    { self
    , nixpkgs
    , flake-utils
    , swift_61_linux
    , swift_61_macos
    , swift_snapshot_linux
    , swift_snapshot_macos
    }:
      with flake-utils.lib; with system; eachSystem [ x86_64-linux aarch64-linux aarch64-darwin ] (system:
      let
        sources = (nixpkgs.lib.importJSON ./flake.lock).nodes;
        pkgs = nixpkgs.legacyPackages.${system};
        swift = with pkgs; callPackage ./build.nix {
          src =
            if stdenv.hostPlatform.system == "x86_64-linux" then swift_61_linux
            else if stdenv.hostPlatform.system == "aarch64-darwin" then swift_61_macos
            else throw "Unsupproted system: ${stdenv.hostPlatform.system}";
          version = "6.1-RELEASE";
        };
        swift_snapshot = with pkgs; callPackage ./build.nix {
          src =
            if stdenv.hostPlatform.system == "x86_64-linux" then swift_snapshot_linux
            else if stdenv.hostPlatform.system == "aarch64-darwin" then swift_snapshot_macos
            else throw "Unsupproted system: ${stdenv.hostPlatform.system}";
          version = "DEVELOPMENT-SNAPSHOT-2025-03-28-a";
        };
        derivation = { inherit swift swift_snapshot; };
      in
      rec {
        packages = derivation // {
          inherit swift;
          default = swift;
        };
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
