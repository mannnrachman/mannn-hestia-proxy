# mannn-hestia-proxy

Dynamic Nginx reverse proxy templates for **HestiaCP** — run Node.js, Go, Python, FrankenPHP, or safer prebuilt Docker images behind Nginx with per-domain port configuration.

## Overview

| Before (PHP-FPM) | After (mannn-hestia-proxy) |
|---|---|
| Files in `public_html/` | Files in `private/{runtime}/` |
| Nginx serves files directly | Nginx proxies to backend app |
| No process management | Service auto-created |
| Static template per port | Dynamic — one template, port from `.env` |

## Templates

| Template | Runtime | Directory | Default Port | What Runs |
|----------|---------|-----------|-------------|-----------|
| `mannn-nodejs-proxy` | Node.js | `private/nodejs/` | 3100 | systemd → `node server.js` |
| `mannn-go-proxy` | Go | `private/go/` | 4100 | systemd → compiled `server` binary |
| `mannn-python-proxy` | Python | `private/python/` | 8100 | systemd → `python3 app.py` |
| `mannn-frankenphpoctane-proxy` | PHP / Laravel | `private/php/` | 8180 | systemd → `frankenphp php-server` or `php artisan octane:start` |
| `mannn-docker-proxy` | Docker | `private/docker/` | 9100 | Restricted container from prebuilt `IMAGE=` only |

All templates share the same pattern:
```
nginx (port 80/443) → proxy_pass to 127.0.0.1:{PORT} → your app
```

Security hardening in this version:
- each runtime only accepts a dedicated localhost port range
- blocked internal/control-panel ports automatically fall back to a safe default
- service/container names use a collision-safe hash
- Docker no longer builds or runs `docker-compose.yml` from user-writable files

## Quick Start (3 steps)

```bash
# Step 1: Install templates
sudo ./install.sh

# Step 2: Create domain in HestiaCP
v-add-web-domain myuser myapp.example.com

# Step 3: Apply template — everything auto-created
v-change-web-domain-tpl myuser myapp.example.com mannn-nodejs-proxy

# Done. Domain is live with placeholder.
curl http://myapp.example.com
```

## What Gets Auto-Created

When you apply ANY template, the `.sh` script handles:

| Step | What Happens |
|------|-------------|
| 1 | Creates app directory with correct permissions (`755`, `$user:$user`) |
| 2 | Creates `.env` with default PORT (`600`, `$user:$user`) |
| 3 | Creates placeholder app (only if no app files exist) |
| 4 | Generates nginx proxy config (`root:$user 640`) |
| 5 | Creates and starts service (systemd for runtimes, Docker for containers) |
| 6 | Domain is live immediately |

**Nothing manual** besides uploading your app code.

## Step-by-Step Guide

### Step 1: Server Setup (one-time)

Install HestiaCP with nginx-only + your runtimes. See [docs/prerequisites.md](docs/prerequisites.md) for full guide.

### Step 2: Install Templates (one-time)

```bash
sudo ./install.sh        # Install
sudo ./uninstall.sh      # Remove
```

### Step 3: Create Domain

```bash
v-add-web-domain myuser myapp.example.com
```

### Step 4: Apply Template

```bash
# Node.js
v-change-web-domain-tpl myuser myapp.example.com mannn-nodejs-proxy

# Go
v-change-web-domain-tpl myuser myapp.example.com mannn-go-proxy

# Python
v-change-web-domain-tpl myuser myapp.example.com mannn-python-proxy

# PHP / FrankenPHP / Laravel Octane
v-change-web-domain-tpl myuser myapp.example.com mannn-frankenphpoctane-proxy

# Docker
v-change-web-domain-tpl myuser myapp.example.com mannn-docker-proxy
```

### Step 5: Upload Your App Code

Each template has its own directory and entry point:

#### Node.js (`private/nodejs/`)
```bash
cd /home/myuser/web/myapp.example.com/private/nodejs/
rm server.js                    # remove placeholder
# upload: server.js, package.json, etc.
npm install
```
Entry points detected: `server.js` → `index.js` → `app.js`

