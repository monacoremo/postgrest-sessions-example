#!/usr/bin/env bash

# Runs the integrations tests in tests.py as soon as the API becomes available.
# Options like '-k [PATTERN]', which can be used to select tests, will be passed
# to py.test.

set -e

export EXAMPLEAPP_URI=${EXAMPLEAPP_URI:-"http://localhost:3000/"}

echo "Waiting for API to become available... (Ctrl-c to cancel)"

while [[ "$(curl -s -o /dev/null -w ''%{http_code}'' $EXAMPLEAPP_URI)" != "200" ]];
    do sleep 0.1;
done

echo "API is ready, running tests..."

exec py.test tests.py $@
