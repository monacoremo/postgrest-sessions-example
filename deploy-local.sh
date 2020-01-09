#!/usr/bin/env bash

# This script sets up a PostgreSQL database in a temporary directory, loads the
# schema described in the app.sql.md file and runs a PostgREST instance on top
# of it.

set -e # abort on error

# Source 'deploy-local.env' if the example environment is not yet set.
if [[ -z "$EXAMPLEAPP_URI" ]]; then
    echo "Loading a new environment from 'deploy-local.env'..."
    source deploy-local.env
else
    echo "Using the existing environment in '$EXAMPLEAPP_BASEDIR'..."
fi

mkdir -p "$EXAMPLEAPP_BASEDIR"

cleanup () {
    pg_ctl stop -m i
    rm -rf "$EXAMPLEAPP_BASEDIR"
    kill 0
}

trap cleanup exit

# Filter the SQL code blocks from the Markdown file
sed -f md2sql.sed <app.sql.md >"$EXAMPLEAPP_BASEDIR/app.sql"

# Initialize our database cluster in the PGDATA directory. As we'd like our
# environment to be as reproducible as possible, we make it independent from
# the locale, encoding and timezone of the host.
TZ=UTC initdb --no-locale --encoding=UTF8 -U "$PGUSER" > /dev/null

# Create the socket directory.
mkdir -p "$PGHOST"

# Start the database server, listening on a socket instead of a port.
# -F disables file syncing for a bit of extra performance in testing, don't use
# this in production. We use pg_ctl here as it waits for its actions to
# complete by default.
pg_ctl start -o "-F -c listen_addresses=\"\" -k $PGHOST" > /dev/null

# Load the application schema.
psql -P pager=off -f "$EXAMPLEAPP_BASEDIR/app.sql"

# Stop the database server and wait for it to shut down.
pg_ctl stop > /dev/null

echo "Running PostgreSQL and PostgREST on $EXAMPLEAPP_URI"
echo "Press Ctrl-c to exit and clean up the temp directory $EXAMPLEAPP_BASEDIR."

# Start a non-daemonized instance of the database server.
postgres -F -c listen_addresses="" -k "$PGHOST" &

postgrest postgrest.conf &

wait
