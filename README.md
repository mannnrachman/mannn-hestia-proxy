# mannn-hestia-proxy

Dynamic Nginx reverse proxy templates for **HestiaCP** — run Node.js, Go, Python, FrankenPHP, or Docker / Compose backends behind Nginx with per-domain port configuration.

## Why This Project?

[HestiaCP](https://hestiacp.com/) is a lightweight, open-source web hosting control panel designed for managing websites, DNS, mail, and databases on Linux servers. It provides a clean web UI and powerful CLI tools for server administration. HestiaCP is actively maintained on [GitHub](https://github.com/hestiacp/hestiacp) and supports nginx + PHP-FPM as its primary web stack.

**The problem:** HestiaCP is built around PHP-FPM — it natively serves PHP files from `public_html/` with no built-in support for running Node.js, Go, Python, or other backend runtimes. If you want to host a Go API, a Node.js app, or a Python service alongside your PHP sites, you're on your own — manual systemd services, hand-written nginx proxy configs, port management, and no integration with HestiaCP's domain/user model.

**mannn-hestia-proxy fills that gap.** It provides drop-in Nginx proxy templates that integrate with HestiaCP's template system, so you can:

- Apply a proxy template to any domain from the HestiaCP panel (or CLI)
- Automatically create systemd services, nginx proxy configs, and firewall rules
- Run multiple backends (Node.js, Go, Python, FrankenPHP, Docker) on the same server, each under its own domain and user
- Manage everything through HestiaCP's existing domain model — no extra control panel needed

> **TL;DR:** HestiaCP = great for PHP. This project = makes HestiaCP great for everything else too.

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
| `mannn-frankenphpoctane-proxy` | PHP / Laravel | `private/php/` | 7100 | systemd → `frankenphp php-server` or `php artisan octane:start` |
| `mannn-docker-proxy` | Docker / Compose | `private/docker/` | 9100 | Advanced mode: nginx proxy only to an existing localhost backend |

All templates share the same pattern:
```
nginx (port 80/443) → proxy_pass to 127.0.0.1:{PORT} → your app
```

Security hardening in this version:
- each runtime only accepts a dedicated localhost port range
- blocked internal/control-panel ports automatically fall back to a safe default
- systemd service names use a collision-safe hash
- Docker backends stay external to the template
- Docker mode is proxy-only for CI/CD, Compose, and admin-managed stacks
- **nginx security headers** (`X-Frame-Options`, `X-Content-Type-Options`, `X-XSS-Protection`, `Referrer-Policy`, `Content-Security-Policy`, `Permissions-Policy`, `Strict-Transport-Security` on SSL)
- **`proxy_hide_header X-Powered-By`** prevents backend technology disclosure
- **`server_tokens off`** hides nginx version from response headers
- **sensitive file blocking** — `.bak`, `.sql`, `.zip`, `.log`, etc. return 404 at nginx level
- **config path blocking** — `wp-config.php`, `config.php`, `settings.php`, etc. return 404 at nginx level
- **rate limiting** — 10 req/s per IP (burst 20) via `mannn-rate-limit.conf`
- **`client_max_body_size 10m`** — explicit upload size limit
- **`/private/` path blocked** in nginx (returns 404)
- **iptables firewall** auto-restricts app ports to localhost only (`! -i lo`)
- **systemd sandbox** (`ProtectSystem=strict`, `ProtectHome=read-only`, `NoNewPrivileges`, `PrivateTmp`)

## Runtime Installation Model

Runtimes are installed **once per server**, not once per user.

- Node.js binary → one system-wide install
- Go toolchain → one system-wide install
- Python binary → one system-wide install
- FrankenPHP binary → one system-wide install
- Docker daemon → one system-wide install

Per user/domain, you only store app code and local dependencies under `private/{runtime}/`.

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
| 5 | Creates and starts service with systemd sandbox (runtimes only) |
| 6 | Adds iptables rule to restrict app port to localhost only |
| 7 | Domain is live immediately |

**Nothing manual** besides uploading your app code.

## Step-by-Step Guide

### Step 1: Server Setup (one-time)

Install HestiaCP with nginx-only + your runtimes. See [docs/prerequisites.md](docs/prerequisites.md) for full guide.

### Step 2: Install Templates (one-time)

```bash
sudo ./install.sh        # Install
sudo ./uninstall.sh      # Remove
```

### Update Templates

Already installed an older version? Update to the latest:

```bash
cd ~/mannn-hestia-proxy
git pull
sudo ./install.sh all
```

Then rebuild domains using these templates so the new config takes effect:

```bash
sudo /usr/local/hestia/bin/v-rebuild-web-domains admin
```

> **Safe:** The install script only overwrites nginx template files on the system.
> It does **not** delete your `.env`, application code, or data.

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

# Docker / Compose
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

#### Docker / Compose (`private/docker/`)
```bash
cd /home/myuser/web/myapp.example.com/private/docker/
cat > .env <<EOF
BACKEND_PORT=9100
EOF
```

This mode does **not** run Docker for you.

Use it when:
- CI/CD deploys your container separately
- you use `docker compose up -d` outside the template
- one domain needs a backend already listening on `127.0.0.1:BACKEND_PORT`

Flow:
```
nginx domain -> 127.0.0.1:BACKEND_PORT
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

# Docker / Compose: choose the localhost backend port
cat > /home/myuser/web/myapp.example.com/private/docker/.env <<EOF
BACKEND_PORT=9101
EOF

# Re-apply template
v-change-web-domain-tpl myuser myapp.example.com mannn-docker-proxy
```

## Manage Service

Services and containers now use a **collision-safe generated name** based on `user + hash(domain)`. Example pattern:

```
mannn-myuser-a1b2c3d4e5f6
```

To discover the exact name on a server later, list matching units or containers:

```bash
# Systemd (Node.js, Go, Python, FrankenPHP)
systemctl list-units --type=service | grep mannn-
ls /etc/systemd/system/mannn-*.service

# Docker / Compose backends are managed separately
docker ps -a
docker compose ps
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
│       ├── .env          ← PORT=7100
│       ├── index.php     ← plain PHP entry
│       └── artisan       ← if present → Laravel Octane mode
├── document_errors/
└── stats/
```

### Docker / Compose
```
/home/$USER/web/$DOMAIN/
├── public_html/          ← not used
├── private/
│   └── docker/           ← backend proxy config only
│       └── .env          ← BACKEND_PORT=9100
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
| Systemd service | `root:root` | `644` | Includes sandbox hardening |
| iptables rule | auto | auto | Port restricted to localhost (`! -i lo`) |
| Docker backend/container | external | external | Managed outside the template |

## Documentation

| Document | Content |
|----------|---------|
| [docs/prerequisites.md](docs/prerequisites.md) | Server setup, nginx-only mode, all runtime installations |
| [docs/architecture.md](docs/architecture.md) | Template internals, file locations, proxy headers |
| [docs/deployment.md](docs/deployment.md) | Full workflows, migration, uninstall, multiple apps |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Error codes, common issues, fixes |

## Troubleshooting

**502 Bad Gateway**: Backend not running. Verify your Docker / Compose app is listening on `127.0.0.1:BACKEND_PORT`.

**203/EXEC**: Binary not found. Ensure runtime installed system-wide.

**Connection refused**: Port mismatch. Re-apply template.

**Template not in panel**: `sudo ./install.sh` then refresh.

**Permission denied**: Re-apply template to auto-fix: `v-change-web-domain-tpl user domain template`

**Docker backend fails to start**: verify your app/container is running and `BACKEND_PORT=` in `.env` matches the localhost port, then re-apply the template if needed.

## File Reference

```
mannn-hestia-proxy/
├── install.sh              ← install templates to HestiaCP
├── uninstall.sh            ← remove templates from HestiaCP
├── setup-backup-exclusions.sh ← exclude heavy dirs from backups
├── README.md
├── CHANGELOG.md
├── CONTRIBUTING.md
├── LICENSE
├── docs/
│   ├── prerequisites.md    ← server setup, all runtime installations
│   ├── architecture.md     ← how templates work internally
│   ├── deployment.md       ← full workflow per template, migration, uninstall
│   └── troubleshooting.md  ← common issues and fixes per template
└── templates/
    ├── common/
    │   ├── mannn-security.sh
    │   └── mannn-rate-limit.conf
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
| Docker backend/container | external | e.g. your own Compose service name |
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

What stays in backup: source code, `.env`, `package.json`, `requirements.txt`, `go.mod`, and other small app configuration files. In proxy-only Docker mode, the Hestia directory usually only needs `.env`; your real Docker files can live in a separate deployment directory managed by CI/CD or admin operations.

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

[MIT](LICENSE) — free to use, modify, and distribute.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on bug reports, feature requests, and pull requests.


## Security Notes

Docker mode is proxy-only. The template never runs `docker build`, `docker pull`, `docker run`, or `docker compose`. It only stores `BACKEND_PORT` and proxies nginx to `127.0.0.1:BACKEND_PORT`.

This is safer for CI/CD and advanced Docker stacks because deployment stays outside the Hestia template.

Per-runtime localhost port windows:

- Node.js: `3100-3999`
- Go: `4100-4999`
- Python: `8100-8999`
- FrankenPHP: `7100-7999`
- Docker: `9100-9999`

If an invalid or blocked port is requested, the template falls back to its safe default port.

### Built-in Security Layers

| Layer | Protection |
|-------|-----------|
| **iptables firewall** | App ports auto-restricted to localhost only (`! -i lo` DROP rule). External access blocked. |
| **nginx security headers** | `X-Frame-Options: SAMEORIGIN`, `X-Content-Type-Options: nosniff`, `X-XSS-Protection: 1; mode=block`, `Referrer-Policy: strict-origin-when-cross-origin`, `Content-Security-Policy`, `Permissions-Policy` |
| **nginx SSL headers** | `Strict-Transport-Security: max-age=63072000; includeSubDomains; preload` (SSL templates only) |
| **nginx header hiding** | `proxy_hide_header X-Powered-By` — prevents backend technology fingerprinting |
| **nginx path protection** | `/private/` returns 404, dotfiles (`.env`, `.git`) blocked, sensitive extensions (`.bak`, `.sql`, `.zip`, `.log`, etc.) blocked, config paths (`wp-config.php`, `config.php`, etc.) blocked |
| **nginx rate limiting** | 10 req/s per IP (burst 20) via `limit_req_zone` — mitigates brute-force and automated scanning |
| **nginx version hiding** | `server_tokens off` — prevents nginx version disclosure |
| **upload size limit** | `client_max_body_size 10m` — explicit body size limit |
| **systemd sandbox** | `ProtectSystem=strict`, `ProtectHome=read-only`, `NoNewPrivileges=true`, `PrivateTmp=true`, `ReadWritePaths` limited to app directory |
| **symlink protection** | `mannn_abort_if_symlink()` prevents symlink attacks on config files |
| **port validation** | `MANNN_BLOCKED_PORTS` blocks sensitive system ports, per-runtime range enforcement |
| **user isolation** | Each app runs as its own system user, no shared privileges |
