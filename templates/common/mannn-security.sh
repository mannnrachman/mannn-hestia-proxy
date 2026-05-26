#!/bin/bash
# Shared security helpers for mannn-hestia-proxy templates.

set -u

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
    grep -oP "^${key}=\K.*" "$env_file" 2>/dev/null | tr -d '"' | tr -d "'" | head -1
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
