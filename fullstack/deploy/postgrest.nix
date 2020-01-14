{ stdenv, fetchurl }:

stdenv.mkDerivation {
  name = "postgrest";
  src = fetchurl {
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
}
