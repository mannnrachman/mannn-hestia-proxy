# mannn-hestia-proxy

Dynamic Nginx reverse proxy templates for **HestiaCP** — run Node.js, Go, Python, FrankenPHP, or Docker apps behind Nginx with per-domain port configuration.

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
| `mannn-nodejs-proxy` | Node.js | `private/nodejs/` | 3000 | systemd → `node server.js` |
| `mannn-go-proxy` | Go | `private/go/` | 4000 | systemd → compiled `server` binary |
| `mannn-python-proxy` | Python | `private/python/` | 8000 | systemd → `python3 app.py` |
| `mannn-frankenphpoctane-proxy` | PHP / Laravel | `private/php/` | 8080 | systemd → `frankenphp php-server` or `php artisan octane:start` |
| `mannn-docker-proxy` | Docker | `private/docker/` | 9000 | Docker container from `Dockerfile` or `docker-compose.yml` |

All templates share the same pattern:
```
nginx (port 80/443) → proxy_pass to 127.0.0.1:{PORT} → your app
```

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
rm Dockerfile                   # remove placeholder
# upload: Dockerfile OR docker-compose.yml
```
Auto-detect:
- `docker-compose.yml` exists → `docker compose up -d --build`
- `Dockerfile` exists → `docker build` + `docker run`

`.env` has two variables for Docker:
```
PORT=9000            # host port (nginx proxies here)
CONTAINER_PORT=80    # port inside the container
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
# Edit .env
echo "PORT=3001" > /home/myuser/web/myapp.example.com/private/nodejs/.env

# For Docker, also set container port
echo -e "PORT=9001\nCONTAINER_PORT=8080" > /home/myuser/web/myapp.example.com/private/docker/.env

# Re-apply template
v-change-web-domain-tpl myuser myapp.example.com mannn-nodejs-proxy
```

## Manage Service

Services auto-created with name `mannn-{domain}` (dots → dashes):

```bash
# Systemd (Node.js, Go, Python, FrankenPHP)
sudo systemctl status mannn-api-example-com
sudo systemctl restart mannn-api-example-com
sudo systemctl stop mannn-api-example-com
journalctl -u mannn-api-example-com -f

# Docker
sudo docker ps                                 # list containers
sudo docker logs mannn-api-example-com          # view logs
sudo docker restart mannn-api-example-com       # restart
sudo docker stop mannn-api-example-com          # stop
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
│       ├── .env          ← PORT=3000
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
│       ├── .env          ← PORT=4000
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
│       ├── .env          ← PORT=8000
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
│       ├── .env          ← PORT=8080
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
│       ├── .env          ← PORT=9000, CONTAINER_PORT=80
│       ├── Dockerfile    ← OR docker-compose.yml
│       └── ...           ← any files needed by container
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

**502 Bad Gateway**: App not running. Check service: `systemctl status mannn-{domain}` or `docker ps`

**203/EXEC**: Binary not found. Ensure runtime installed system-wide.

**Connection refused**: Port mismatch. Re-apply template.

**Template not in panel**: `sudo ./install.sh` then refresh.

**Permission denied**: Re-apply template to auto-fix: `v-change-web-domain-tpl user domain template`

**Docker build fails**: Check Dockerfile syntax: `docker build -t test /home/user/web/domain/private/docker/`

## File Reference

```
mannn-hestia-proxy/
├── install.sh              ← install templates to HestiaCP
├── uninstall.sh            ← remove templates from HestiaCP
├── README.md
├── docs/
│   ├── prerequisites.md    ← server setup, all runtime installations
│   ├── architecture.md     ← how templates work internally
│   ├── deployment.md       ← full workflow per template, migration, uninstall
│   └── troubleshooting.md  ← common issues and fixes per template
└── templates/
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
| Systemd service | `mannn-{domain}` | `mannn-api-example-com` |
| Docker container | `mannn-{domain}` | `mannn-api-example-com` |
| App directory | `private/{runtime}/` | `private/nodejs/` |

To use a different prefix, find-and-replace `mannn` across all files before running `install.sh`.

## License

MIT
