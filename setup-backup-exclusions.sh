#!/bin/bash
# mannn-hestia-proxy — Setup backup exclusions for proxy domains
# Excludes heavy runtime dirs (node_modules, venv, vendor, binaries) from HestiaCP backups
# These dirs are auto-rebuilt when re-applying the template after restore.
#
# Usage:
#   sudo ./setup-backup-exclusions.sh <user>           # apply exclusions
#   sudo ./setup-backup-exclusions.sh <user> --revert  # restore previous config
#   All users: for u in $(v-list-users plain | cut -f1); do sudo ./setup-backup-exclusions.sh $u; done

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Run as root or with sudo."
    exit 1
fi

if [ ! -d /usr/local/hestia ]; then
    echo "HestiaCP not found at /usr/local/hestia"
    exit 1
fi

if [ -z "$1" ]; then
    echo "Usage: sudo ./setup-backup-exclusions.sh <user> [--revert]"
    echo "       All users: for u in \$(v-list-users plain | cut -f1); do sudo ./setup-backup-exclusions.sh \$u; done"
    exit 1
fi

user="$1"
action="$2"
HESTIA="/usr/local/hestia"
USER_DATA="$HESTIA/data/users/$user"
CONF="$USER_DATA/backup-excludes.conf"

# Verify user exists
if [ ! -d "$USER_DATA" ]; then
    echo "User '$user' not found in HestiaCP."
    exit 1
fi

# --- Revert mode ---
if [ "$action" = "--revert" ]; then
    LATEST_BAK=$(ls -t "$CONF.bak."* 2>/dev/null | head -1)
    if [ -z "$LATEST_BAK" ]; then
        echo "No backup found for user '$user'. Nothing to revert."
        exit 1
    fi

    cp "$LATEST_BAK" "$CONF"
    chmod 660 "$CONF"
    echo "Reverted backup exclusions for '$user' from $(basename "$LATEST_BAK")."
    echo "Backup file kept: $LATEST_BAK"
    exit 0
fi

# --- Apply mode ---
TMPFILE=$(mktemp)
trap "rm -f $TMPFILE" EXIT

# Excluded paths (relative to /home/$user/web/$domain/):
# - private/nodejs/node_modules  → reinstall with npm install
# - private/go/server            → rebuild with go build
# - private/python/venv          → recreate with python3 -m venv + pip install
# - private/php/vendor           → reinstall with composer install
# - private/php/node_modules     → reinstall with npm install
#
# Using * wildcard — safe because non-proxy domains don't have these paths

PROXY_EXCLUDES="*:private/nodejs/node_modules:private/go/server:private/python/venv:private/php/vendor:private/php/node_modules"

# Preserve existing exclusions for other categories
WEB_VAL=""
DNS_VAL=""
MAIL_VAL=""
DB_VAL=""
CRON_VAL=""
USER_VAL=""

if [ -f "$CONF" ]; then
    # Backup existing config before modifying
    cp "$CONF" "$CONF.bak.$(date +%Y%m%d%H%M%S)"
    WEB_VAL=$(grep '^WEB=' "$CONF" | head -1 | sed "s/^WEB='//" | sed "s/'$//")
    DNS_VAL=$(grep '^DNS=' "$CONF" | head -1 | sed "s/^DNS='//" | sed "s/'$//")
    MAIL_VAL=$(grep '^MAIL=' "$CONF" | head -1 | sed "s/^MAIL='//" | sed "s/'$//")
    DB_VAL=$(grep '^DB=' "$CONF" | head -1 | sed "s/^DB='//" | sed "s/'$//")
    CRON_VAL=$(grep '^CRON=' "$CONF" | head -1 | sed "s/^CRON='//" | sed "s/'$//")
    USER_VAL=$(grep '^USER=' "$CONF" | head -1 | sed "s/^USER='//" | sed "s/'$//")
fi

# Check if proxy exclusions already exist in WEB value
if echo "$WEB_VAL" | grep -q "private/nodejs/node_modules"; then
    echo "Proxy backup exclusions already set for user '$user'."
    exit 0
fi

# Append proxy exclusions to existing WEB value
if [ -n "$WEB_VAL" ]; then
    WEB_VAL="${WEB_VAL},${PROXY_EXCLUDES}"
else
    WEB_VAL="${PROXY_EXCLUDES}"
fi

# Write config file
cat > "$TMPFILE" << EOF
WEB='${WEB_VAL}'
DNS='${DNS_VAL}'
MAIL='${MAIL_VAL}'
DB='${DB_VAL}'
CRON='${CRON_VAL}'
USER='${USER_VAL}'
EOF

# Apply via HestiaCP CLI
$HESTIA/bin/v-update-user-backup-exclusions "$user" "$TMPFILE"

echo "Backup exclusions set for user '$user':"
echo "  private/nodejs/node_modules (Node.js — npm install)"
echo "  private/go/server           (Go — go build)"
echo "  private/python/venv         (Python — pip install)"
echo "  private/php/vendor          (PHP — composer install)"
echo "  private/php/node_modules    (PHP — npm install)"
echo ""
echo "Source code, .env, package.json, requirements.txt, go.mod, and small app config files stay in backup."
echo ""
echo "To revert: sudo ./setup-backup-exclusions.sh $user --revert"
