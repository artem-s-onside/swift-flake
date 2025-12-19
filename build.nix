{ pkgs
, src
, version
}:

# TODO: add bootstrap version https://forums.swift.org/t/building-the-swift-project-on-linux-with-lld-instead-of-gold/73303/24

with pkgs;

let
  llvm = llvmPackages_19;
  clang = llvm.clang;
  stdenv = llvm.stdenv;

  fhsEnv = buildFHSEnv {
    name = "swift-env";
    targetPkgs = pkgs: [ llvm.llvm llvm.lld clang ];
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

  unpackPhase = lib.optionalString stdenv.isDarwin ''
    xar -xf $src
    zcat < swift-${version}-osx-package.pkg/Payload | cpio -i
  '';

  installPhase = ''
    cp -R . $out
    mkdir $out/bin

    for progName in swift-symbolgraph-extract swift-autolink-extract; do
      ln -s $out/usr/bin/swift-frontend $out/bin/$progName
    done

    rm -rf $out/usr/bin/clang-17 $out/usr/bin/clangd \
      $out/usr/bin/lld

    ln -s ${clang}/bin/clang $out/usr/bin/clang-17
    ln -s ${llvm.clang-unwrapped}/bin/clangd $out/usr/bin/clangd

    ln -s ${llvm.lld}/bin/lld $out/usr/bin/lld

    for executable in llvm-ar llvm-cov llvm-profdata; do
      rm -rf $out/usr/bin/$executable
      ln -s ${llvm.llvm}/bin/$executable $out/usr/bin/$executable
    done

    swift=$out
  '' + lib.optionalString stdenv.isDarwin ''
    swiftDriver="$out/usr/bin/swift-driver"
    for progName in swift swiftc; do
      prog=$out/usr/bin/$progName
      export prog progName swift swiftDriver sdk
      rm $out/usr/bin/$progName
      substituteAll '${./build/wrapper.sh}' $out/bin/$progName
      chmod a+x $out/bin/$progName
    done
  '' + lib.optionalString stdenv.isLinux ''
        rpath=$rpath''${rpath:+:}$out/usr/lib
        rpath=$rpath''${rpath:+:}$out/usr/lib/swift/host
        rpath=$rpath''${rpath:+:}$out/usr/lib/swift/host/compiler
        rpath=$rpath''${rpath:+:}$out/usr/lib/swift/linux
        rpath=$rpath''${rpath:+:}${stdenv.cc.cc.lib}/lib
        rpath=$rpath''${rpath:+:}${gcc.cc.lib}/lib
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

        swiftDriver="$out/usr/bin/swift-driver"
        for progName in swift swiftc; do
          prog=$out/usr/bin/$progName
          export prog progName swift swiftDriver sdk
          rm $out/usr/bin/$progName
          substituteAll '${./build/wrapper.sh}' $out/usr/bin/$progName

          cat > $out/bin/$progName <<-EOF
    #!${runtimeShell}
    ${fhsEnv}/bin/swift-env $out/usr/bin/$progName "\$@"
    EOF
          chmod a+x $out/bin/$progName $out/usr/bin/$progName
        done
  '' + ''
    mkdir -p $out/nix-support
    substituteAll ${./build/setup-hook.sh} $out/nix-support/setup-hook

    ln -s $out/usr/lib $out/lib
  '';

  doCheck = true;
  checkPhase = ''
    $out/bin/swift --version
    $out/bin/swiftc --version
  '';
})
