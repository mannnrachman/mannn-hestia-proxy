#!/bin/bash
# mannn-hestia-proxy — Install dynamic proxy templates for HestiaCP
# Supports: Node.js, Go, Python, FrankenPHP/Laravel Octane, Docker / Compose proxy-only backend
#
# Usage:
#   sudo ./install.sh                  # interactive menu
#   sudo ./install.sh nodejs go python # install specific templates only
#   sudo ./install.sh all              # install all templates
#
# To rebrand: find-and-replace "mannn" across all files before installing

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Run as root or with sudo."
    exit 1
fi

if [ ! -d /usr/local/hestia ]; then
    echo "HestiaCP not found at /usr/local/hestia"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TPL_DIR="/usr/local/hestia/data/templates/web/nginx/php-fpm"

# Template definitions
TEMPLATES=(
    "nodejs|mannn-nodejs-proxy|Node.js proxy (3100-3999)"
    "goproxy|mannn-go-proxy|Go proxy (4100-4999)"
    "frankenphp|mannn-frankenphpoctane-proxy|FrankenPHP / Laravel Octane (7100-7999)"
    "pypyroxy|mannn-python-proxy|Python proxy (8100-8999)"
    "docker|mannn-docker-proxy|Docker / Compose backend proxy only (9100-9999)"
)

# Build lookup arrays
declare -A TPL_LABEL
declare -A TPL_FILE
declare -A TPL_SELECTED

for entry in "${TEMPLATES[@]}"; do
    IFS='|' read -r key file label <<< "$entry"
    TPL_LABEL[$key]="$label"
    TPL_FILE[$key]="$file"
    TPL_SELECTED[$key]=1
done

ALL_KEYS=(nodejs goproxy frankenphp pypyroxy docker)

# --- Mode 1: CLI arguments ---
if [ $# -gt 0 ]; then
    # Reset all to unselected
    for key in "${ALL_KEYS[@]}"; do
        TPL_SELECTED[$key]=0
    done

    if [ "$1" = "all" ]; then
        for key in "${ALL_KEYS[@]}"; do
            TPL_SELECTED[$key]=1
        done
    else
        for arg in "$@"; do
            found=0
            for key in "${ALL_KEYS[@]}"; do
                if [ "$arg" = "$key" ]; then
                    TPL_SELECTED[$key]=1
                    found=1
                    break
                fi
            done
            if [ $found -eq 0 ]; then
                echo "Unknown template: $arg"
                echo "Available: ${ALL_KEYS[*]}"
                exit 1
            fi
        done
    fi
fi

# --- Mode 2: Interactive menu (no args or terminal available) ---
if [ $# -eq 0 ] && [ -t 0 ]; then
    cursor=0
    count=${#ALL_KEYS[@]}

    # Enable raw mode for key detection
    stty_orig=$(stty -g)
    trap 'stty "$stty_orig" 2>/dev/null; echo ""; exit 0' INT

    _draw_menu() {
        tput clear 2>/dev/null || clear
        echo "mannn-hestia-proxy — Select templates to install"
        echo "  Space=toggle  Up/Down=move  Enter=confirm  a=all  q=quit"
        echo ""
        for i in "${!ALL_KEYS[@]}"; do
            key="${ALL_KEYS[$i]}"
            if [ "${TPL_SELECTED[$key]}" -eq 1 ]; then
                mark="[x]"
            else
                mark="[ ]"
            fi
            if [ "$i" -eq "$cursor" ]; then
                printf "  > %s %-12s %s\n" "$mark" "$key" "${TPL_LABEL[$key]}"
            else
                printf "    %s %-12s %s\n" "$mark" "$key" "${TPL_LABEL[$key]}"
            fi
        done
        echo ""
        echo "  mannn-security.sh will always be installed."
    }

    while true; do
        _draw_menu
        # Read single keypress
        stty raw -echo 2>/dev/null
        key=$(dd bs=1 count=1 2>/dev/null)
        stty "$stty_orig" 2>/dev/null

        case "$key" in
            q)
                echo "Cancelled."
                exit 0
                ;;
            $'\033')
                # Read rest of escape sequence
                stty raw -echo 2>/dev/null
                seq1=$(dd bs=1 count=1 2>/dev/null)
                seq2=$(dd bs=1 count=1 2>/dev/null)
                stty "$stty_orig" 2>/dev/null
                if [ "$seq1" = "[" ]; then
                    case "$seq2" in
                        A) [ $cursor -gt 0 ] && cursor=$((cursor - 1)) ;;
                        B) [ $cursor -lt $((count - 1)) ] && cursor=$((cursor + 1)) ;;
                    esac
                fi
                ;;
            ' ')
                key_name="${ALL_KEYS[$cursor]}"
                if [ "${TPL_SELECTED[$key_name]}" -eq 1 ]; then
                    TPL_SELECTED[$key_name]=0
                else
                    TPL_SELECTED[$key_name]=1
                fi
                ;;
            a)
                for k in "${ALL_KEYS[@]}"; do TPL_SELECTED[$k]=1; done
                ;;
            '')
                break
                ;;
        esac
    done

    # Restore terminal
    stty "$stty_orig" 2>/dev/null
    echo ""
