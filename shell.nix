let
  pkgs =
    let
      pinnedPkgs =
        builtins.fetchTarball {
          url = "https://github.com/nixos/nixpkgs/archive/f9c81b5c148572c2a78a8c1d2c8d5d40e642b31a.tar.gz";
          sha256 = "0ff7zhqk7mjgsvqyp4pa9xjvv9cvp3mh0ss9j9mclgzfh9wbwzmf";
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