#### Go (`private/go/`)
```bash
cd /home/myuser/web/myapp.example.com/private/go/
rm main.go server               # remove placeholder + binary
# upload: main.go, go.mod
# binary auto-compiles on re-apply
```
Entry point: compiled `server` binary from `main.go`

#### Python (`private/python/`)
```bash
cd /home/myuser/web/myapp.example.com/private/python/
rm app.py                       # remove placeholder
# upload: app.py, requirements.txt
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
deactivate
```
Entry points detected: `app.py` → `server.py` → `main.py` → `wsgi.py`
Venv auto-detected if `venv/bin/python3` exists.

#### FrankenPHP / Laravel Octane (`private/php/`)
```bash
cd /home/myuser/web/myapp.example.com/private/php/
rm index.php                    # remove placeholder
# upload: your PHP files
```
Auto-detect:
- `artisan` exists → Laravel project → `php artisan octane:start --server=frankenphp`
- `public/index.php` exists → `frankenphp php-server --root public/`
- Otherwise → `frankenphp php-server --root ./`

#### Docker (`private/docker/`)
```bash
cd /home/myuser/web/myapp.example.com/private/docker/
# hardened mode: do not place Dockerfile or compose files here
# only edit .env and point IMAGE to a prebuilt image
```
Docker hardening:
- `Dockerfile`, `docker-compose.yml`, `compose.yaml`, and `compose.yml` are refused by the hardened template
- set a prebuilt image name in `.env` and the template will `docker pull` + run it with restricted flags

`.env` has three variables for Docker:
```
PORT=9100                # host port (nginx proxies here)
CONTAINER_PORT=8080      # port inside the container
IMAGE=nginx:alpine       # prebuilt image only
```

### Step 6: Re-apply Template (restarts with your code)

```bash
v-change-web-domain-tpl myuser myapp.example.com mannn-nodejs-proxy
```

This regenerates proxy config, rebuilds/restarts the service with your code.

### Step 7: Verify

```bash
curl http://myapp.example.com
```

## Change Port

```bash
# Node.js: choose a port inside the allowed Node.js range (3100-3999)
echo "PORT=3101" > /home/myuser/web/myapp.example.com/private/nodejs/.env

# Docker: choose a port inside the allowed Docker range (9100-9999)
cat > /home/myuser/web/myapp.example.com/private/docker/.env <<EOF
PORT=9101
CONTAINER_PORT=8080
IMAGE=nginx:alpine
EOF

# Re-apply template
v-change-web-domain-tpl myuser myapp.example.com mannn-nodejs-proxy
```

## Manage Service

Services and containers now use a **collision-safe generated name** based on `user + hash(domain)`. Example pattern:

```
mannn-myuser-a1b2c3d4e5f6
```

To discover the exact name on a server later, list matching units or containers:

```bash
# Systemd (Node.js, Go, Python, FrankenPHP, Docker unit)
systemctl list-units --type=service | grep mannn-
ls /etc/systemd/system/mannn-*.service

# Docker containers
docker ps -a --format '{{.Names}}' | grep '^mannn-'
```

## Directory Structure

### PHP-FPM (default HestiaCP — for comparison)
```
/home/$USER/web/$DOMAIN/
├── public_html/          ← served by nginx directly
│   └── index.php
├── private/
├── document_errors/
└── stats/
```

### Node.js
```
/home/$USER/web/$DOMAIN/
├── public_html/          ← not used
├── private/
│   └── nodejs/           ← app code here
│       ├── .env          ← PORT=3100
│       ├── server.js     ← entry point
│       ├── package.json
│       └── node_modules/
├── document_errors/
└── stats/
```

### Go
```
/home/$USER/web/$DOMAIN/
├── public_html/          ← not used
├── private/
│   └── go/               ← app code here
│       ├── .env          ← PORT=4100
│       ├── main.go       ← source code
│       ├── go.mod
│       └── server        ← auto-compiled binary
├── document_errors/
└── stats/
```

