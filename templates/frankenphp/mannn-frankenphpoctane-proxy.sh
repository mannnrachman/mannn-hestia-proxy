#!/bin/bash
# mannn-frankenphpoctane-proxy — Dynamic proxy template for PHP/FrankenPHP/Laravel Octane on HestiaCP
# Args: $1=user $2=domain $3=ip $4=home $5=docroot
# Auto: directory, .env, placeholder, detect Laravel vs plain PHP, nginx proxy, systemd service

user="$1"
domain="$2"
ip="$3"
home="$4"
docroot="$5"

. "/usr/local/hestia/data/templates/web/nginx/php-fpm/mannn-security.sh"

APP_DIR="$home/$user/web/$domain/private/php"
ENV_FILE="$APP_DIR/.env"
CONF_DIR="$home/$user/conf/web/$domain"
PROXY_CONF="$CONF_DIR/nginx.proxy.conf"
PROXY_SSL_CONF="$CONF_DIR/nginx.proxy.ssl.conf"
DEFAULT_PORT=7100
PORT_MIN=7100
PORT_MAX=7999
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

if [ ! -f "$APP_DIR/index.php" ] && [ ! -f "$APP_DIR/public/index.php" ]; then
    cat > "$APP_DIR/index.php" << 'PHPEOF'
<?php
$port = 7100;
$envFile = __DIR__ . '/.env';
if (file_exists($envFile)) {
    $env = file_get_contents($envFile);
    if (preg_match('/^PORT=(.+)$/m', $env, $m)) {
        $port = trim($m[1], ""' 	");
    }
}

header('Content-Type: application/json');
echo json_encode([
    'status' => 'ok',
    'message' => 'PHP app running behind HestiaCP',
    'domain' => $_SERVER['HTTP_HOST'] ?? 'unknown',
    'runtime' => 'FrankenPHP ' . PHP_MAJOR_VERSION . '.' . PHP_MINOR_VERSION . '.' . PHP_RELEASE_VERSION,
]);
PHPEOF
    chown "$user:$user" "$APP_DIR/index.php"
    chmod 644 "$APP_DIR/index.php"
fi

REQUESTED_PORT=$(mannn_read_env_value PORT "$ENV_FILE")
PORT=$(mannn_resolve_port "$REQUESTED_PORT" "$DEFAULT_PORT" "$PORT_MIN" "$PORT_MAX")

FRANKENPHP_BIN=$(command -v frankenphp 2>/dev/null || echo "/usr/local/bin/frankenphp")
PHP_BIN=$(command -v php 2>/dev/null || echo "/usr/bin/php")

if [ -f "$APP_DIR/artisan" ]; then
    EXEC_START="$PHP_BIN $APP_DIR/artisan octane:start --server=frankenphp --host=127.0.0.1 --port=$PORT"
    DESC="Laravel Octane app for $domain"
elif [ -f "$APP_DIR/public/index.php" ]; then
    EXEC_START="$FRANKENPHP_BIN php-server --root $APP_DIR/public --listen 127.0.0.1:$PORT"
    DESC="PHP app for $domain (FrankenPHP)"
else
    EXEC_START="$FRANKENPHP_BIN php-server --root $APP_DIR --listen 127.0.0.1:$PORT"
    DESC="PHP app for $domain (FrankenPHP)"
fi

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
Description=$DESC
After=network.target

[Service]
Type=simple
User=$user
Group=$user
WorkingDirectory=$APP_DIR
ExecStart=$EXEC_START
Restart=on-failure
RestartSec=5
Environment=PORT=$PORT

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


# Restrict port to localhost only (firewall)
mannn_restrict_port "$PORT" "$user" "$domain"
systemctl daemon-reload >/dev/null 2>&1
if systemctl is-active --quiet "$SVC_NAME" 2>/dev/null; then
    systemctl restart "$SVC_NAME" >/dev/null 2>&1
else
    systemctl enable "$SVC_NAME" >/dev/null 2>&1
    systemctl start "$SVC_NAME" >/dev/null 2>&1
fi
