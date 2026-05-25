# Troubleshooting

Common issues and fixes.

## 502 Bad Gateway

**Cause**: Backend app not running or wrong port.

```bash
# Check if service is running
systemctl status mannn-{domain}

# Check app logs
journalctl -u mannn-{domain} -n 50 --no-pager

# Verify port matches
cat /home/{user}/web/{domain}/private/{runtime}/.env
# Compare with what the app actually listens on

# Restart service
systemctl restart mannn-{domain}
```

## 203/EXEC Error (systemd)

**Cause**: Binary not found or user cannot execute it.

Common for Node.js:
```bash
# Check which node binary the service uses
grep ExecStart /etc/systemd/system/mannn-{domain}.service

# Verify the binary exists and is executable
ls -la /usr/local/node/bin/node
ls -la /usr/local/bin/node

# If /usr/local/bin/node is a symlink to NVM, other users can't follow it
# Fix: install Node.js system-wide
ls -la /usr/local/bin/node
# If it points to /home/user/.nvm/..., replace it:
ln -sf /usr/local/node/bin/node /usr/local/bin/node
```

Common for Go:
```bash
# Binary not compiled yet
cd /home/{user}/web/{domain}/private/go/
go build -o server .
# Then re-apply template or restart service
```

## CHDIR Error (systemd)

**Cause**: Service user cannot access the WorkingDirectory.

```bash
# Check user's shell
getent passwd {user}
# If shell is /usr/sbin/nologin, the user can't chdir

# Option A: Give user a login shell
chsh -s /bin/bash {user}

# Option B: Change service user manually
# Edit /etc/systemd/system/mannn-{domain}.service
# Change User={user} to a user that can access the directory
# Then: systemctl daemon-reload && systemctl restart mannn-{domain}
```

## Connection Refused

**Cause**: App listening on different port than `.env` says.

```bash
# Check what port the app is actually using
ss -tlnp | grep node
ss -tlnp | grep python
ss -tlnp | grep server

# Check .env
cat /home/{user}/web/{domain}/private/{runtime}/.env

# Fix: align .env with actual port, then re-apply template
echo "PORT=CORRECT_PORT" > /home/{user}/web/{domain}/private/{runtime}/.env
v-change-web-domain-tpl {user} {domain} mannn-proxy-{runtime}
```

## Port Already in Use

**Cause**: Another process using the same port.

```bash
# Find what's using the port
ss -tlnp | grep :3000

# Option A: Change .env to use a different port
echo "PORT=3005" > /home/{user}/web/{domain}/private/nodejs/.env
v-change-web-domain-tpl {user} {domain} mannn-nodejs-proxy

# Option B: Stop the conflicting service
systemctl stop mannn-other-domain
```

## Template Not Appearing in Panel

**Cause**: Template files not installed.

```bash
# Re-run install
sudo ./install.sh

# Verify files exist
ls /usr/local/hestia/data/templates/web/nginx/php-fpm/mannn-proxy-*
# Should show 9 files (3 per template: .tpl, .stpl, .sh)

# Refresh HestiaCP panel (Ctrl+F5)
```

## Nginx Config Test Fails

```bash
# Test config
nginx -t

# If error about missing include file:
cat /home/{user}/conf/web/{domain}/nginx.proxy.conf
# If missing, re-apply template:
v-change-web-domain-tpl {user} {domain} mannn-nodejs-proxy

# Reload nginx
systemctl reload nginx
```

## App Crashes on Start

```bash
# Check detailed logs
journalctl -u mannn-{domain} -n 100 --no-pager

# Common issues:
# - Missing dependencies (npm install, pip install, go mod tidy)
# - Syntax error in app code
# - Port conflict (see above)
# - Permission denied (check file ownership)
```

## Permission Denied

```bash
# Fix app directory ownership
chown -R {user}:{user} /home/{user}/web/{domain}/private/{runtime}/

# Fix .env permissions
chmod 600 /home/{user}/web/{domain}/private/{runtime}/.env
chown {user}:{user} /home/{user}/web/{domain}/private/{runtime}/.env

# Re-apply template to auto-fix everything
v-change-web-domain-tpl {user} {domain} mannn-nodejs-proxy
```

## Go Build Fails

```bash
# Check Go is installed
go version

# Try building manually
cd /home/{user}/web/{domain}/private/go/
go build -o server . 2>&1

# Common issues:
# - go.mod not initialized: go mod init example.com/myapp
# - Missing dependencies: go mod tidy
# - Syntax errors: check error output
```

## Python venv Not Detected

The template checks for `venv/bin/python3` in the app directory.

```bash
# Verify venv structure
ls /home/{user}/web/{domain}/private/python/venv/bin/python3

# If missing, create it:
cd /home/{user}/web/{domain}/private/python/
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Re-apply template to update service ExecStart
v-change-web-domain-tpl {user} {domain} mannn-python-proxy
```

## WebSocket Not Working

The proxy config already includes WebSocket support headers:
```
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
```

If WebSocket connections time out, increase the timeouts in the generated config:

```bash
# Edit the proxy config directly
nano /home/{user}/conf/web/{domain}/nginx.proxy.conf

# Change timeouts:
# proxy_read_timeout 3600s;  (for long-lived connections)
```

Note: this file is regenerated on template re-apply, so changes will be lost.

## FrankenPHP Not Starting

```bash
# Check FrankenPHP binary
frankenphp version

# Check service logs
journalctl -u mannn-{domain} -n 50 --no-pager

# Common issues:
# - FrankenPHP binary not found: install to /usr/local/bin/frankenphp
# - Laravel Octane not installed: composer require laravel/octane
# - Wrong PHP version: FrankenPHP bundles its own PHP, check compatibility
```

## Docker Container Not Running

```bash
# Check Docker daemon
systemctl status docker

# List containers
docker ps -a

# Check specific container
docker logs mannn-{domain}

# Common issues:
# - Dockerfile syntax error: docker build -t test /home/{user}/web/{domain}/private/docker/
# - Port already in use: change PORT in .env
# - Container exits immediately: check docker logs for crash reason
# - Permission denied on docker socket: user needs docker group or run with sudo
```

## Docker Port Mapping Wrong

The `.env` for Docker has TWO port variables:
```
PORT=9000            # host port — what nginx proxies to
CONTAINER_PORT=80    # port inside the container
```

If the app inside the container listens on port 3000:
```bash
echo -e "PORT=9000\nCONTAINER_PORT=3000" > /home/{user}/web/{domain}/private/docker/.env
v-change-web-domain-tpl {user} {domain} mannn-docker-proxy
```
