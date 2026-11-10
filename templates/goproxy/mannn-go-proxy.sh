#!/bin/bash
# mannn-go-proxy — Dynamic proxy template for Go apps on HestiaCP
# Args: $1=user $2=domain $3=ip $4=home $5=docroot
# Auto: directory, .env, placeholder, go build, nginx proxy, systemd service

user="$1"
domain="$2"
# shellcheck disable=SC2034  # $3=ip, $5=docroot: HestiaCP always passes 5 args; unused by proxy templates
ip="$3"
home="$4"
# shellcheck disable=SC2034
docroot="$5"

set -eo pipefail

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
chown "$user:$user" "$ENV_FILE" 2>/dev/null || true
chmod 600 "$ENV_FILE" 2>/dev/null || true

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
    port := os.Getenv("PORT")
    if port == "" {
        port = loadPort("4100")
    }

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
    # Module-mode Go (default since 1.16) refuses to build a bare main.go:
    # ship a minimal go.mod with the placeholder or the first build fails.
    if [ ! -f "$APP_DIR/go.mod" ]; then
        printf 'module mannn-placeholder\n\ngo 1.21\n' > "$APP_DIR/go.mod"
        chown "$user:$user" "$APP_DIR/go.mod"
        chmod 644 "$APP_DIR/go.mod"
    fi
fi

GO_BIN=$(command -v go 2>/dev/null || echo "/usr/local/go/bin/go")
if [ -f "$APP_DIR/main.go" ] && [ -x "$GO_BIN" ]; then
    mkdir -p "$APP_DIR/.cache" 2>/dev/null || true
    chown "$user:$user" "$APP_DIR/.cache" 2>/dev/null || true
    if command -v runuser >/dev/null 2>&1; then
        runuser -u "$user" -- env HOME="$APP_DIR" "$GO_BIN" build -o server . || echo "mannn: go build failed — check main.go" >&2
    else
        env HOME="$APP_DIR" "$GO_BIN" build -o server . 2>/dev/null || echo "mannn: go build failed — check main.go" >&2
    fi
    chown "$user:$user" "$APP_DIR/server" 2>/dev/null || true
    chmod 755 "$APP_DIR/server" 2>/dev/null || true
fi

BINARY="$APP_DIR/server"
if [ ! -f "$BINARY" ] && [ -f "$APP_DIR/app" ]; then
    BINARY="$APP_DIR/app"
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
Description=Go app for $domain
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$user
Group=$user
WorkingDirectory=$APP_DIR
ExecStart=$BINARY
Restart=on-failure
RestartSec=5
TimeoutStopSec=20
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
    MemoryMax=256M
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
