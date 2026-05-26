#!/bin/bash
# mannn-docker-proxy — Safer dynamic proxy template for Docker apps on HestiaCP
# Args: $1=user $2=domain $3=ip $4=home $5=docroot
# Auto: directory, .env, nginx proxy, restricted docker pull/run, systemd service

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
DEFAULT_CONTAINER_PORT=8080
DEFAULT_IMAGE="nginx:alpine"
CONTAINER_NAME="$(mannn_unit_name "$user" "$domain")"
SVC_NAME="$CONTAINER_NAME"
SVC_FILE="/etc/systemd/system/$SVC_NAME.service"

mannn_prepare_dir "$APP_DIR" "$user:$user" 755
mannn_prepare_dir "$CONF_DIR" "$user:$user" 750
mannn_abort_if_symlink "$ENV_FILE"
mannn_abort_if_symlink "$PROXY_CONF"
mannn_abort_if_symlink "$PROXY_SSL_CONF"
mannn_abort_if_symlink "$SVC_FILE"

if [ ! -f "$ENV_FILE" ]; then
    cat > "$ENV_FILE" << ENVDEF
PORT=$DEFAULT_PORT
CONTAINER_PORT=$DEFAULT_CONTAINER_PORT
IMAGE=$DEFAULT_IMAGE
ENVDEF
fi
chown "$user:$user" "$ENV_FILE" 2>/dev/null
chmod 600 "$ENV_FILE"

if [ -f "$APP_DIR/docker-compose.yml" ] || [ -f "$APP_DIR/compose.yaml" ] || [ -f "$APP_DIR/compose.yml" ] || [ -f "$APP_DIR/Dockerfile" ]; then
    echo "Unsafe Docker build/compose files detected in $APP_DIR. This hardened template only supports prebuilt images via IMAGE=... in .env." >&2
    exit 1
fi

REQUESTED_PORT=$(mannn_read_env_value PORT "$ENV_FILE")
PORT=$(mannn_resolve_port "$REQUESTED_PORT" "$DEFAULT_PORT" "$PORT_MIN" "$PORT_MAX")

CONTAINER_PORT=$(mannn_read_env_value CONTAINER_PORT "$ENV_FILE")
if ! [[ "$CONTAINER_PORT" =~ ^[0-9]+$ ]] || [ "$CONTAINER_PORT" -lt 1 ] || [ "$CONTAINER_PORT" -gt 65535 ]; then
    CONTAINER_PORT=$DEFAULT_CONTAINER_PORT
fi

IMAGE=$(mannn_read_env_value IMAGE "$ENV_FILE")
if [ -z "$IMAGE" ]; then
    IMAGE="$DEFAULT_IMAGE"
fi

if ! [[ "$IMAGE" =~ ^[a-zA-Z0-9./:_-]+$ ]]; then
    echo "Invalid IMAGE value in $ENV_FILE" >&2
    exit 1
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
Description=Docker app for $domain (prebuilt image only)
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=-/usr/bin/docker stop $CONTAINER_NAME
ExecStartPre=-/usr/bin/docker rm $CONTAINER_NAME
ExecStartPre=/usr/bin/docker pull $IMAGE
ExecStart=/usr/bin/docker run -d --name $CONTAINER_NAME --read-only --tmpfs /tmp:rw,noexec,nosuid,size=64m --security-opt no-new-privileges:true --cap-drop ALL --pids-limit 256 -p 127.0.0.1:$PORT:$CONTAINER_PORT --restart unless-stopped $IMAGE
ExecStop=/usr/bin/docker stop $CONTAINER_NAME

[Install]
WantedBy=multi-user.target
SVCEOF

/usr/bin/docker stop "$CONTAINER_NAME" >/dev/null 2>&1
/usr/bin/docker rm "$CONTAINER_NAME" >/dev/null 2>&1
/usr/bin/docker pull "$IMAGE" >/dev/null 2>&1
/usr/bin/docker run -d     --name "$CONTAINER_NAME"     --read-only     --tmpfs /tmp:rw,noexec,nosuid,size=64m     --security-opt no-new-privileges:true     --cap-drop ALL     --pids-limit 256     -p "127.0.0.1:$PORT:$CONTAINER_PORT"     --restart unless-stopped     "$IMAGE" >/dev/null 2>&1

systemctl daemon-reload >/dev/null 2>&1
if systemctl is-enabled --quiet "$SVC_NAME" 2>/dev/null; then
    systemctl restart "$SVC_NAME" >/dev/null 2>&1
else
    systemctl enable "$SVC_NAME" >/dev/null 2>&1
fi