### Python
```
/home/$USER/web/$DOMAIN/
├── public_html/          ← not used
├── private/
│   └── python/           ← app code here
│       ├── .env          ← PORT=8100
│       ├── app.py        ← entry point
│       ├── requirements.txt
│       └── venv/         ← optional (auto-detected)
├── document_errors/
└── stats/
```

### FrankenPHP / Laravel Octane
```
/home/$USER/web/$DOMAIN/
├── public_html/          ← not used
├── private/
│   └── php/              ← app code here
│       ├── .env          ← PORT=8180
│       ├── index.php     ← plain PHP entry
│       └── artisan       ← if present → Laravel Octane mode
├── document_errors/
└── stats/
```

### Docker
```
/home/$USER/web/$DOMAIN/
├── public_html/          ← not used
├── private/
│   └── docker/           ← app code here
│       ├── .env          ← PORT=9100, CONTAINER_PORT=8080, IMAGE=nginx:alpine
│       └── no build files ← Dockerfile / compose files are intentionally rejected
├── document_errors/
└── stats/
```

## Permissions

All permissions match HestiaCP standard:

| Path | Owner | Mode | Note |
|------|-------|------|------|
| `private/{runtime}/` | `user:user` | `755` | Same as `public_html/` |
| `.env` | `user:user` | `600` | User private, others blocked |
| Source files | `user:user` | `644` | Standard |
| `nginx.proxy.conf` | `root:user` | `640` | Same as HestiaCP `nginx.conf` |
| Systemd service | `root:root` | `644` | Standard |
| Docker container | — | — | Runs in Docker's own namespace |

## Documentation

| Document | Content |
|----------|---------|
| [docs/prerequisites.md](docs/prerequisites.md) | Server setup, nginx-only mode, all runtime installations |
| [docs/architecture.md](docs/architecture.md) | Template internals, file locations, proxy headers |
| [docs/deployment.md](docs/deployment.md) | Full workflows, migration, uninstall, multiple apps |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Error codes, common issues, fixes |

## Troubleshooting

**502 Bad Gateway**: App not running. Check the generated `mannn-*` service with `systemctl list-units --type=service | grep mannn-` or inspect containers with `docker ps -a`.

**203/EXEC**: Binary not found. Ensure runtime installed system-wide.

**Connection refused**: Port mismatch. Re-apply template.

**Template not in panel**: `sudo ./install.sh` then refresh.

**Permission denied**: Re-apply template to auto-fix: `v-change-web-domain-tpl user domain template`

**Docker image fails to start**: verify `IMAGE=` and `CONTAINER_PORT=` in `.env`, then re-apply the template.

## File Reference

```
mannn-hestia-proxy/
├── install.sh              ← install templates to HestiaCP
├── uninstall.sh            ← remove templates from HestiaCP
├── setup-backup-exclusions.sh ← exclude heavy dirs from backups
├── README.md
├── docs/
│   ├── prerequisites.md    ← server setup, all runtime installations
│   ├── architecture.md     ← how templates work internally
│   ├── deployment.md       ← full workflow per template, migration, uninstall
│   └── troubleshooting.md  ← common issues and fixes per template
└── templates/
    ├── common/
    │   └── mannn-security.sh
    ├── nodejs/
    │   ├── mannn-nodejs-proxy.tpl
    │   ├── mannn-nodejs-proxy.stpl
    │   └── mannn-nodejs-proxy.sh
    ├── goproxy/
    │   ├── mannn-go-proxy.tpl
    │   ├── mannn-go-proxy.stpl
    │   └── mannn-go-proxy.sh
    ├── pypyroxy/
    │   ├── mannn-python-proxy.tpl
    │   ├── mannn-python-proxy.stpl
    │   └── mannn-python-proxy.sh
    ├── frankenphp/
    │   ├── mannn-frankenphpoctane-proxy.tpl
    │   ├── mannn-frankenphpoctane-proxy.stpl
    │   └── mannn-frankenphpoctane-proxy.sh
    └── docker/
        ├── mannn-docker-proxy.tpl
        ├── mannn-docker-proxy.stpl
        └── mannn-docker-proxy.sh
```

