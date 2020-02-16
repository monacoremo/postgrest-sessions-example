let
  pkgs =
    let
      pinnedPkgs =
        builtins.fetchTarball {
          url = "https://github.com/nixos/nixpkgs/archive/62bbc2abc1f3ae24943a204a4095c20737189656.tar.gz";
          sha256 = "0cggas9zl19pzc0ikj9zdxvygqrgmj26snnmhhj27d25kh6cksww";
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
    pkgs.curl
    pkgs.bash
  ];
}
