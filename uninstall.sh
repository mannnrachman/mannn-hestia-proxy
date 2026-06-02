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

ALL_KEYS=(nodejs goproxy frankenphp pypyroxy docker)

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
    SEC_FILE="$TPL_DIR/mannn-security.sh"
    if [ -f "$SEC_FILE" ]; then
        rm "$SEC_FILE"
        echo "  Removed mannn-security.sh"
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
echo "NOTE: Systemd services (mannn-*) and app directories are NOT removed."
echo "To clean up services manually:"
echo "  systemctl stop mannn-{generated-name}"
echo "  systemctl disable mannn-{generated-name}"
echo "  rm /etc/systemd/system/mannn-{generated-name}.service"
echo "  systemctl daemon-reload"
echo ""
echo "Switch domains back to a PHP template before removing services:"
echo "  v-change-web-domain-tpl user domain default"
