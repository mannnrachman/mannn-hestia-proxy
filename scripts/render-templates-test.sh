#!/usr/bin/env bash
# Standalone render-and-parse test for every templates/*/*.tpl and *.stpl.
#
# Renders each template with dummy HestiaCP variables, generates the shared
# proxy include files via templates/common/mannn-security.sh, and validates
# the whole tree with `nginx -t` inside an nginx:alpine container.
#
# Usage: scripts/render-templates-test.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

command -v docker >/dev/null 2>&1 || { echo "FAIL: docker not found" >&2; exit 1; }
command -v openssl >/dev/null 2>&1 || { echo "FAIL: openssl not found" >&2; exit 1; }

SANDBOX="$(mktemp -d)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

CONF_DIR="$SANDBOX/conf.d"
HOME_DIR="$SANDBOX/home/test"
DOMAIN_DIR="$HOME_DIR/conf/web/a.test"
WEB_DIR="$HOME_DIR/web/a.test"
mkdir -p "$CONF_DIR" "$DOMAIN_DIR" "$WEB_DIR" "$SANDBOX/ports"

# ---------------------------------------------------------------------------
# Dummy HestiaCP template variables
# ---------------------------------------------------------------------------
SSL_PEM="$SANDBOX/ssl/a.test.pem"
SSL_KEY="$SANDBOX/ssl/a.test.key"
mkdir -p "$SANDBOX/ssl"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
    -subj "/CN=a.test" -keyout "$SSL_KEY" -out "$SSL_PEM" >/dev/null 2>&1

subst() {
    sed \
        -e "s|%ip%|127.0.0.1|g" \
        -e "s|%web_port%|8080|g" \
        -e "s|%web_ssl_port%|8443|g" \
        -e "s|%domain_idn%|a.test|g" \
        -e "s|%alias_idn%|www.a.test|g" \
        -e "s|%domain%|a.test|g" \
        -e "s|%home%|/home|g" \
        -e "s|%user%|test|g" \
        -e "s|%docroot%|/home/test/web/a.test/public_html|g" \
        -e "s|%sdocroot%|/home/test/web/a.test/public_html|g" \
        -e "s|%ssl_pem%|$SSL_PEM|g" \
        -e "s|%ssl_key%|$SSL_KEY|g" \
        -e "s|%backend_lsnr%|127.0.0.1:9000|g" \
        "$1"
}

# ---------------------------------------------------------------------------
# HestiaCP globals the templates rely on (http{} context)
# ---------------------------------------------------------------------------
# TLS 1.3 0-RTT anti-replay / early-data maps. Upstream HestiaCP no longer
# ships them (OCSP removal); fallback definitions below keep the templates'
# $anti_replay / $rfc_early_data references parseable. If a newer upstream
# file defines them, the upstream definitions are used instead.
MAP_ANTI_REPLAY='map $ssl_early_data $anti_replay { default ""; 1 307; }'
MAP_RFC_EARLY_DATA='map $ssl_early_data $rfc_early_data { default ""; 1 on; }'
if curl -fsSL --max-time 15 \
    https://raw.githubusercontent.com/hestiacp/hestiacp/main/install/deb/nginx/nginx.conf \
    -o "$SANDBOX/upstream-nginx.conf" 2>/dev/null; then
    UP_ANTI="$(grep -A12 'map \$ssl_early_data \$anti_replay' "$SANDBOX/upstream-nginx.conf" | sed -n '/{/,/}/p' || true)"
    UP_RFC="$(grep -A12 'map \$ssl_early_data \$rfc_early_data' "$SANDBOX/upstream-nginx.conf" | sed -n '/{/,/}/p' || true)"
    [ -n "$UP_ANTI" ] && MAP_ANTI_REPLAY="$UP_ANTI" || true
    [ -n "$UP_RFC" ] && MAP_RFC_EARLY_DATA="$UP_RFC" || true
fi

cat >"$SANDBOX/nginx.conf" <<EOF
worker_processes  1;
error_log  /dev/stderr;
pid        /tmp/nginx-ci.pid;

events { worker_connections 64; }

