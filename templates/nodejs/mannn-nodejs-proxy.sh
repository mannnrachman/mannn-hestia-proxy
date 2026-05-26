#!/bin/bash
# mannn-nodejs-proxy — Dynamic proxy template for Node.js apps on HestiaCP
# Args: $1=user $2=domain $3=ip $4=home $5=docroot
# Auto: directory, .env, placeholder, nginx proxy, systemd service

user="$1"
domain="$2"
ip="$3"
home="$4"
docroot="$5"

. "/usr/local/hestia/data/templates/web/nginx/php-fpm/mannn-security.sh"

APP_DIR="$home/$user/web/$domain/private/nodejs"
ENV_FILE="$APP_DIR/.env"
CONF_DIR="$home/$user/conf/web/$domain"
PROXY_CONF="$CONF_DIR/nginx.proxy.conf"
PROXY_SSL_CONF="$CONF_DIR/nginx.proxy.ssl.conf"
DEFAULT_PORT=3100
PORT_MIN=3100
PORT_MAX=3999
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

if [ ! -f "$APP_DIR/server.js" ] && [ ! -f "$APP_DIR/index.js" ] && [ ! -f "$APP_DIR/app.js" ]; then
    cat > "$APP_DIR/server.js" << 'SRVEOF'
const http = require('http');
const fs = require('fs');
const path = require('path');

let port = 3100;
try {
    const env = fs.readFileSync(path.join(__dirname, '.env'), 'utf8');
    const match = env.match(/^PORT=(.+)$/m);
    if (match) port = parseInt(match[1].trim().replace(/['"]/g, ''));
} catch {}

const server = http.createServer((req, res) => {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
        status: 'ok',
        message: 'Node.js app running',
        domain: req.headers.host
    }));
});

server.listen(port, '127.0.0.1', () => {
    console.log('Listening on port ' + port);
});
SRVEOF
    chown "$user:$user" "$APP_DIR/server.js"
    chmod 644 "$APP_DIR/server.js"
fi

ENTRY="server.js"
if [ ! -f "$APP_DIR/server.js" ]; then
    if [ -f "$APP_DIR/index.js" ]; then
        ENTRY="index.js"
    elif [ -f "$APP_DIR/app.js" ]; then
        ENTRY="app.js"
    fi
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

if [ -x "/usr/local/node/bin/node" ]; then
    NODE_BIN="/usr/local/node/bin/node"
else
    NODE_BIN=$(command -v node 2>/dev/null || echo "/usr/local/bin/node")
fi

cat > "$SVC_FILE" << SVCEOF
[Unit]
Description=Node.js app for $domain
After=network.target

[Service]
Type=simple
User=$user
Group=$user
WorkingDirectory=$APP_DIR
ExecStart=$NODE_BIN $ENTRY
Restart=on-failure
RestartSec=5
Environment=NODE_ENV=production
Environment=PORT=$PORT

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
