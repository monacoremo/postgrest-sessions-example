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

  fullstack =
    pkgs.callPackage ./default.nix {};
in
pkgs.stdenv.mkDerivation {
  name = "fullstack";

  buildInputs = [
    fullstack.api.run
    fullstack.api.watch
    fullstack.db.run
    fullstack.deployLocal.mkEnv
    fullstack.deployLocal.run
    fullstack.deployLocal.watch
    fullstack.ingress.run
    fullstack.postgresql
    fullstack.postgrest
    fullstack.python
    fullstack.webapp.build
    fullstack.webapp.watch
    fullstack.tests
    pkgs.bash
    pkgs.curl
    pkgs.entr
  ];

  shellHook = ''
    tmpdir="$(mktemp -d)"
    source "$(fullstack-local-mkenv . "$tmpdir")"

    cat << EOF

    $(${pkgs.ncurses}/bin/tput setaf 2)
    Full stack development environment
    $(${pkgs.ncurses}/bin/tput sgr0)
    Use "fullstack-local-watch" to run the full stack with code reload.
    EOF
  '';
}