fi

# --- Install ---
echo "Installing mannn-hestia-proxy templates..."
echo ""

# Always install security helper
cp "$SCRIPT_DIR/templates/common/mannn-security.sh" "$TPL_DIR/mannn-security.sh"
chmod 644 "$TPL_DIR/mannn-security.sh"
echo "  mannn-security.sh ✓"

INSTALLED=()

for key in "${ALL_KEYS[@]}"; do
    if [ "${TPL_SELECTED[$key]}" -ne 1 ]; then
        echo "  ${TPL_FILE[$key]} — skipped"
        continue
    fi

    NAME="${TPL_FILE[$key]}"
    SRC_DIR="$SCRIPT_DIR/templates/$key"

    cp "$SRC_DIR/$NAME.tpl"  "$TPL_DIR/$NAME.tpl"
    cp "$SRC_DIR/$NAME.stpl" "$TPL_DIR/$NAME.stpl"
    cp "$SRC_DIR/$NAME.sh"   "$TPL_DIR/$NAME.sh"

    chmod 644 "$TPL_DIR/$NAME.tpl" "$TPL_DIR/$NAME.stpl"
    chmod 755 "$TPL_DIR/$NAME.sh"

    echo "  $NAME ✓"
    INSTALLED+=("$key")
done

echo ""
if [ ${#INSTALLED[@]} -eq 0 ]; then
    echo "No templates selected. Nothing installed."
    exit 0
fi

echo "Installed templates available in HestiaCP panel:"
echo "  Web → Edit Domain → Web Template"
for key in "${INSTALLED[@]}"; do
    echo "    ${TPL_FILE[$key]} — ${TPL_LABEL[$key]}"
done
echo ""
echo "Security hardening enabled:"
echo "  - localhost proxy ports restricted per runtime"
echo "  - service/container names are collision-safe"
if [ "${TPL_SELECTED[docker]}" -eq 1 ]; then
    echo "  - Docker template is proxy-only: nginx -> 127.0.0.1:BACKEND_PORT"
fi
echo ""

# --- Backup exclusions ---
HESTIA="/usr/local/hestia"
USERS=$("$HESTIA/bin/v-list-users" plain 2>/dev/null | awk '{print $1}' || true)

if [ -n "$USERS" ]; then
    echo "Setup backup exclusions for existing users? [y/N]"
    read -r answer
    if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
        for u in $USERS; do
            "$SCRIPT_DIR/setup-backup-exclusions.sh" "$u" && echo "  $u ✓" || echo "  $u — skipped"
        done
    fi
else
    echo "No HestiaCP users found yet."
    echo "Run this later to setup backup exclusions:"
    echo "  sudo $SCRIPT_DIR/setup-backup-exclusions.sh <user>"
fi

echo ""
echo "See README.md for usage instructions."
