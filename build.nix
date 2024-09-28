{ pkgs
, src
, replaceLlvm ? true
, replaceClang ? true
, replaceLld ? true
}:

# TODO: add bootstrap version https://forums.swift.org/t/building-the-swift-project-on-linux-with-lld-instead-of-gold/73303/24

with pkgs;

let
  version = "6.0.1";
  src = fetchurl {
    url = "https://download.swift.org/swift-${version}-release/ubi9/swift-${version}-RELEASE/swift-${version}-RELEASE-ubi9.tar.gz";
    hash = "sha256-MQbDGfL+BgaI8tW4LNRPp5WjivFqIhfPX7vyfjA9mC4=";
  };

  llvm = llvmPackages_17;
  clang = llvm.clang;

  fhsEnv = buildFHSEnv {
    name = "swift-env";
    targetPkgs = pkgs: (with pkgs;
      lib.optionals replaceLlvm [ llvm.llvm ]
      ++ lib.optionals replaceLld [ llvm.lld ]
      ++ lib.optionals replaceClang [ clang ]
    );
    multiPkgs = pkgs: (with pkgs; [ stdenv.cc.cc stdenv.cc.libc stdenv.cc.libc.dev ]);
  };

  wrapperParams = rec {
    inherit bintools;

    default_cc_wrapper = clang;
    coreutils_bin = lib.getBin coreutils;
    gnugrep_bin = gnugrep;
    suffixSalt = lib.replaceStrings [ "-" "." ] [ "_" "_" ] targetPlatform.config;
    use_response_file_by_default = 1;

    swiftOs =
      if targetPlatform.isDarwin
      then {
        "macos" = "macosx";
        "ios" = "iphoneos";
        #iphonesimulator
        #appletvos
        #appletvsimulator
        #watchos
        #watchsimulator
      }.${targetPlatform.darwinPlatform}
        or (throw "Cannot build Swift for target Darwin platform '${targetPlatform.darwinPlatform}'")
      else targetPlatform.parsed.kernel.name;

    # Apple Silicon uses a different CPU name in the target triple.
    swiftArch =
      if stdenv.isDarwin && stdenv.isAarch64 then "arm64"
      else targetPlatform.parsed.cpu.name;

    # On Darwin, a `.swiftmodule` is a subdirectory in `lib/swift/<OS>`,
    # containing binaries for supported archs. On other platforms, binaries are
    # installed to `lib/swift/<OS>/<ARCH>`. Note that our setup-hook also adds
    # `lib/swift` for convenience.
    swiftLibSubdir = "lib/swift/${swiftOs}";
    swiftModuleSubdir =
      if hostPlatform.isDarwin
      then "lib/swift/${swiftOs}"
      else "lib/swift/${swiftOs}/${swiftArch}";

    # And then there's also a separate subtree for statically linked  modules.
    swiftStaticLibSubdir = lib.replaceStrings [ "/swift/" ] [ "/swift_static/" ] swiftLibSubdir;
    swiftStaticModuleSubdir = lib.replaceStrings [ "/swift/" ] [ "/swift_static/" ] swiftModuleSubdir;
  };

in
stdenv.mkDerivation (wrapperParams // {
  inherit src version;

  name = "swift";

  buildInputs = [ makeWrapper ];

  phases = [ "installPhase" "checkPhase" ];

  installPhase = ''
    mkdir -p $out/nix-support

    tar --strip-components=2 -xf $src -C $out
  '' + lib.optionalString replaceClang ''
    rm -rf $out/bin/clang-17 $out/bin/clangd $out/lib/clang

    ln -s ${clang}/bin/clang $out/bin/clang-17
    ln -s ${llvm.clang-unwrapped}/bin/clangd $out/bin/clangd
    ln -s ${libclang.lib}/lib/clang $out/lib/clang
  '' + lib.optionalString replaceLld ''
    rm -rf $out/bin/lld

    ln -s ${llvm.lld}/bin/lld $out/bin/lld
  '' + lib.optionalString replaceLlvm ''
    for executable in llvm-ar llvm-cov llvm-profdata; do
      rm -rf $out/bin/$executable
      ln -s ${llvm.llvm}/bin/$executable $out/bin/$executable
    done
  '' + ''
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

    rm $out/bin/swift
    swiftDriver="$out/bin/swift-frontend" \
      prog=$out/bin/swift \
      substituteAll '${./build/wrapper.sh}' $out/bin/.swift-wrapper

    cat > $out/bin/swift <<-EOF
    #!${runtimeShell}
    ${fhsEnv}/bin/swift-env $out/bin/.swift-wrapper "\$@"
    EOF

    chmod +x $out/bin/.swift-wrapper $out/bin/swift

    substituteAll ${./build/setup-hook.sh} $out/nix-support/setup-hook
  '';

  doCheck = true;
  checkPhase = ''
    $out/bin/swift --version
  '';
})
