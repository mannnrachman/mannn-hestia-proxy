#!/bin/bash
# mannn-hestia-proxy — Install dynamic proxy templates for HestiaCP
# Supports: Node.js, Go, Python, FrankenPHP/Laravel Octane, Docker
#
# Usage: sudo ./install.sh
# To rebrand: find-and-replace "mannn" across all files before installing

set -e

# Check root
if [ "$EUID" -ne 0 ]; then
    echo "Run as root or with sudo."
    exit 1
fi

# Check HestiaCP
if [ ! -d /usr/local/hestia ]; then
    echo "HestiaCP not found at /usr/local/hestia"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TPL_DIR="/usr/local/hestia/data/templates/web/nginx/php-fpm"

echo "Installing mannn-hestia-proxy templates..."

# Install each template
for runtime in nodejs goproxy pypyroxy frankenphp docker; do
    SRC_DIR="$SCRIPT_DIR/templates/$runtime"

    case $runtime in
        nodejs)     NAME="mannn-nodejs-proxy" ;;
        goproxy)    NAME="mannn-go-proxy" ;;
        pypyroxy)   NAME="mannn-python-proxy" ;;
        frankenphp) NAME="mannn-frankenphpoctane-proxy" ;;
        docker)     NAME="mannn-docker-proxy" ;;
    esac

    cp "$SRC_DIR/$NAME.tpl"  "$TPL_DIR/$NAME.tpl"
    cp "$SRC_DIR/$NAME.stpl" "$TPL_DIR/$NAME.stpl"
    cp "$SRC_DIR/$NAME.sh"   "$TPL_DIR/$NAME.sh"

    chmod 644 "$TPL_DIR/$NAME.tpl" "$TPL_DIR/$NAME.stpl"
    chmod 755 "$TPL_DIR/$NAME.sh"

    echo "  $NAME ✓"
done

echo ""
echo "Installed. Templates available in HestiaCP panel:"
echo "  Web → Edit Domain → Web Template → mannn-nodejs-proxy"
echo "  Web → Edit Domain → Web Template → mannn-go-proxy"
echo "  Web → Edit Domain → Web Template → mannn-python-proxy"
echo "  Web → Edit Domain → Web Template → mannn-frankenphpoctane-proxy"
echo "  Web → Edit Domain → Web Template → mannn-docker-proxy"
echo ""
echo "See README.md for usage instructions."
