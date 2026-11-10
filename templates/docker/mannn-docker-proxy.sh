#!/bin/bash
# mannn-docker-proxy — Reverse-proxy-only template for Docker / Compose apps on HestiaCP
# Args: $1=user $2=domain $3=ip $4=home $5=docroot
# Auto: directory, .env, nginx proxy only. Does NOT run docker build/pull/compose.

user="$1"
domain="$2"
# shellcheck disable=SC2034  # $3=ip, $5=docroot: HestiaCP always passes 5 args; unused by proxy templates
ip="$3"
home="$4"
# shellcheck disable=SC2034
docroot="$5"

set -eo pipefail

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
chown "$user:$user" "$ENV_FILE" 2>/dev/null || true
chmod 600 "$ENV_FILE" 2>/dev/null || true

REQUESTED_PORT=$(mannn_read_env_value BACKEND_PORT "$ENV_FILE")
PORT=$(mannn_resolve_port "$REQUESTED_PORT" "$DEFAULT_PORT" "$PORT_MIN" "$PORT_MAX")

if ! mannn_port_migrate "$PORT" "$SVC_NAME"; then
    mannn_write_disabled_confs "$PROXY_CONF" "$PROXY_SSL_CONF"
    chown "root:$user" "$PROXY_CONF" "$PROXY_SSL_CONF" 2>/dev/null || true
    chmod 640 "$PROXY_CONF" "$PROXY_SSL_CONF" 2>/dev/null || true
    echo "mannn: port $PORT already used by another domain — set another BACKEND_PORT in $ENV_FILE and re-apply" >&2
    exit 1
fi

rm -f "$PROXY_CONF" "$PROXY_SSL_CONF"
mannn_write_proxy_confs "$PROXY_CONF" "$PROXY_SSL_CONF" "$PORT"

chown "root:$user" "$PROXY_CONF" "$PROXY_SSL_CONF" 2>/dev/null || true
chmod 640 "$PROXY_CONF" "$PROXY_SSL_CONF" 2>/dev/null || true

if [ -f "$SVC_FILE" ]; then
    systemctl stop "$SVC_NAME" >/dev/null 2>&1 || true
    systemctl disable "$SVC_NAME" >/dev/null 2>&1 || true
    rm -f "$SVC_FILE"
    systemctl daemon-reload >/dev/null 2>&1 || true
fi
