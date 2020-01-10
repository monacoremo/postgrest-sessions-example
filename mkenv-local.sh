#!/usr/bin/env bash

# Creates a new local environment for the PostgREST session example.

basedir=$(mktemp -d)

cat >"$basedir/env" <<EOF

export PGDATA="$basedir/db"
export PGHOST="$basedir/dbsocket"
export PGUSER=postgres
export PGDATABASE=postgres

export EXAMPLEAPP_PORT=3000
export EXAMPLEAPP_APISERVER_DB_URI="postgresql:///\$PGDATABASE?host=\$PGHOST&user=authenticator"
export EXAMPLEAPP_TESTS_DB_URI="postgresql:///\$PGDATABASE?host=\$PGHOST&user=\$PGUSER"
export EXAMPLEAPP_BASEDIR="$basedir"
export EXAMPLEAPP_URI="http://localhost:\$EXAMPLEAPP_PORT/"

EOF

echo "$basedir/env"
