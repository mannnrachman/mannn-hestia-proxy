#!/bin/bash
# Shared security helpers for mannn-hestia-proxy templates.

set -u

# Port registry directory (override-able for testing).
MANNN_PORT_DIR="${MANNN_PORT_DIR:-/usr/local/hestia/data/mannn-ports}"
# Set MANNN_REQUIRE_FIREWALL=1 to make apply fail (503 stub) when no firewall
# binary is available instead of leaving the app port world-reachable.
MANNN_REQUIRE_FIREWALL="${MANNN_REQUIRE_FIREWALL:-0}"
MANNN_BLOCKED_PORTS="1 7 9 11 13 15 17 19 20 21 22 23 25 37 42 53 67 68 69 79 80 81 88 110 111 123 135 137 138 139 143 161 162 179 389 443 445 465 500 514 515 520 523 548 554 587 631 636 873 993 995 1080 1433 1521 1723 1883 2049 2082 2083 2086 2087 2375 2376 3000 3306 3389 3690 4369 5000 5432 5601 5672 5900 5984 6379 6443 6666 6667 7001 7002 8000 8008 8080 8081 8083 8086 8090 8200 8443 8500 8529 8600 9000 9042 9090 9092 9200 9300 9418 10000 11211 15672 27017"

mannn_hash12() {
    local input="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "$input" | sha256sum | cut -c1-12
    elif command -v shasum >/dev/null 2>&1; then
        printf '%s' "$input" | shasum -a 256 | cut -c1-12
    elif command -v md5sum >/dev/null 2>&1; then
        printf '%s' "$input" | md5sum | cut -c1-12
    else
        printf '%s' "$input" | cksum | awk '{print $1}' | cut -c1-12
    fi
}

mannn_unit_name() {
    local user="$1"
    local domain="$2"
    printf 'mannn-%s-%s' "$user" "$(mannn_hash12 "$domain")"
}

mannn_abort_if_symlink() {
    local path="$1"
    if [ -L "$path" ]; then
        echo "Refusing to use symlink path: $path" >&2
        exit 1
    fi
}

mannn_prepare_dir() {
    local path="$1"
    local owner="$2"
    local mode="$3"
    mannn_abort_if_symlink "$path"
    mkdir -p "$path"
    chown "$owner" "$path"
    chmod "$mode" "$path"
}

mannn_read_env_value() {
    local key="$1"
    local env_file="$2"
    # Always exit 0: callers run under `set -eo pipefail`, and a .env without
    # the key is a normal case handled by mannn_resolve_port's default.
    { grep -oP "^${key}=\K.*" "$env_file" 2>/dev/null || true; } | tr -d '"' | tr -d "'" | head -1
    return 0
}

mannn_port_allowed() {
    local port="$1"
    local min_port="$2"
    local max_port="$3"

    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    if [ "$port" -lt "$min_port" ] || [ "$port" -gt "$max_port" ]; then
        return 1
    fi

    case " $MANNN_BLOCKED_PORTS " in
        *" $port "*)
            return 1
            ;;
    esac

    return 0
}

mannn_resolve_port() {
    local requested_port="$1"
    local default_port="$2"
    local min_port="$3"
    local max_port="$4"

    if mannn_port_allowed "$requested_port" "$min_port" "$max_port"; then
        printf '%s' "$requested_port"
    else
        printf '%s' "$default_port"
    fi
}

# --- Port registry ---------------------------------------------------------
# Each file $MANNN_PORT_DIR/<port> contains the owning unit name
# (mannn-<user>-<domainhash>). Guarantees one port per unit, one unit per port.
# Directory is root-only (700): entries map unit names (user + domain hash) to
# ports and must not leak to unprivileged local users.

