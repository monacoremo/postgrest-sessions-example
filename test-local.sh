#!/usr/bin/env bash

set -e

source deploy-local.env

trap "kill 0" exit

./deploy-local.sh &

echo "Waiting for API to become available... (Ctrl-c to cancel)"

while [[ "$(curl -s -o /dev/null -w ''%{http_code}'' $EXAMPLEAPP_URI)" != "200" ]];
    do sleep 0.1;
done

echo "API is ready, running tests..."

exec py.test tests.py $@
