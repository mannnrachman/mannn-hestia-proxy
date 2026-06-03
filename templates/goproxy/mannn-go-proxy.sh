#!/bin/bash
# mannn-go-proxy — Dynamic proxy template for Go apps on HestiaCP
# Args: $1=user $2=domain $3=ip $4=home $5=docroot
# Auto: directory, .env, placeholder, go build, nginx proxy, systemd service

user="$1"
domain="$2"
ip="$3"
home="$4"
docroot="$5"

. "/usr/local/hestia/data/templates/web/nginx/php-fpm/mannn-security.sh"

APP_DIR="$home/$user/web/$domain/private/go"
ENV_FILE="$APP_DIR/.env"
CONF_DIR="$home/$user/conf/web/$domain"
PROXY_CONF="$CONF_DIR/nginx.proxy.conf"
PROXY_SSL_CONF="$CONF_DIR/nginx.proxy.ssl.conf"
DEFAULT_PORT=4100
PORT_MIN=4100
PORT_MAX=4999
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

if [ ! -f "$APP_DIR/main.go" ] && [ ! -f "$APP_DIR/server" ] && [ ! -f "$APP_DIR/app" ]; then
    cat > "$APP_DIR/main.go" << 'GOEOF'
package main

import (
    "bufio"
    "encoding/json"
    "fmt"
    "net/http"
    "os"
    "strings"
)

func main() {
    port := loadPort("4100")

    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        w.Header().Set("Content-Type", "application/json")
        json.NewEncoder(w).Encode(map[string]string{
            "status":  "ok",
            "message": "Go app running",
            "domain":  r.Host,
        })
    })

    fmt.Printf("Listening on port %s\n", port)
    http.ListenAndServe("127.0.0.1:"+port, nil)
}

func loadPort(defaultPort string) string {
    f, err := os.Open(".env")
    if err != nil {
        return defaultPort
    }
    defer f.Close()
    scanner := bufio.NewScanner(f)
    for scanner.Scan() {
        line := strings.TrimSpace(scanner.Text())
        if strings.HasPrefix(line, "PORT=") {
            return strings.Trim(strings.TrimPrefix(line, "PORT="), "\"'")
        }
    }
    return defaultPort
}
GOEOF
    chown "$user:$user" "$APP_DIR/main.go"
    chmod 644 "$APP_DIR/main.go"
fi

GO_BIN=$(command -v go 2>/dev/null || echo "/usr/local/go/bin/go")
if [ -f "$APP_DIR/main.go" ] && [ -x "$GO_BIN" ]; then
    cd "$APP_DIR"
    "$GO_BIN" build -o server . 2>/dev/null
    chown "$user:$user" "$APP_DIR/server" 2>/dev/null
    chmod 755 "$APP_DIR/server" 2>/dev/null
fi

BINARY="$APP_DIR/server"
if [ ! -f "$BINARY" ] && [ -f "$APP_DIR/app" ]; then
    BINARY="$APP_DIR/app"
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
Description=Go app for $domain
After=network.target

[Service]
Type=simple
User=$user
Group=$user
WorkingDirectory=$APP_DIR
ExecStart=$BINARY
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