## Naming Convention

| Layer | Pattern | Example |
|-------|---------|---------|
| Template files | `mannn-{runtime}-proxy.{tpl,stpl,sh}` | `mannn-nodejs-proxy.sh` |
| Template name in HestiaCP | `mannn-{runtime}-proxy` | `mannn-go-proxy` |
| Systemd service | `mannn-{user}-{hash(domain)}` | `mannn-myuser-a1b2c3d4e5f6` |
| Docker container | `mannn-{user}-{hash(domain)}` | `mannn-myuser-a1b2c3d4e5f6` |
| App directory | `private/{runtime}/` | `private/nodejs/` |

To use a different prefix, find-and-replace `mannn` across all files before running `install.sh`.

## Backup & Restore

### Setup Backup Exclusions

By default, HestiaCP backs up the entire domain directory — including `node_modules/`, `venv/`, `vendor/`, and compiled binaries. These can bloat backups to hundreds of MB.

Run after installing templates:

```bash
# Single user — apply exclusions
sudo ./setup-backup-exclusions.sh myuser

# All users
for u in $(v-list-users plain | cut -f1); do sudo ./setup-backup-exclusions.sh $u; done

# Revert to previous config (if needed)
sudo ./setup-backup-exclusions.sh myuser --revert
```

Script auto-backs up existing `backup-excludes.conf` before modifying. Use `--revert` to restore.

What gets excluded (rebuilt on restore):

| Path | Why | Restore command |
|------|-----|-----------------|
| `private/nodejs/node_modules` | Large, reinstallable | `npm install` |
| `private/go/server` | Binary, recompilable | `go build -o server .` |
| `private/python/venv` | Large, recreatable | `python3 -m venv venv && pip install -r requirements.txt` |
| `private/php/vendor` | Large, reinstallable | `composer install` |
| `private/php/node_modules` | Large, reinstallable | `npm install` |

What stays in backup: source code, `.env`, `package.json`, `requirements.txt`, `go.mod`, and other small app configuration files. In hardened Docker mode, build/compose files are intentionally not used.

Uses HestiaCP's native `v-update-user-backup-exclusions` with `*` wildcard — safe because non-proxy domains don't have these paths.

### Restore Flow

```bash
# 1. Restore backup (HestiaCP panel or CLI)
v-restore-user myuser /backup/myuser.2026-01-15.tar

# 2. Re-apply template (auto-rebuilds everything)
v-change-web-domain-tpl myuser myapp.example.com mannn-nodejs-proxy

# 3. For Node.js — reinstall dependencies
cd /home/myuser/web/myapp.example.com/private/nodejs/
npm install

# For Python — recreate venv
cd /home/myuser/web/myapp.example.com/private/python/
python3 -m venv venv
source venv/bin/activate && pip install -r requirements.txt && deactivate

# For Go — recompile
cd /home/myuser/web/myapp.example.com/private/go/
go build -o server .

# For PHP/Laravel — reinstall dependencies
cd /home/myuser/web/myapp.example.com/private/php/
composer install

# 4. Re-apply template again to restart service with rebuilt deps
v-change-web-domain-tpl myuser myapp.example.com mannn-nodejs-proxy
```

## License

MIT


## Security Notes

This hardened release intentionally removes the old Docker build/compose workflow because it allowed root to execute build instructions from user-writable files. The new Docker template supports **prebuilt images only** via `IMAGE=` in `.env`.

Per-runtime localhost port windows:

- Node.js: `3100-3999`
- Go: `4100-4999`
- Python: `8100-8999`
- FrankenPHP: `8180-8999`
- Docker: `9100-9999`

If an invalid or blocked port is requested, the template falls back to its safe default port.
