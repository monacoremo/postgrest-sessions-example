{ writeText, checkedShellScript, postgrest, entr }:

let
  postgrestConf =
    writeText "postgrest.conf"
      ''
        db-uri = "$(FULLSTACK_DB_APISERVER_URI)"
        db-schema = "api"
        db-anon-role = "anonymous"

        pre-request = "auth.authenticate"

        server-unix-socket = "$(FULLSTACK_API_SOCKET)"
      '';
in
rec {
  run =
    checkedShellScript.writeBin "fullstack-api-run"
      ''
        mkdir "$FULLSTACK_API_DIR"
        exec ${postgrest}/bin/postgrest ${postgrestConf}
      '';

  watch =
    checkedShellScript.writeBin "fullstack-api-watch"
      ''
        while true; do
          find "$FULLSTACK_DB_SRC" | \
            ${entr}/bin/entr -d -r ${run}/bin/fullstack-api-run
        done
      '';
}
