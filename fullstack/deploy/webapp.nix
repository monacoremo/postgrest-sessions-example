{ writeShellScriptBin, elmPackages, entr }:

rec {
  build =
    writeShellScriptBin "fullstack-webapp-build"
      ''
        set -e

        mkdir -p "$FULLSTACK_WEBAPP_DIR" "$FULLSTACK_WEBAPP_BUILDDIR"
        touch "$FULLSTACK_WEBAPP_LOGFILE"
        ln -sf "$FULLSTACK_WEBAPP_SRC"/{elm.json,src} "$FULLSTACK_WEBAPP_DIR"
        ln -sf "$FULLSTACK_WEBAPP_SRC"/index.html "$FULLSTACK_WEBAPP_BUILDDIR"

        (
            cd "$FULLSTACK_WEBAPP_DIR"

            ${elmPackages.elm}/bin/elm make src/Main.elm \
              --output "$FULLSTACK_WEBAPP_BUILDDIR"/app.js --debug

            cat "$FULLSTACK_WEBAPP_SRC"/init.js \
              >> "$FULLSTACK_WEBAPP_BUILDDIR"/app.js
        )
      '';

  watch =
    writeShellScriptBin "fullstack-webapp-watch"
      ''
        while true; do
          find "$FULLSTACK_WEBAPP_SRC" | \
            ${entr}/bin/entr -d ${build}/bin/fullstack-webapp-build
        done;
      '';
}