http {
    include       mime.types;
    default_type  application/octet-stream;

    log_format bytes '\$body_bytes_sent';

    $MAP_RFC_EARLY_DATA

    $MAP_ANTI_REPLAY

    include $SANDBOX/conf.d/*.conf;
}
EOF

# Minimal mime.types so "include mime.types" resolves inside the sandbox.
echo 'types { text/html html htm; text/css css; application/javascript js; }' \
    >"$SANDBOX/mime.types"

# Templates include /etc/nginx/fastcgi_params (PHP templates).
cat >"$SANDBOX/fastcgi_params" <<'EOF'
fastcgi_param  QUERY_STRING       $query_string;
fastcgi_param  REQUEST_METHOD     $request_method;
fastcgi_param  CONTENT_TYPE       $content_type;
fastcgi_param  CONTENT_LENGTH     $content_length;
fastcgi_param  SCRIPT_NAME        $fastcgi_script_name;
fastcgi_param  REQUEST_URI        $request_uri;
fastcgi_param  DOCUMENT_URI       $document_uri;
fastcgi_param  DOCUMENT_ROOT      $document_root;
fastcgi_param  SERVER_PROTOCOL    $server_protocol;
fastcgi_param  REQUEST_SCHEME     $scheme;
fastcgi_param  HTTPS              $https if_not_empty;
fastcgi_param  GATEWAY_INTERFACE  CGI/1.1;
fastcgi_param  SERVER_SOFTWARE    nginx/$nginx_version;
fastcgi_param  REMOTE_ADDR        $remote_addr;
fastcgi_param  REMOTE_PORT        $remote_port;
fastcgi_param  SERVER_ADDR        $server_addr;
fastcgi_param  SERVER_PORT        $server_port;
fastcgi_param  SERVER_NAME        $server_name;
fastcgi_param  REDIRECT_STATUS    200;
EOF

# Shared http{}-context confs from templates/common/.
cp "$REPO_ROOT/templates/common/mannn-rate-limit.conf" "$CONF_DIR/"
cp "$REPO_ROOT/templates/common/mannn-upgrade-map.conf" "$CONF_DIR/" \
    || echo "WARN: templates/common/mannn-upgrade-map.conf missing (being added by install work)" >&2

# ---------------------------------------------------------------------------
# Generate the shared proxy include files via the real helper library
# ---------------------------------------------------------------------------
# shellcheck source=templates/common/mannn-security.sh
MANNN_PORT_DIR="$SANDBOX/ports" source "$REPO_ROOT/templates/common/mannn-security.sh"
if ! command -v mannn_write_proxy_confs >/dev/null 2>&1; then
    echo "FAIL: mannn_write_proxy_confs not defined in templates/common/mannn-security.sh" >&2
    exit 1
fi
mannn_write_proxy_confs "$DOMAIN_DIR/nginx.proxy.conf" "$DOMAIN_DIR/nginx.proxy.ssl.conf" 3100

# ---------------------------------------------------------------------------
# Render every runtime template into conf.d/ (each is a full server block)
# ---------------------------------------------------------------------------
TPL_COUNT=0
for tpl in "$REPO_ROOT"/templates/*/*.tpl "$REPO_ROOT"/templates/*/*.stpl; do
    [ -f "$tpl" ] || continue
    name="$(basename "$tpl")"
    runtime="$(basename "$(dirname "$tpl")")"
    subst "$tpl" >"$CONF_DIR/$runtime-$name.conf"
    TPL_COUNT=$((TPL_COUNT + 1))
done
echo "Rendered $TPL_COUNT templates into sandbox conf.d/"

# nginx -t requires files referenced by include with trailing glob to have a
# parent directory, and alias/try_files targets may be missing — that is fine.

# ---------------------------------------------------------------------------
# Validate with nginx -t inside a container (sandbox mounted as /etc/nginx)
# ---------------------------------------------------------------------------
set +e
OUT="$(docker run --rm \
    -v "$SANDBOX":/etc/nginx:ro \
    -v "$SANDBOX/home":/home:ro \
    nginx:alpine nginx -t 2>&1)"
RC=$?
set -e

echo "$OUT"
if [ $RC -eq 0 ] && echo "$OUT" | grep -q 'test is successful'; then
    echo "PASS: nginx -t accepted all $TPL_COUNT rendered templates"
    exit 0
fi
echo "FAIL: nginx -t rejected the rendered configuration (exit $RC)" >&2
exit 1
