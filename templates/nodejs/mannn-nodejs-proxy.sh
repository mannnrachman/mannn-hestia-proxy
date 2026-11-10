#!/bin/bash
# mannn-nodejs-proxy — Dynamic proxy template for Node.js apps on HestiaCP
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
chown "$user:$user" "$ENV_FILE" 2>/dev/null || true
chmod 600 "$ENV_FILE" 2>/dev/null || true

if [ ! -f "$APP_DIR/server.js" ] && [ ! -f "$APP_DIR/index.js" ] && [ ! -f "$APP_DIR/app.js" ]; then
    cat > "$APP_DIR/server.js" << 'SRVEOF'
const http = require('http');
const fs = require('fs');
const path = require('path');

function loadPort() {
    const envPort = parseInt(process.env.PORT, 10);
    if (Number.isInteger(envPort) && envPort > 0) return envPort;
    try {
        const env = fs.readFileSync(path.join(__dirname, '.env'), 'utf8');
        const match = env.match(/^PORT=(.+)$/m);
        if (match) {
            const p = parseInt(match[1].trim().replace(/['"]/g, ''));
            if (Number.isInteger(p) && p > 0) return p;
        }
    } catch {}
    return 3100;
}

const port = loadPort();

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

if [ -x "/usr/local/node/bin/node" ]; then
    NODE_BIN="/usr/local/node/bin/node"
else
    NODE_BIN=$(command -v node 2>/dev/null || echo "/usr/local/bin/node")
fi

cat > "$SVC_FILE" << SVCEOF
[Unit]
Description=Node.js app for $domain
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$user
Group=$user
WorkingDirectory=$APP_DIR
ExecStart=$NODE_BIN $ENTRY
Restart=on-failure
RestartSec=5
TimeoutStopSec=20
Environment=NODE_ENV=production
Environment=PORT=$PORT
    # Systemd sandbox hardening
    # Per-service overrides survive re-apply via a drop-in:
    #   /etc/systemd/system/<unit>.service.d/override.conf
    ProtectSystem=strict
    ProtectHome=read-only
    NoNewPrivileges=true
    PrivateTmp=true
    PrivateDevices=true
    ProtectClock=yes
    ProtectControlGroups=yes
    ProtectHostname=yes
    ProtectKernelLogs=yes
    ProtectKernelModules=yes
    ProtectKernelTunables=yes
    ProtectProc=invisible
    RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK
    RestrictRealtime=yes
    RestrictSUIDSGID=yes
    SystemCallArchitectures=native
    SystemCallFilter=@system-service
    SystemCallErrorNumber=EPERM
    LockPersonality=yes
    MemoryMax=512M
    UMask=0027
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
