#!/bin/bash
# mannn-docker-proxy — Reverse-proxy-only template for Docker / Compose apps on HestiaCP
# Args: $1=user $2=domain $3=ip $4=home $5=docroot
# Auto: directory, .env, nginx proxy only. Does NOT run docker build/pull/compose.

user="$1"
domain="$2"
ip="$3"
home="$4"
docroot="$5"

. "/usr/local/hestia/data/templates/web/nginx/php-fpm/mannn-security.sh"

APP_DIR="$home/$user/web/$domain/private/docker"
ENV_FILE="$APP_DIR/.env"
CONF_DIR="$home/$user/conf/web/$domain"
PROXY_CONF="$CONF_DIR/nginx.proxy.conf"
PROXY_SSL_CONF="$CONF_DIR/nginx.proxy.ssl.conf"
DEFAULT_PORT=9100
PORT_MIN=9100
PORT_MAX=9999
SVC_NAME="$(mannn_unit_name "$user" "$domain")"
SVC_FILE="/etc/systemd/system/$SVC_NAME.service"

mannn_prepare_dir "$APP_DIR" "$user:$user" 755
mannn_prepare_dir "$CONF_DIR" "$user:$user" 750
mannn_abort_if_symlink "$ENV_FILE"
mannn_abort_if_symlink "$PROXY_CONF"
mannn_abort_if_symlink "$PROXY_SSL_CONF"

if [ ! -f "$ENV_FILE" ]; then
    cat > "$ENV_FILE" << ENVDEF
# Reverse-proxy-only mode.
# Start your container or docker compose stack separately.
# Then point nginx at its localhost port.
BACKEND_PORT=$DEFAULT_PORT
ENVDEF
fi
chown "$user:$user" "$ENV_FILE" 2>/dev/null
chmod 600 "$ENV_FILE"

REQUESTED_PORT=$(mannn_read_env_value BACKEND_PORT "$ENV_FILE")
PORT=$(mannn_resolve_port "$REQUESTED_PORT" "$DEFAULT_PORT" "$PORT_MIN" "$PORT_MAX")

# Restrict port to localhost only (firewall)
mannn_restrict_port "$PORT" "$user" "$domain"

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

if [ -f "$SVC_FILE" ]; then
    systemctl stop "$SVC_NAME" >/dev/null 2>&1 || true
    systemctl disable "$SVC_NAME" >/dev/null 2>&1 || true
    rm -f "$SVC_FILE"
    systemctl daemon-reload >/dev/null 2>&1 || true
fi
