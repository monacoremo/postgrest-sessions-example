{ pkgs }:

rec {
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
    pkgs.callPackage deploy/postgrest.nix {};

  webapp =
    pkgs.callPackage deploy/webapp.nix {};

  ingress =
    pkgs.callPackage deploy/ingress.nix { inherit checkedShellScript; };

  api =
    pkgs.callPackage deploy/api.nix { inherit checkedShellScript postgrest; };

  db =
    pkgs.callPackage deploy/db.nix { inherit checkedShellScript postgresql; };

  checkedShellScript =
    pkgs.callPackage deploy/checked-shell-script.nix {};

  deployLocal =
    pkgs.callPackage deploy/local.nix { inherit checkedShellScript; }
      { inherit db api ingress webapp; };

  tests =
    pkgs.callPackage deploy/tests.nix { inherit checkedShellScript python deployLocal; };
}
