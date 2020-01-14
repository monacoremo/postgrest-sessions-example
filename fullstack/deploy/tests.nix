{ python, checkedShellScript, deployLocal, curl}:

let
  testPython =
    python.withPackages
      (
        ps: [
          ps.pytest
          ps.requests
        ]
      );
in
checkedShellScript.writeBin "fullstack-tests-run"
  ''
    set -e

    cleanup() {
      rm -rf "$tmpdir"
      kill 0
    }
    trap cleanup exit

    tmpdir="$(mktemp -d)"
    # shellcheck source=/dev/null
    source "$(${deployLocal.mkEnv}/bin/fullstack-local-mkenv . "$tmpdir")"
    ${deployLocal.run}/bin/fullstack-local-run &

    echo "Waiting for API to become available... (Ctrl-c to cancel)"

    while [[ "$(${curl}/bin/curl -s -o /dev/null -w "%{http_code}" "$FULLSTACK_URI"api/)" != "200" ]];
        do sleep 0.1;
    done

    echo "API is ready, running tests..."

    ${python}/bin/py.test tests/tests.py "$@"
  ''
