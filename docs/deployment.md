# Deployment Guide

Complete guide to deploying apps with mannn-hestia-proxy.

## Quick Start

```bash
# 1. Install templates
sudo ./install.sh

# 2. Create domain
v-add-web-domain myuser myapp.example.com

# 3. Apply template
v-change-web-domain-tpl myuser myapp.example.com mannn-nodejs-proxy

# Done. Domain is live at http://myapp.example.com with placeholder response.
```

## Full Workflow: Node.js App

### Step 1: Create user and domain

```bash
# Create HestiaCP user
v-add-user devuser 'StrongPass123!' 'devuser@example.com'

# Create domain
v-add-web-domain devuser myapi.example.com

# (Optional) Add SSL
v-add-letsencrypt-domain devuser myapi.example.com
```

### Step 2: Apply template

```bash
v-change-web-domain-tpl devuser myapi.example.com mannn-nodejs-proxy
```

This auto-creates:
- `/home/devuser/web/myapi.example.com/private/nodejs/` directory
- `.env` with `PORT=3100`
- Placeholder `server.js`
- Collision-safe systemd service `mannn-devuser-<hash>`
- Nginx proxy config

Verify:
```bash
curl http://myapi.example.com
# {"status":"ok","message":"Node.js app running","domain":"myapi.example.com"}
```

### Step 3: Deploy your app

```bash
# SSH or SFTP as devuser
cd /home/devuser/web/myapi.example.com/private/nodejs/

# Remove placeholder, upload your code
rm server.js
# Upload: server.js, package.json, etc.

# Install dependencies
npm install

# Re-apply template to restart with your code
v-change-web-domain-tpl devuser myapi.example.com mannn-nodejs-proxy
```

### Step 4: Custom port (optional)

```bash
echo "PORT=3105" > /home/devuser/web/myapi.example.com/private/nodejs/.env
v-change-web-domain-tpl devuser myapi.example.com mannn-nodejs-proxy
```

## Full Workflow: Go App

```bash
# Create domain and apply template
v-add-web-domain devuser goapi.example.com
v-change-web-domain-tpl devuser goapi.example.com mannn-go-proxy

# Upload your Go code
cd /home/devuser/web/goapi.example.com/private/go/
rm main.go  # remove placeholder
# Upload your main.go and other .go files

# Remove old binary so template rebuilds it
rm -f server

# Re-apply to auto-compile and restart
v-change-web-domain-tpl devuser goapi.example.com mannn-go-proxy
```

The template auto-runs `go build -o server .` when re-applied.

If you prefer to compile manually:
```bash
cd /home/devuser/web/goapi.example.com/private/go/
go build -o server .
# Then restart service
systemctl list-units --type=service | grep mannn-
# then restart the generated mannn-* unit for this domain
```

## Full Workflow: Python App

```bash
# Create domain and apply template
v-add-web-domain devuser pyapi.example.com
v-change-web-domain-tpl devuser pyapi.example.com mannn-python-proxy

# Upload your Python code
cd /home/devuser/web/pyapi.example.com/private/python/
rm app.py  # remove placeholder
# Upload: app.py, requirements.txt, etc.

# Create virtual environment (recommended)
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
deactivate

# Re-apply template (auto-detects venv python)
v-change-web-domain-tpl devuser pyapi.example.com mannn-python-proxy
```

The template auto-detects `venv/bin/python3` if a virtual environment exists.

## Full Workflow: FrankenPHP / Laravel Octane

```bash
# Create domain and apply template
v-add-web-domain devuser phpapp.example.com
v-change-web-domain-tpl devuser phpapp.example.com mannn-frankenphpoctane-proxy

# Upload your PHP code
cd /home/devuser/web/phpapp.example.com/private/php/
rm index.php  # remove placeholder
# Upload: index.php, or Laravel project files
```

