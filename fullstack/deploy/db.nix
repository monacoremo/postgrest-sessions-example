{ writeText, checkedShellScript, postgresql, entr }:

let
  postgresConf =
    writeText "postgresql.conf"
      ''
        log_min_messages = warning
        log_min_error_statement = error

        log_min_duration_statement = 100  # ms

        log_connections = on
        log_disconnections = on
        log_duration = on
        #log_line_prefix = '[] '
        #log_statement = 'none'
        log_timezone = 'UTC'
      '';

  md2sql =
    ../../deploy/md2sql.sed;
in
rec {
  run =
    checkedShellScript.writeBin "fullstack-db-run"
      ''
        set -e

        export PGDATA="$FULLSTACK_DB_DIR"
        export PGHOST="$FULLSTACK_DB_HOST"
        export PGUSER="$FULLSTACK_DB_SUPERUSER"
        export PGDATABASE="$FULLSTACK_DB_DBNAME"

        cleanup() {
          ${postgresql}/bin/pg_ctl stop -m i
          kill 0
        }

        trap cleanup exit

        touch "$FULLSTACK_DB_LOGFILE"
        rm -rf "$FULLSTACK_DB_DIR"
        mkdir -p "$FULLSTACK_DB_DIR"

        # Initialize the PostgreSQL cluster
        pwfile=$(mktemp)
        echo "$FULLSTACK_DB_SUPERUSER_PW" > "$pwfile"

        TZ=UTC ${postgresql}/bin/initdb --no-locale --encoding=UTF8 --nosync \
          -U "$PGUSER" -A password --pwfile="$pwfile"

        rm "$pwfile"

        # Convert the .sql.md script to .sql
        sed -f ${md2sql} <"$FULLSTACK_DB_SRC" >"$FULLSTACK_DB_DIR"/app.sql

        mkdir -p "$FULLSTACK_DB_SETUPHOST"

        ${postgresql}/bin/pg_ctl start \
          -o "-F -c listen_addresses=\"\" -k $FULLSTACK_DB_SETUPHOST"

        ${postgresql}/bin/psql "$FULLSTACK_DB_SUPERUSER_SETUP_URI" \
          -f "$FULLSTACK_DB_DIR/app.sql"

        ${postgresql}/bin/psql "$FULLSTACK_DB_SUPERUSER_SETUP_URI" << EOF
          alter role authenticator with password '$FULLSTACK_DB_APISERVER_PW';
        EOF

        ${postgresql}/bin/pg_ctl stop

        rm -rf "$FULLSTACK_DB_SETUPHOST"

        cat ${postgresConf} >> "$FULLSTACK_DB_DIR"/postgresql.conf

        exec ${postgresql}/bin/postgres -F -c listen_addresses="" \
          -k "$FULLSTACK_DB_HOST" 2>&1
      '';

  watch =
    checkedShellScript.writeBin "fullstack-db-watch"
      ''
        while true; do
          find "$FULLSTACK_DB_SRC" | \
            ${entr}/bin/entr -d -r ${run}/bin/fullstack-db-run
        done
      '';
}
