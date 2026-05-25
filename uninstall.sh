#!/bin/bash
# mannn-hestia-proxy — Uninstall templates from HestiaCP
# Usage: sudo ./uninstall.sh

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Run as root or with sudo."
    exit 1
fi

if [ ! -d /usr/local/hestia ]; then
    echo "HestiaCP not found at /usr/local/hestia"
    exit 1
fi

TPL_DIR="/usr/local/hestia/data/templates/web/nginx/php-fpm"

echo "Removing mannn-hestia-proxy templates..."

for name in mannn-nodejs-proxy mannn-go-proxy mannn-python-proxy mannn-frankenphpoctane-proxy mannn-docker-proxy; do
    for ext in tpl stpl sh; do
        FILE="$TPL_DIR/$name.$ext"
        if [ -f "$FILE" ]; then
            rm "$FILE"
            echo "  Removed $name.$ext"
        fi
    done
done

echo ""
echo "Templates removed."
echo ""
echo "NOTE: Systemd services (mannn-*) and app directories are NOT removed."
echo "To clean up services manually:"
echo "  systemctl stop mannn-{domain}"
echo "  systemctl disable mannn-{domain}"
echo "  rm /etc/systemd/system/mannn-{domain}.service"
echo "  systemctl daemon-reload"
echo ""
echo "Switch domains back to a PHP template before removing services:"
echo "  v-change-web-domain-tpl user domain default"
