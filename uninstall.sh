#!/bin/bash
# mannn-hestia-proxy — Uninstall templates from HestiaCP
#
# Usage:
#   sudo ./uninstall.sh                  # interactive menu
#   sudo ./uninstall.sh nodejs go python docker # uninstall specific templates only
#   sudo ./uninstall.sh all              # uninstall all templates

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

# Template definitions
TEMPLATES=(
    "nodejs|mannn-nodejs-proxy|Node.js proxy"
    "goproxy|mannn-go-proxy|Go proxy"
    "frankenphp|mannn-frankenphpoctane-proxy|FrankenPHP / Laravel Octane"
    "pypyroxy|mannn-python-proxy|Python proxy"
    "docker|mannn-docker-proxy|Docker / Compose backend proxy only"
    "laravel|mannn-laravel|Laravel PHP-FPM (dynamic image route fix)"
)

declare -A TPL_LABEL
declare -A TPL_FILE
declare -A TPL_SELECTED

for entry in "${TEMPLATES[@]}"; do
    IFS='|' read -r key file label <<< "$entry"
    TPL_LABEL[$key]="$label"
    TPL_FILE[$key]="$file"
    TPL_SELECTED[$key]=1
done

ALL_KEYS=(nodejs goproxy frankenphp pypyroxy docker laravel)

# --- Mode 1: CLI arguments ---
if [ $# -gt 0 ]; then
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

# --- Mode 2: Interactive menu ---
if [ $# -eq 0 ] && [ -t 0 ]; then
    cursor=0
    count=${#ALL_KEYS[@]}

    stty_orig=$(stty -g)
    trap 'stty "$stty_orig" 2>/dev/null; echo ""; exit 0' INT

    _draw_menu() {
        tput clear 2>/dev/null || clear
        echo "mannn-hestia-proxy — Select templates to UNINSTALL"
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
        echo "  mannn-security.sh will be removed if all templates are selected."
    }

    while true; do
        _draw_menu
        stty raw -echo 2>/dev/null
        key=$(dd bs=1 count=1 2>/dev/null)
        stty "$stty_orig" 2>/dev/null

        case "$key" in
            q)
                echo "Cancelled."
                exit 0
                ;;
            $'\033')
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

    stty "$stty_orig" 2>/dev/null
    echo ""
fi

# --- Uninstall ---
echo "Removing mannn-hestia-proxy templates..."
echo ""

echo "WARNING: switch domains back to a PHP template before removing services:"
echo "  v-change-web-domain-tpl user domain default"
echo ""

# Refuse to remove templates that domains still reference: HestiaCP rebuilds
# render the domain nginx conf from the template file, so removing one in use
# breaks nginx -t on the next rebuild/apply of that domain. Override with
# MANNN_FORCE_UNINSTALL=1 (domains will need v-change-web-domain-tpl anyway).
if [ "${MANNN_FORCE_UNINSTALL:-0}" != "1" ]; then
    USERS_DATA="/usr/local/hestia/data/users"
    BUSY=0
    for key in "${ALL_KEYS[@]}"; do
        [ "${TPL_SELECTED[$key]}" -ne 1 ] && continue
        NAME="${TPL_FILE[$key]}"
        DOMAINS="$(grep -h "TPL='$NAME'" "$USERS_DATA"/*/web.conf 2>/dev/null \
            | sed -n "s/^DOMAIN='\([^']*\)'.*/\1/p" || true)"
        if [ -n "$DOMAINS" ]; then
            BUSY=1
            echo "ERROR: template $NAME is still used by domain(s):" >&2
            echo "$DOMAINS" | sed 's/^/  - /' >&2
            echo "Switch them first: v-change-web-domain-tpl <user> <domain> default" >&2
        fi
    done
    if [ "$BUSY" -eq 1 ]; then
        echo "Refusing to uninstall (set MANNN_FORCE_UNINSTALL=1 to override)." >&2
        exit 1
    fi
fi

# Load security helper (if present) before removing template files, so a full
# uninstall can flush firewall rules and the port registry.
SEC_FILE="$TPL_DIR/mannn-security.sh"
HAVE_SEC=0
if [ -f "$SEC_FILE" ]; then
    # shellcheck source=/dev/null
    source "$SEC_FILE"
    HAVE_SEC=1
fi

REMOVED=0

for key in "${ALL_KEYS[@]}"; do
    if [ "${TPL_SELECTED[$key]}" -ne 1 ]; then
        echo "  ${TPL_FILE[$key]} — skipped"
        continue
    fi

    NAME="${TPL_FILE[$key]}"
    for ext in sh tpl stpl; do
        FILE="$TPL_DIR/$NAME.$ext"
        if [ -f "$FILE" ]; then
            rm "$FILE"
            echo "  Removed $NAME.$ext"
            REMOVED=$((REMOVED + 1))
        fi
    done
done

# Remove security helper if all templates removed
ALL_SELECTED=1
for key in "${ALL_KEYS[@]}"; do
    if [ "${TPL_SELECTED[$key]}" -ne 1 ]; then
        ALL_SELECTED=0
        break
    fi
done

if [ $ALL_SELECTED -eq 1 ]; then
    # Stop, disable and remove every mannn-* systemd service
    for unit_file in /etc/systemd/system/mannn-*.service; do
        [ -e "$unit_file" ] || continue
        unit="$(basename "$unit_file")"
        systemctl stop "$unit" 2>/dev/null || true
        systemctl disable "$unit" 2>/dev/null || true
        rm -f "$unit_file"
        echo "  Removed service $unit"
    done
    systemctl reset-failed 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true

    # Flush mannn-* firewall rules and release the port registry
    if [ $HAVE_SEC -eq 1 ]; then
        mannn_unrestrict_all || true
        mannn_port_release_all || true
    else
        echo "  WARNING: mannn-security.sh missing — manual cleanup may be needed:" >&2
        echo "    iptables -S INPUT | grep 'mannn-'   # then remove matching rules with iptables -D" >&2
    fi
    rm -rf /usr/local/hestia/data/mannn-ports

    if [ -f "$SEC_FILE" ]; then
        rm -f "$SEC_FILE"
        echo "  Removed mannn-security.sh"
    fi
    # Remove nginx conf files installed by install.sh
    REMOVED_NGINX_CONF=0
    for conf in /etc/nginx/conf.d/mannn-rate-limit.conf /etc/nginx/conf.d/mannn-upgrade-map.conf; do
        if [ -f "$conf" ]; then
            rm -f "$conf"
            echo "  Removed $(basename "$conf")"
            REMOVED_NGINX_CONF=1
        fi
    done
    if [ $REMOVED_NGINX_CONF -eq 1 ]; then
        if nginx -t >/dev/null 2>&1; then
            systemctl reload nginx >/dev/null 2>&1 || echo "  WARNING: nginx reload failed — check systemctl status nginx" >&2
        else
            echo "  ERROR: nginx -t failed after removing mannn conf files — nginx NOT reloaded. Run 'nginx -t' to inspect." >&2
            exit 1
        fi
    fi
else
    echo "  mannn-security.sh — kept (some templates still installed)"
fi

echo ""
if [ $REMOVED -eq 0 ]; then
    echo "No templates selected. Nothing removed."
    exit 0
fi

echo "Templates removed."
echo ""
if [ $ALL_SELECTED -eq 1 ]; then
    echo "mannn-* services, firewall rules, and the port registry have been cleaned up."
    echo "NOTE: app directories (web/<domain>/) are NOT removed."
else
    echo "NOTE: mannn-* services and firewall rules remain in place (partial uninstall)."
fi
