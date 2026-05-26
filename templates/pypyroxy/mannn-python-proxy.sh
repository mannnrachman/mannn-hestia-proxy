#!/bin/bash
# mannn-python-proxy — Dynamic proxy template for Python apps on HestiaCP
# Args: $1=user $2=domain $3=ip $4=home $5=docroot
# Auto: directory, .env, placeholder, nginx proxy, systemd service

user="$1"
domain="$2"
ip="$3"
home="$4"
docroot="$5"

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
chown "$user:$user" "$ENV_FILE" 2>/dev/null
chmod 600 "$ENV_FILE"

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

rm -f "$PROXY_CONF" "$PROXY_SSL_CONF"

cat > "$PROXY_CONF" << PROXYEOF
location / {
    proxy_pass http://127.0.0.1:$PORT;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;
}
PROXYEOF

cat > "$PROXY_SSL_CONF" << PROXYEOF
location / {
    proxy_pass http://127.0.0.1:$PORT;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;
}
PROXYEOF

chown "root:$user" "$PROXY_CONF" "$PROXY_SSL_CONF" 2>/dev/null
chmod 640 "$PROXY_CONF" "$PROXY_SSL_CONF" 2>/dev/null

cat > "$SVC_FILE" << SVCEOF
[Unit]
Description=Python app for $domain
After=network.target

[Service]
Type=simple
User=$user
Group=$user
WorkingDirectory=$APP_DIR
ExecStart=$PYTHON_BIN $ENTRY
Restart=on-failure
RestartSec=5
Environment=PORT=$PORT
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload >/dev/null 2>&1
if systemctl is-active --quiet "$SVC_NAME" 2>/dev/null; then
    systemctl restart "$SVC_NAME" >/dev/null 2>&1
else
    systemctl enable "$SVC_NAME" >/dev/null 2>&1
    systemctl start "$SVC_NAME" >/dev/null 2>&1
fi
