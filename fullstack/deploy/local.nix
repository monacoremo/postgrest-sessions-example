{ stdenv, checkedShellScript, runtimeShell, shellcheck, pwgen }:
{ db, api, ingress, webapp }:

rec {
  run =
    checkedShellScript.writeBin "fullstack-local-run"
      ''
        set -e
        tmpdir=$(mktemp -d)

        stop() {
            rm -rf tmpdir
            kill 0
        }

        # shellcheck source=/dev/null
        source "$(${mkEnv}/bin/fullstack-local-mkenv . "$tmpdir")"

        ${db.run}/bin/fullstack-db-run &
        ${api.run}/bin/fullstack-api-run &
        ${ingress.run}/bin/fullstack-ingress-run &
        ${webapp.build}/bin/fullstack-webapp-build &

        wait
      '';

  watch =
    checkedShellScript.writeBin "fullstack-local-watch"
      ''
        set -e
        tmpdir=$(mktemp -d)

        stop() {
            rm -rf tmpdir
            kill 0
        }

        # shellcheck source=/dev/null
        source "$(${mkEnv}/bin/fullstack-local-mkenv . "$tmpdir")"

        ${db.watch}/bin/fullstack-db-watch &
        ${api.watch}/bin/fullstack-api-watch &
        ${ingress.run}/bin/fullstack-ingress-run &
        ${webapp.watch}/bin/fullstack-webapp-watch &

        wait
      '';

  mkEnv =
    checkedShellScript.writeBin "fullstack-local-mkenv"
      ''
        sourcedir=$(realpath "$1")
        basedir=$(realpath "$2")
        envfile="$basedir"/env

        mkdir -p "$basedir"

        cat << EOF > "$envfile"
        #!${runtimeShell}

        export FULLSTACK_SRC="$sourcedir"
        export FULLSTACK_PORT=9000
        export FULLSTACK_DIR="$basedir"
        export FULLSTACK_URI="http://localhost:$FULLSTACK_PORT/"
        export FULLSTACK_DB_DIR="\$FULLSTACK_DIR/db"
        export FULLSTACK_DB_LOGFILE="\$FULLSTACK_DIR/db.log"
        export FULLSTACK_DB_SRC="$sourcedir/../app.sql.md"
        export FULLSTACK_DB_HOST="\$FULLSTACK_DB_DIR"
        export FULLSTACK_DB_DBNAME=postgres
        export FULLSTACK_DB_SUPERUSER=postgres
        export FULLSTACK_DB_URI="postgresql:///\$FULLSTACK_DB_DBNAME?host=\$FULLSTACK_DB_HOST"
        export FULLSTACK_DB_SUPERUSER_PW=$(${pwgen}/bin/pwgen 32 1)
        export FULLSTACK_DB_APISERVER_PW=$(${pwgen}/bin/pwgen 32 1)
        export FULLSTACK_DB_SETUPHOST="\$FULLSTACK_DB_DIR/setupsocket"
        export FULLSTACK_DB_SUPERUSER_SETUP_URI="postgresql:///\$FULLSTACK_DBNAME?host=\$FULLSTACK_DB_SETUPHOST&user=\$FULLSTACK_DB_SUPERUSER&password=\$FULLSTACK_DB_SUPERUSER_PW"
        export FULLSTACK_DB_SUPERUSER_URI="\$FULLSTACK_DB_URI&user=\$FULLSTACK_DB_SUPERUSER&password=\$FULLSTACK_DB_SUPERUSER_PW"
        export FULLSTACK_DB_APISERVER_URI="\$FULLSTACK_DB_URI&user=authenticator&password=\$FULLSTACK_DB_APISERVER_PW"

        export FULLSTACK_API_LOGFILE="\$FULLSTACK_DIR/api.log"
        export FULLSTACK_API_DIR="\$FULLSTACK_DIR/api"
        export FULLSTACK_API_SOCKET="\$FULLSTACK_API_DIR/postgrest.sock"
        export FULLSTACK_API_CONFIG="\$FULLSTACK_API_DIR/postgrest.conf"
        export FULLSTACK_API_URI="http://unix:\$FULLSTACK_API_SOCKET:/"

        export FULLSTACK_WEBAPP_LOGFILE="\$FULLSTACK_DIR/webapp.log"
        export FULLSTACK_WEBAPP_DIR="\$FULLSTACK_DIR/webapp"
        export FULLSTACK_WEBAPP_BUILDDIR="\$FULLSTACK_WEBAPP_DIR/build"
        export FULLSTACK_WEBAPP_SRC="$sourcedir/webapp"

        export FULLSTACK_INGRESS_LOGFILE="\$FULLSTACK_DIR/ingress"
        export FULLSTACK_INGRESS_DIR="\$FULLSTACK_DIR/ingress"

        # psql variables for convenience
        export PGHOST="\$FULLSTACK_DB_HOST"
        export PGDATABASE="\$FULLSTACK_DB_DBNAME"
        export PGUSER="\$FULLSTACK_DB_SUPERUSER"
        export PGPASSWORD="\$FULLSTACK_DB_SUPERUSER_PW"

        EOF

        ${stdenv.shell} -n "$envfile"
        ${shellcheck}/bin/shellcheck "$envfile"

        echo "$envfile"
      '';
}
