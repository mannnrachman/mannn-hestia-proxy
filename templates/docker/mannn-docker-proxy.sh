#!/bin/bash
# mannn-docker-proxy — Dynamic proxy template for Docker apps on HestiaCP
# Args: $1=user $2=domain $3=ip $4=home $5=docroot
# Auto: directory, .env, placeholder Dockerfile, docker build/run, nginx proxy, systemd service

user="$1"
domain="$2"
ip="$3"
home="$4"
docroot="$5"

APP_DIR="$home/$user/web/$domain/private/docker"
ENV_FILE="$APP_DIR/.env"
CONF_DIR="$home/$user/conf/web/$domain"
PROXY_CONF="$CONF_DIR/nginx.proxy.conf"
PROXY_SSL_CONF="$CONF_DIR/nginx.proxy.ssl.conf"
DEFAULT_PORT=9000
DEFAULT_CONTAINER_PORT=80
CONTAINER_NAME="mannn-$(echo "$domain" | tr '.' '-')"
SVC_NAME="mannn-$(echo "$domain" | tr '.' '-')"
SVC_FILE="/etc/systemd/system/$SVC_NAME.service"

# --- App directory ---
mkdir -p "$APP_DIR"
chown "$user:$user" "$APP_DIR"
chmod 755 "$APP_DIR"

# --- Default .env ---
if [ ! -f "$ENV_FILE" ]; then
    cat > "$ENV_FILE" << ENVDEF
PORT=$DEFAULT_PORT
CONTAINER_PORT=$DEFAULT_CONTAINER_PORT
ENVDEF
fi
chown "$user:$user" "$ENV_FILE" 2>/dev/null
chmod 600 "$ENV_FILE"

# --- Placeholder Dockerfile ---
if [ ! -f "$APP_DIR/Dockerfile" ] && [ ! -f "$APP_DIR/docker-compose.yml" ]; then
    cat > "$APP_DIR/Dockerfile" << 'DOCKEREOF'
FROM nginx:alpine
RUN echo '{"status":"ok","message":"Docker app running behind HestiaCP"}' > /usr/share/nginx/html/index.html
COPY <<'NCONF' /etc/nginx/conf.d/default.conf
server {
    listen 80 default_server;
    root /usr/share/nginx/html;
    location / {
        default_type application/json;
    }
}
NCONF
DOCKEREOF
    chown "$user:$user" "$APP_DIR/Dockerfile"
    chmod 644 "$APP_DIR/Dockerfile"
fi

# --- Read PORT from .env ---
PORT=$(grep -oP '^PORT=\K.*' "$ENV_FILE" 2>/dev/null | tr -d '"' | tr -d "'")
if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
    PORT=$DEFAULT_PORT
fi
CONTAINER_PORT=$(grep -oP '^CONTAINER_PORT=\K.*' "$ENV_FILE" 2>/dev/null | tr -d '"' | tr -d "'")
if ! [[ "$CONTAINER_PORT" =~ ^[0-9]+$ ]] || [ "$CONTAINER_PORT" -lt 1 ] || [ "$CONTAINER_PORT" -gt 65535 ]; then
    CONTAINER_PORT=$DEFAULT_CONTAINER_PORT
fi

# --- Stop and remove old container ---
docker stop "$CONTAINER_NAME" >/dev/null 2>&1
docker rm "$CONTAINER_NAME" >/dev/null 2>&1

# --- Build and run container ---
if [ -f "$APP_DIR/docker-compose.yml" ]; then
    # docker-compose mode
    cat > "$SVC_FILE" << SVCEOF
[Unit]
Description=Docker app for $domain (compose)
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/docker compose up -d --build
ExecStop=/usr/bin/docker compose down

[Install]
WantedBy=multi-user.target
SVCEOF
    cd "$APP_DIR" && docker compose up -d --build >/dev/null 2>&1
else
    # Dockerfile mode
    docker build -t "$CONTAINER_NAME" "$APP_DIR" >/dev/null 2>&1
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "127.0.0.1:$PORT:$CONTAINER_PORT" \
        --restart unless-stopped \
        "$CONTAINER_NAME" >/dev/null 2>&1

    cat > "$SVC_FILE" << SVCEOF
[Unit]
Description=Docker app for $domain
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$APP_DIR
ExecStartPre=-/usr/bin/docker stop $CONTAINER_NAME
ExecStartPre=-/usr/bin/docker rm $CONTAINER_NAME
ExecStartPre=/usr/bin/docker build -t $CONTAINER_NAME $APP_DIR
ExecStart=/usr/bin/docker run -d --name $CONTAINER_NAME -p 127.0.0.1:$PORT:$CONTAINER_PORT --restart unless-stopped $CONTAINER_NAME
ExecStop=/usr/bin/docker stop $CONTAINER_NAME

[Install]
WantedBy=multi-user.target
SVCEOF
fi

# --- Clean old proxy configs ---
rm -f "$PROXY_CONF" "$PROXY_SSL_CONF"

# --- Generate nginx proxy configs ---
mkdir -p "$CONF_DIR"

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

# --- Enable systemd service ---
systemctl daemon-reload >/dev/null 2>&1
systemctl enable "$SVC_NAME" >/dev/null 2>&1
