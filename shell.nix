let
  pkgs =
    let
      pinnedPkgs =
        builtins.fetchGit {
          name = "nixos-unstable-2019-12-05";
          url = https://github.com/nixos/nixpkgs/;
          rev = "cc6cf0a96a627e678ffc996a8f9d1416200d6c81";
        };
    in
      import pinnedPkgs {};

  postgresql =
    pkgs.postgresql_12.withPackages
      (
        ps: [
          ps.pgtap
        ]
      );

  python =
    pkgs.python38.withPackages
      (
        ps: [
          ps.pytest
          ps.requests
        ]
      );

  postgrest =
    pkgs.stdenv.mkDerivation {
      name = "postgrest";
      src = pkgs.fetchurl {
        url = (
          "https://github.com/PostgREST/postgrest/"
          + "releases/download/v6.0.2/postgrest-v6.0.2-linux-x64-static.tar.xz"
        );
        hash = "sha256:09byg9pvq5f3chh1l4rg83y9ycyk2px0086im4xjjhk98z4sd41f";
      };

      sourceRoot = ".";
      unpackCmd = "tar xf $src";

      dontConfigure = true;
      dontBuild = true;

      installPhase = ''
        mkdir -p $out/bin
        cp postgrest $out/bin
      '';
    };
in
pkgs.stdenv.mkDerivation {
  name = "postgrest-session-example";

  buildInputs = [
    postgresql
    postgrest
    python
    pkgs.entr
  ];
}
