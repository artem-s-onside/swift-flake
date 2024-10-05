{ pkgs
, src
, replaceLlvm ? pkgs.stdenv.isLinux
, replaceClang ? pkgs.stdenv.isLinux
, replaceLld ? pkgs.stdenv.isLinux
}:

# TODO: add bootstrap version https://forums.swift.org/t/building-the-swift-project-on-linux-with-lld-instead-of-gold/73303/24

with pkgs;

let
  version = "6.0.1";

  src =
    if stdenv.hostPlatform.system == "x86_64-linux" then
      fetchurl {
        url = "https://download.swift.org/swift-${version}-release/ubi9/swift-${version}-RELEASE/swift-${version}-RELEASE-ubi9.tar.gz";
        hash = "sha256-MQbDGfL+BgaI8tW4LNRPp5WjivFqIhfPX7vyfjA9mC4=";
      }
    else if stdenv.hostPlatform.system == "aarch64-darwin" then
      fetchurl {
        url = "https://download.swift.org/swift-${version}-release/xcode/swift-${version}-RELEASE/swift-${version}-RELEASE-osx.pkg";
        hash = "sha256-kkqezUwvj2/ihKsMlmMF4y65jRfUq/pHKJuwoGH3L4k=";
      }
    else throw "Unsupproted system: ${stdenv.hostPlatform.system}";

  llvm = llvmPackages_17;
  clang = llvm.clang;
  stdenv = llvm.stdenv;

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

  buildInputs = [ makeWrapper ]
    ++ lib.optionals stdenv.isDarwin [ xar cpio ];

  phases = [ "unpackPhase" "installPhase" "checkPhase" ];

  unpackPhase = lib.optionalString stdenv.isLinux ''
    tar --strip-components=1 -xf $src
  '' + lib.optionalString stdenv.isDarwin ''
    xar -xf $src
    zcat < swift-${version}-RELEASE-osx-package.pkg/Payload | cpio -i
  '';

  installPhase = ''
    cp -R . $out
    mkdir $out/bin
  '' + lib.optionalString replaceClang ''
    rm -rf $out/usr/bin/clang-17 $out/usr/bin/clangd $out/usr/lib/clang

    ln -s ${clang}/bin/clang $out/usr/bin/clang-17
    ln -s ${llvm.clang-unwrapped}/bin/clangd $out/usr/bin/clangd
    ln -s ${libclang.lib}/lib/clang $out/usr/lib/clang
  '' + lib.optionalString replaceLld ''
    rm -rf $out/usr/bin/lld

    ln -s ${llvm.lld}/bin/lld $out/usr/bin/lld
  '' + lib.optionalString replaceLlvm ''
    for executable in llvm-ar llvm-cov llvm-profdata; do
      rm -rf $out/usr/bin/$executable
      ln -s ${llvm.llvm}/bin/$executable $out/usr/bin/$executable
    done
  '' + lib.optionalString stdenv.isDarwin ''
    ln -s $out/usr/bin/swift-driver $out/bin/swift
  '' + lib.optionalString stdenv.isLinux ''
    rpath=$rpath''${rpath:+:}$out/usr/lib
    rpath=$rpath''${rpath:+:}$out/usr/lib/swift/host
    rpath=$rpath''${rpath:+:}$out/usr/lib/swift/linux
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
    find $out/usr/bin -type f -perm -0100 \
      -exec patchelf --interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
      --set-rpath "$rpath" {} \;

    find $out/usr/lib -name "*.so" -exec patchelf --set-rpath "$rpath" --force-rpath {} \;

    rm $out/usr/bin/swift
    swiftDriver="$out/usr/bin/swift-frontend" \
      prog=$out/usr/bin/swift \
      substituteAll '${./build/wrapper.sh}' $out/usr/bin/.swift-wrapper

    cat > $out/bin/swift <<-EOF
    #!${runtimeShell}
    ${fhsEnv}/bin/swift-env $out/usr/bin/.swift-wrapper "\$@"
    EOF

    chmod +x $out/usr/bin/.swift-wrapper $out/bin/swift

    mkdir -p $out/nix-support
    substituteAll ${./build/setup-hook.sh} $out/nix-support/setup-hook
  '';

  doCheck = stdenv.isLinux; # TODO: macOS
  checkPhase = ''
    $out/bin/swift --version
  '';
})