# Acquire a port for a unit. Atomic via noclobber.
# Returns 0 on success (or idempotent re-acquire by same unit),
# 1 if the port is already registered to a DIFFERENT unit.
mannn_port_acquire() {
    local port="$1"
    local unit="$2"

    mannn_abort_if_symlink "$MANNN_PORT_DIR"
    if [ ! -d "$MANNN_PORT_DIR" ]; then
        mkdir -p "$MANNN_PORT_DIR" || return 1
        chmod 700 "$MANNN_PORT_DIR" 2>/dev/null || true
    fi

    if ( set -C; echo "$unit" > "$MANNN_PORT_DIR/$port" ) 2>/dev/null; then
        chmod 600 "$MANNN_PORT_DIR/$port" 2>/dev/null || true
        return 0
    fi

    # Claim failed: file exists. Same unit is idempotent.
    if [ "$(cat "$MANNN_PORT_DIR/$port" 2>/dev/null)" = "$unit" ]; then
        return 0
    fi

    echo "mannn: port $port already in use by another unit" >&2
    return 1
}

# Drop every registry entry owned by <unit> except the given port.
# Used before AND after acquiring so concurrent applies of the same unit can
# never leave the unit holding two ports.
mannn_port_release_others() {
    local keep_port="$1"
    local unit="$2"
    local f old_unit old_port

    [ -d "$MANNN_PORT_DIR" ] || return 0

    for f in "$MANNN_PORT_DIR"/*; do
        [ -f "$f" ] || continue
        old_unit="$(cat "$f" 2>/dev/null || true)"
        [ "$old_unit" = "$unit" ] || continue
        old_port="$(basename "$f")"
        if [ "$old_port" != "$keep_port" ]; then
            mannn_unrestrict_port "$old_port" "$unit"
            rm -f "$f"
        fi
    done

    return 0
}

# Run a registry mutation while holding an exclusive lock, so concurrent
# applies (two admins, or a rebuild racing a template change) cannot
# interleave release/acquire of the same unit. Best-effort: without flock or
# a writable lock file the mutation runs unlocked, exactly like before.
mannn_registry_lock_run() {
    local fn="$1"
    shift

    if command -v flock >/dev/null 2>&1 && exec 9>>"$MANNN_PORT_DIR/.lock" 2>/dev/null; then
        local rc=0
        flock -x 9 2>/dev/null || true
        "$fn" "$@" || rc=$?
        exec 9>&- 2>/dev/null || true
        return "$rc"
    fi
    "$fn" "$@"
}

# Migrate a unit to a new port: release its previously registered port
# (registry file + firewall rules), then acquire the new one.
mannn_port_migrate() {
    local port="$1"
    local unit="$2"

    mkdir -p "$MANNN_PORT_DIR" 2>/dev/null || true
    mannn_registry_lock_run mannn_port_migrate_locked "$port" "$unit"
}

mannn_port_migrate_locked() {
    local port="$1"
    local unit="$2"
    local cport

    mannn_port_release_others "$port" "$unit"

    # Orphan cleanup: pre-registry versions (and any missed release) could
    # leave firewall rules for this unit on other ports. Comments starting
    # with "<unit>-" identify them regardless of registry state.
    for cport in $(mannn_fw_unit_ports "$unit"); do
        [ "$cport" != "$port" ] || continue
        mannn_fw_purge_port "$cport" "$unit"
    done

    if mannn_port_acquire "$port" "$unit"; then
        # Sweep again post-acquire: without the lock a concurrent apply of
        # this unit may have registered another port in between.
        mannn_port_release_others "$port" "$unit"
        # Claim secured: enforce the localhost-only firewall rule for this port.
        mannn_restrict_port "$port" "$unit" || return 1
        return 0
    fi
    return 1
}

# Release every registry entry belonging to a unit.
mannn_port_release() {
    local unit="$1"

    mannn_port_release_others "-" "$unit"
    return 0
}

# Release every registry entry (uninstall/cleanup).
mannn_port_release_all() {
    local f old_unit old_port

    [ -d "$MANNN_PORT_DIR" ] || return 0

    for f in "$MANNN_PORT_DIR"/*; do
        [ -f "$f" ] || continue
        old_unit="$(cat "$f" 2>/dev/null || true)"
        old_port="$(basename "$f")"
        mannn_unrestrict_port "$old_port" "$old_unit"
        rm -f "$f"
    done

    return 0
}

# --- Nginx proxy include writers -------------------------------------------

# Write the proxy location include for both the HTTP and SSL server blocks.
# Single source of truth for proxying behavior. Requires
# /etc/nginx/conf.d/mannn-upgrade-map.conf (installed by install.sh) for
# $connection_upgrade, and HestiaCP's 0-RTT maps ($rfc_early_data) for the
# Early-Data passthrough on the SSL side (same dependency as $anti_replay in
# the .stpl — an empty $rfc_early_data omits the header entirely).
mannn_write_proxy_confs() {
    local http_conf="$1"
    local ssl_conf="$2"
    local port="$3"

    # Static assets get the loose rate zone (a SPA page load pulls 50+ files
    # in one burst); everything else falls through to location / which
    # inherits the strict server-level zone. Same proxy directives in both
    # locations — the app still serves/gates its own assets; only the rate
    # budget differs.
    cat > "$http_conf" <<EOF
location ~* ^.+\\.(js|mjs|css|svg|svgz|png|jpe?g|gif|webp|ico|bmp|woff2?|ttf|eot|otf|map|mp4|webm)\$ {
    limit_req zone=mannn_static burst=100 nodelay;
    proxy_pass http://127.0.0.1:${port};
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Port \$server_port;
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 3600s;
    proxy_buffering off;
}

location / {
    proxy_pass http://127.0.0.1:${port};
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Port \$server_port;
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 3600s;
    proxy_buffering off;
}
EOF

    cat > "$ssl_conf" <<EOF
location ~* ^.+\\.(js|mjs|css|svg|svgz|png|jpe?g|gif|webp|ico|bmp|woff2?|ttf|eot|otf|map|mp4|webm)\$ {
    limit_req zone=mannn_static burst=100 nodelay;
    proxy_pass http://127.0.0.1:${port};
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Port \$server_port;
    proxy_set_header Early-Data \$rfc_early_data;
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 3600s;
    proxy_buffering off;
}

location / {
    proxy_pass http://127.0.0.1:${port};
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Port \$server_port;
    proxy_set_header Early-Data \$rfc_early_data;
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 3600s;
    proxy_buffering off;
}
EOF
}

# Write the "suspended" include: both files serve 503.
mannn_write_disabled_confs() {
    local http_conf="$1"
    local ssl_conf="$2"

    cat > "$http_conf" <<'EOF'
location / {
    return 503;
}
EOF

    cat > "$ssl_conf" <<'EOF'
location / {
    return 503;
}
EOF
}

# --- Firewall (iptables + ip6tables) ---------------------------------------
# App ports MUST only be reachable from localhost: nginx proxies to
# 127.0.0.1, and a direct external hit would bypass all nginx-level
# protections (rate limit, header policy, sensitive-file blocking).
# Rules are maintained on BOTH iptables (IPv4) and ip6tables (IPv6) —
# an IPv4-only rule leaves the port world-reachable over IPv6.
#
# Rule comment: "<unit>-<port>" — the unit already starts with "mannn-", so the
# tag is "mannn-<user>-<domainhash>-<port>", identical to the pre-registry
# format. That keeps migrate/unrestrict compatible with rules created by
# earlier versions of this project on upgraded servers.
# Pre-1.3.0 rules also used a "! -s 127.0.0.1/32" match instead of "! -i lo";
# every delete path removes BOTH spellings so upgraded servers get orphaned
# legacy rules (and their duplicates) cleaned up on the next re-apply.

# Print every port this unit has a tagged firewall rule for (either family).
mannn_fw_unit_ports() {
    local unit="$1" fam
    for fam in iptables ip6tables; do
        command -v "$fam" >/dev/null 2>&1 || continue
        "$fam" -S INPUT 2>/dev/null
    done | sed 's/"//g' \
        | grep -o -- "--comment ${unit}-[0-9]*" \
        | grep -o '[0-9][0-9]*$' | sort -u
}

# Delete one <family> rule for port/unit with the given match fragments.
mannn_fw_del_rule() {
    local fam="$1" port="$2" unit="$3"
    shift 3
    command -v "$fam" >/dev/null 2>&1 || return 0
    while "$fam" -D INPUT -p tcp --dport "$port" "$@" -m comment --comment "${unit}-${port}" -j DROP 2>/dev/null; do :; done
    return 0
}

# Remove every rule tagged <unit>-<port> on both families and both spellings.
mannn_fw_purge_port() {
    local port="$1"
    local unit="$2"
    local fam
    for fam in iptables ip6tables; do
        mannn_fw_del_rule "$fam" "$port" "$unit" ! -i lo
        mannn_fw_del_rule "$fam" "$port" "$unit" ! -s 127.0.0.1/32
        mannn_fw_del_rule "$fam" "$port" "$unit" ! -s ::1/128
    done
    return 0
}

# Restrict port to localhost only (idempotent).
# Usage: mannn_restrict_port <port> <unit>
mannn_restrict_port() {
    local port="$1"
    local unit="$2"
    local comment="${unit}-${port}"

    if ! command -v iptables >/dev/null 2>&1; then
        echo "mannn: WARNING: iptables not found — port $port is NOT firewalled (exposed to the network). See docs/troubleshooting.md (nftables-only servers)." >&2
        if [ "$MANNN_REQUIRE_FIREWALL" = "1" ]; then
            return 1
        fi
        return 0
    fi

    # Remove any existing rule first (idempotent), then re-insert.
    mannn_fw_purge_port "$port" "$unit"
    iptables -I INPUT 1 -p tcp --dport "$port" ! -i lo -m comment --comment "$comment" -j DROP
    if command -v ip6tables >/dev/null 2>&1; then
        ip6tables -I INPUT 1 -p tcp --dport "$port" ! -i lo -m comment --comment "$comment" -j DROP
    else
        echo "mannn: WARNING: ip6tables not found — port $port is NOT firewalled over IPv6." >&2
        if [ "$MANNN_REQUIRE_FIREWALL" = "1" ]; then
            return 1
        fi
    fi
    return 0
}

# Remove port restriction.
# Usage: mannn_unrestrict_port <port> <unit>
mannn_unrestrict_port() {
    local port="$1"
    local unit="$2"

    if ! command -v iptables >/dev/null 2>&1 && ! command -v ip6tables >/dev/null 2>&1; then
        echo "mannn: no firewall binary found, cannot remove rule for port $port" >&2
        return 0
    fi

    mannn_fw_purge_port "$port" "$unit"
    return 0
}

# Delete every INPUT rule tagged with a "mannn-" comment on one family.
mannn_fw_flush_family() {
    local fam="$1"
    local line del attempts=0

    command -v "$fam" >/dev/null 2>&1 || return 0

    while [ "$attempts" -lt 200 ]; do
        attempts=$((attempts + 1))
        # Normalize quoting first: iptables -S may or may not double-quote
        # comment strings depending on version/toolkit (legacy vs nft).
        line="$("$fam" -S INPUT 2>/dev/null | sed 's/"//g' | grep -- '--comment mannn-' | head -1 || true)"
        [ -n "$line" ] || break
        # Convert "-A INPUT ..." (or "-I INPUT n ...") to its "-D INPUT ..." form.
        del="${line#-A INPUT}"
        del="${del#-I INPUT}"
        case "$del" in
            ' '*) del="${del# }" ;;
        esac
        # Strip a leading position number from -I rules.
        [ "${del%% *}" -ge 0 ] 2>/dev/null && del="${del#* }"
        "$fam" -D INPUT $del 2>/dev/null || break
    done

    return 0
}

# Remove every INPUT rule tagged with a "mannn-" comment (uninstall).
mannn_unrestrict_all() {
    if ! command -v iptables >/dev/null 2>&1 && ! command -v ip6tables >/dev/null 2>&1; then
        echo "mannn: no firewall binary found, cannot remove rules" >&2
        return 0
    fi

    mannn_fw_flush_family iptables
    mannn_fw_flush_family ip6tables
    return 0
}
