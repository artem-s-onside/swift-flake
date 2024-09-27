{ pkgs, src }:

# TODO: add bootstrap version https://forums.swift.org/t/building-the-swift-project-on-linux-with-lld-instead-of-gold/73303/24

with pkgs;

let
  version = "6.0.1";
  src = fetchurl {
    url = "https://download.swift.org/swift-${version}-release/ubi9/swift-${version}-RELEASE/swift-${version}-RELEASE-ubi9.tar.gz";
    hash = "sha256-MQbDGfL+BgaI8tW4LNRPp5WjivFqIhfPX7vyfjA9mC4=";
  };
in stdenv.mkDerivation {
  inherit src version;

  name = "swift";

  buildInputs = [ makeWrapper ];

  phases = [ "installPhase" "checkPhase" ];

  installPhase = ''
    mkdir $out
    tar --strip-components=2 -xf $src -C $out

    rpath=$rpath''${rpath:+:}$out/lib
    rpath=$rpath''${rpath:+:}$out/lib/swift/host
    rpath=$rpath''${rpath:+:}$out/lib/swift/linux
    rpath=$rpath''${rpath:+:}${stdenv.cc.cc.lib}/lib
    rpath=$rpath''${rpath:+:}${stdenv.cc.cc}/lib
    rpath=$rpath''${rpath:+:}${sqlite.out}/lib
    rpath=$rpath''${rpath:+:}${ncurses}/lib
    rpath=$rpath''${rpath:+:}${libuuid.lib}/lib
    rpath=$rpath''${rpath:+:}${zlib}/lib
    rpath=$rpath''${rpath:+:}${curl.out}/lib
    rpath=$rpath''${rpath:+:}${libxml2.out}/lib
    rpath=$rpath''${rpath:+:}${python39.out}/lib
    rpath=$rpath''${rpath:+:}${libedit}/lib

    # set all the dynamic linkers
    find $out/bin -type f -perm -0100 \
        -exec patchelf --interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
        --set-rpath "$rpath" {} \;

    find $out/lib -name "*.so" -exec patchelf --set-rpath "$rpath" --force-rpath {} \;

    cp -r ${stdenv.cc.libc.dev}/include/* $out/lib/clang/17/include/
  '';

  doCheck = true;
  checkPhase = ''
    $out/bin/swift --version
  '';
}
