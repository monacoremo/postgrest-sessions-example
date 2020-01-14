{ stdenv
, imagemagick
, material-design-icons
, gixy
, luajit
, envsubst
, openresty
, writeTextFile
, checkedShellScript
}:

let
  nginxConf =
    writeNginxConf "nginx.conf"
      ''
        events {}

        http {
            default_type application/ocet-stream;

            types {
              text/html html;
              text/css css;
              application/javascript js;
              image/png png;
              image/svg+xml svg;
              font/woff woff;
              font/woff2 woff2;
            }

            gzip off;
            sendfile on;

            keepalive_timeout 65s;

            server {
                listen $FULLSTACK_PORT default_server;

                # add_header Content-Security-Policy "default-src 'self'; style-src 'unsafe-inline'";
                # add_header X-Content-Type-Options "nosniff";
                add_header X-Frame-Options "SAMEORIGIN";
                add_header X-XSS-Protection "1; mode=block";

                location =/ {
                    access_by_lua_block {
                        ngx.header['Location'] = '/app/'
                        ngx.exit(301)
                    }
                }

                location =/favicon.ico {
                    alias ${favicon};
                }

                location /api/ {
                    more_clear_input_headers Accept-Encoding;
                    access_by_lua_file ${antiCsrf};
                    proxy_pass $FULLSTACK_API_URI;
                }

                location /app/ {
                    alias $FULLSTACK_WEBAPP_BUILDDIR/;
                    try_files $$uri /app/index.html;
                }

                location /fonts/material-design-icons/ {
                    alias ${material-design-icons}/share/fonts/;
                }
            }
        }
      '';

  favicon =
    stdenv.mkDerivation rec {
      name = "favicon.ico";
      src = ../webapp/assets/favicon.png;
      phases = [ "buildPhase" ];
      buildPhase =
        ''
          ${imagemagick}/bin/convert -flatten -background none -resize 16x16 ${src} $out
        '';
    };

  antiCsrf =
    writeLuaScript "anticsrf.lua"
      ''
        -- TODO: enable CSRF protection for production

        -- First line of defense: Check that origin or referer is set and that they
        -- match the current host (using ngx.var.http_origin and ngx.var.http_referer)

        -- Defense in depth: Require a custom header for API requests, which can
        -- only be set by requests from the same origin

        -- if ngx.req.get_headers()['X-Requested-By'] == nil then
        --     ngx.header.content_type = 'text/plain'
        --     ngx.say('Missing X-Requested-By header - not allowed to mitigate CSRF')
        --     ngx.exit(405)
        -- end
      '';

  rewriteOpenApi =
    writeLuaScript "openapi.lua"
      ''
        local cjson = require "cjson"
        cjson.decode_array_with_array_mt(true)

        local res = ngx.location.capture("/api/")
        api = cjson.decode(res.body)

        api["basePath"] = "/api/"
        api["host"] = ""

        ngx.say(cjson.encode(api))
      '';

  writeNginxConf =
    name: text:
      writeTextFile {
        inherit name text;
        checkPhase =
          ''
            ${gixy}/bin/gixy $out > /dev/null
          '';
      };

  writeLuaScript =
    name: text:
      writeTextFile {
        inherit name text;
        checkPhase =
          ''
            ${luajit}/bin/luajit -bl $out > /dev/null
          '';
      };
in
{ run =
    checkedShellScript.writeBin "fullstack-ingress-run"
      ''
        mkdir -p "$FULLSTACK_INGRESS_DIR"/{logs,conf}
        touch "$FULLSTACK_INGRESS_LOGFILE"
        touch "$FULLSTACK_INGRESS_DIR"/logs/{error.log,access.log}
        ${envsubst}/bin/envsubst -i ${nginxConf} \
          -o "$FULLSTACK_INGRESS_DIR/conf/nginx.conf"

        exec ${openresty}/bin/openresty -p "$FULLSTACK_INGRESS_DIR" \
          -g "daemon off;"
      '';
}