Auto-detection:
- `artisan` file exists → Laravel project → runs `php artisan octane:start --server=frankenphp`
- `public/index.php` exists → runs `frankenphp php-server --root public/`
- Otherwise → runs `frankenphp php-server --root ./`

For Laravel Octane, install inside your project:
```bash
cd /home/devuser/web/phpapp.example.com/private/php/
composer require laravel/octane
php artisan octane:install --server=frankenphp
```

## Full Workflow: Docker App

```bash
# Create domain and apply template
v-add-web-domain devuser dockerapp.example.com
v-change-web-domain-tpl devuser dockerapp.example.com mannn-docker-proxy

# Hardened mode: use a prebuilt image only
cd /home/devuser/web/dockerapp.example.com/private/docker/
cat > .env <<EOF
PORT=9100
CONTAINER_PORT=8080
IMAGE=nginx:alpine
EOF
```

Docker hardening:
- `Dockerfile`, `docker-compose.yml`, `compose.yaml`, and `compose.yml` are rejected
- the template only runs `docker pull` + `docker run` for `IMAGE=` from `.env`
- service/container names are collision-safe and generated as `mannn-{user}-{hash(domain)}`

Manage containers:
```bash
docker ps -a --format '{{.Names}}' | grep '^mannn-'
# then use the generated container name for logs/restart/stop
```

## Managing Services

```bash
# Check status
systemctl list-units --type=service | grep mannn-
# then inspect the generated unit for this domain

# View logs
journalctl -u mannn-<generated-name> -f

# Restart manually
systemctl restart mannn-<generated-name>

# Stop
systemctl stop mannn-<generated-name>

# Start
systemctl start mannn-<generated-name>
```

## Migrating from PHP Template

If a domain currently uses a PHP template and you want to switch to a proxy:

```bash
# 1. Apply proxy template (replaces PHP template)
v-change-web-domain-tpl devuser myapp.example.com mannn-nodejs-proxy

# 2. Old public_html/ files are preserved but no longer served
# 3. App code goes in private/nodejs/ instead
# 4. Nginx now proxies all requests to the backend app
```

## Changing Templates

To switch a domain from one runtime to another:

```bash
# Stop old service first
systemctl list-units --type=service | grep mannn-
# stop/disable the generated unit for the old runtime before switching templates

# Apply new template
v-change-web-domain-tpl devuser myapp.example.com mannn-go-proxy

# Old app directory (private/nodejs/) is preserved
# New app directory (private/go/) is created
# New systemd service is created and started
```

## Uninstall

Remove templates from HestiaCP:

```bash
# Remove template files
rm /usr/local/hestia/data/templates/web/nginx/php-fpm/mannn-nodejs-proxy.*
rm /usr/local/hestia/data/templates/web/nginx/php-fpm/mannn-go-proxy.*
rm /usr/local/hestia/data/templates/web/nginx/php-fpm/mannn-python-proxy.*

# Switch domains back to a PHP template before removing
v-change-web-domain-tpl devuser myapp.example.com default

# Stop and remove systemd services
systemctl list-units --type=service | grep mannn-
# stop/disable the generated unit for the old runtime before switching templates
rm /etc/systemd/system/mannn-myapp-example-com.service
systemctl daemon-reload
```

## Multiple Apps Per Server

Each app gets its own domain, port, and systemd service:

```bash
# App 1: Node.js
v-add-web-domain devuser app1.example.com
v-change-web-domain-tpl devuser app1.example.com mannn-nodejs-proxy
# → port 3000, service: mannn-app1-example-com

# App 2: Go
v-add-web-domain devuser app2.example.com
v-change-web-domain-tpl devuser app2.example.com mannn-go-proxy
# → port 4000, service: mannn-app2-example-com

# App 3: Python (different user)
v-add-web-domain team2 app3.example.com
v-change-web-domain-tpl team2 app3.example.com mannn-python-proxy
# → port 8000, service: mannn-app3-example-com
```

All apps run independently. Changing one does not affect others.
