#!/bin/bash
# mannn-python-proxy — Dynamic proxy template for Python apps on HestiaCP
# Args: $1=user $2=domain $3=ip $4=home $5=docroot
# Auto: directory, .env, placeholder, nginx proxy, systemd service

user="$1"
domain="$2"
# shellcheck disable=SC2034  # $3=ip, $5=docroot: HestiaCP always passes 5 args; unused by proxy templates
ip="$3"
home="$4"
# shellcheck disable=SC2034
docroot="$5"

set -eo pipefail

. "/usr/local/hestia/data/templates/web/nginx/php-fpm/mannn-security.sh"

APP_DIR="$home/$user/web/$domain/private/python"
ENV_FILE="$APP_DIR/.env"
CONF_DIR="$home/$user/conf/web/$domain"
PROXY_CONF="$CONF_DIR/nginx.proxy.conf"
PROXY_SSL_CONF="$CONF_DIR/nginx.proxy.ssl.conf"
DEFAULT_PORT=8100
PORT_MIN=8100
PORT_MAX=8999
SVC_NAME="$(mannn_unit_name "$user" "$domain")"
SVC_FILE="/etc/systemd/system/$SVC_NAME.service"

mannn_prepare_dir "$APP_DIR" "$user:$user" 755
mannn_prepare_dir "$CONF_DIR" "$user:$user" 750
mannn_abort_if_symlink "$ENV_FILE"
mannn_abort_if_symlink "$PROXY_CONF"
mannn_abort_if_symlink "$PROXY_SSL_CONF"
mannn_abort_if_symlink "$SVC_FILE"

if [ ! -f "$ENV_FILE" ]; then
    echo "PORT=$DEFAULT_PORT" > "$ENV_FILE"
fi
chown "$user:$user" "$ENV_FILE" 2>/dev/null || true
chmod 600 "$ENV_FILE" 2>/dev/null || true

if [ ! -f "$APP_DIR/app.py" ] && [ ! -f "$APP_DIR/main.py" ] && [ ! -f "$APP_DIR/wsgi.py" ] && [ ! -f "$APP_DIR/server.py" ]; then
    cat > "$APP_DIR/app.py" << 'PYEOF'
import json
from http.server import HTTPServer, BaseHTTPRequestHandler


def load_port(default=8100):
    try:
        with open('.env') as f:
            for line in f:
                line = line.strip()
                if line.startswith('PORT='):
                    return int(line[5:].strip().strip('"').strip("'"))
    except Exception:
        pass
    return default


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        response = {
            'status': 'ok',
            'message': 'Python app running',
            'domain': self.headers.get('Host', 'unknown'),
        }
        self.wfile.write(json.dumps(response).encode())


if __name__ == '__main__':
    port = load_port()
    server = HTTPServer(('127.0.0.1', port), Handler)
    print(f'Listening on port {port}')
    server.serve_forever()
PYEOF
    chown "$user:$user" "$APP_DIR/app.py"
    chmod 644 "$APP_DIR/app.py"
fi

ENTRY="app.py"
if [ ! -f "$APP_DIR/app.py" ]; then
    if [ -f "$APP_DIR/server.py" ]; then
        ENTRY="server.py"
    elif [ -f "$APP_DIR/main.py" ]; then
        ENTRY="main.py"
    elif [ -f "$APP_DIR/wsgi.py" ]; then
        ENTRY="wsgi.py"
    fi
fi

if [ -f "$APP_DIR/venv/bin/python3" ]; then
    PYTHON_BIN="$APP_DIR/venv/bin/python3"
else
    PYTHON_BIN=$(command -v python3 2>/dev/null || echo "/usr/local/bin/python3")
fi

REQUESTED_PORT=$(mannn_read_env_value PORT "$ENV_FILE")
PORT=$(mannn_resolve_port "$REQUESTED_PORT" "$DEFAULT_PORT" "$PORT_MIN" "$PORT_MAX")

if ! mannn_port_migrate "$PORT" "$SVC_NAME"; then
    mannn_write_disabled_confs "$PROXY_CONF" "$PROXY_SSL_CONF"
    chown "root:$user" "$PROXY_CONF" "$PROXY_SSL_CONF" 2>/dev/null || true
    chmod 640 "$PROXY_CONF" "$PROXY_SSL_CONF" 2>/dev/null || true
    systemctl stop "$SVC_NAME" >/dev/null 2>&1 || true
    echo "mannn: port $PORT already used by another domain — set another PORT in $ENV_FILE and re-apply" >&2
    exit 1
fi

rm -f "$PROXY_CONF" "$PROXY_SSL_CONF"
mannn_write_proxy_confs "$PROXY_CONF" "$PROXY_SSL_CONF" "$PORT"

chown "root:$user" "$PROXY_CONF" "$PROXY_SSL_CONF" 2>/dev/null || true
chmod 640 "$PROXY_CONF" "$PROXY_SSL_CONF" 2>/dev/null || true

cat > "$SVC_FILE" << SVCEOF
[Unit]
Description=Python app for $domain
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$user
Group=$user
WorkingDirectory=$APP_DIR
ExecStart=$PYTHON_BIN $ENTRY
Restart=on-failure
RestartSec=5
TimeoutStopSec=20
Environment=PORT=$PORT
Environment=PYTHONUNBUFFERED=1

    # Systemd sandbox hardening
    ProtectSystem=strict
    ProtectHome=read-only
    NoNewPrivileges=true
    PrivateTmp=true
    ReadWritePaths=$APP_DIR
    CapabilityBoundingSet=
    AmbientCapabilities=
[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload >/dev/null 2>&1 || true
if systemctl is-active --quiet "$SVC_NAME" 2>/dev/null; then
    systemctl restart "$SVC_NAME" >/dev/null 2>&1 || true
else
    systemctl enable "$SVC_NAME" >/dev/null 2>&1 || true
    systemctl start "$SVC_NAME" >/dev/null 2>&1 || true
fi
