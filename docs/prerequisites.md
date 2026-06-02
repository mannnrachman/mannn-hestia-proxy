# Prerequisites

Server setup required before using mannn-hestia-proxy templates.

## 1. HestiaCP Installation

Install HestiaCP with nginx-only (no Apache):

```bash
wget https://raw.githubusercontent.com/hestiacp/hestiacp/release/install/hst-install.sh
bash hst-install.sh --nginx yes --apache no --phpfpm yes --multiphp no \
  --vsftd no --proftpd no --named yes --exim yes --dovecot yes \
  --sieve no --clamav no --spamassassin no --iptables yes --fail2ban yes \
  --quota no --interactive yes
```

If HestiaCP is already installed with Apache, switch to nginx-only:

```bash
# Edit main config
sed -i "s/WEB_SYSTEM='apache2'/WEB_SYSTEM='nginx'/" /usr/local/hestia/conf/hestia.conf
sed -i "s/PROXY_SYSTEM='nginx'/PROXY_SYSTEM=''/" /usr/local/hestia/conf/hestia.conf

# Remove Apache
apt remove --purge apache2 -y

# Restart services
systemctl restart nginx
```

## 2. Install Node.js (v22 LTS)

```bash
# Option A: System-wide binary (recommended for multi-user)
curl -fsSL https://nodejs.org/dist/v22.16.0/node-v22.16.0-linux-x64.tar.xz | tar -xJ -C /usr/local --strip-components=1

# Option B: Via NodeSource
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt install -y nodejs

# Verify
node --version  # v22.x.x
```

If using Option A, binary lands at `/usr/local/bin/node`. The template auto-detects it.

If installing to custom path (e.g., `/usr/local/node/`), create a symlink:

```bash
ln -sf /usr/local/node/bin/node /usr/local/bin/node
```

## 3. Install Go (latest)

```bash
# Download latest Go
GO_VERSION=$(curl -fsSL 'https://go.dev/VERSION?m=text')
curl -fsSL "https://go.dev/dl/${GO_VERSION}.linux-amd64.tar.gz" | tar -xz -C /usr/local

# Add to PATH
echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile.d/go.sh
source /etc/profile.d/go.sh

# Verify
go version  # go1.x.x linux/amd64
```

## 4. Install Python (latest)

```bash
# Option A: Build from source (for latest version)
apt install -y build-essential zlib1g-dev libncurses5-dev libgdbm-dev \
  libnss3-dev libssl-dev libreadline-dev libffi-dev libsqlite3-dev \
  wget libbz2-dev

PYTHON_VERSION="3.14.5"
curl -fsSL "https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz" | tar -xz
cd Python-${PYTHON_VERSION}
./configure --enable-optimizations --prefix=/usr/local
make -j$(nproc)
make altinstall

# Create symlink
ln -sf /usr/local/bin/python3.14 /usr/local/bin/python3

# Verify
python3 --version  # Python 3.14.x

# Option B: Via deadsnakes PPA (Ubuntu only)
add-apt-repository ppa:deadsnakes/ppa
apt update
apt install -y python3.14 python3.14-venv python3.14-dev
```

## 5. Install FrankenPHP (for PHP/Laravel Octane)

```bash
# Download FrankenPHP binary
curl -fsSL https://github.com/dunglas/frankenphp/releases/latest/download/frankenphp-linux-x86_64 \
  -o /usr/local/bin/frankenphp
chmod +x /usr/local/bin/frankenphp

# Verify
frankenphp version
# FrankenPHP v1.x.x PHP 8.x.x Caddy ...

# For Laravel Octane (install inside Laravel project):
# composer require laravel/octane
# php artisan octane:install --server=frankenphp
```

## 6. Install Docker (for Docker templates)

```bash
# Install Docker
curl -fsSL https://get.docker.com | sh

# Verify
docker --version

# (Optional) Add user to docker group
# Needed only if a real user will run docker commands manually or via CI/CD.
usermod -aG docker myuser
```

## 7. Secure HestiaCP Panel (optional but recommended)

```bash
# Change panel port (e.g., 8083 → custom port)
sed -i 's/8083/YOUR_CUSTOM_PORT/' /usr/local/hestia/nginx/conf/nginx.conf

# Bind to specific IP only
sed -i 's/0.0.0.0/YOUR_SERVER_IP/' /usr/local/hestia/nginx/conf/nginx.conf

# Restart panel
systemctl restart hestia
```

## 8. Verify Setup

```bash
# Check web system
grep WEB_SYSTEM /usr/local/hestia/conf/hestia.conf
# Expected: WEB_SYSTEM='nginx'

# Check proxy system
grep PROXY_SYSTEM /usr/local/hestia/conf/hestia.conf
# Expected: PROXY_SYSTEM=''

# Check runtimes
node --version
go version
python3 --version
frankenphp version
docker --version
```


## 9. Important Runtime Model

Install Node.js, Go, Python, FrankenPHP, and Docker **once per server**.
Do not install them separately for each Hestia user.

Per user/domain you only keep:
- app source code
- `.env`
- local deps like `node_modules/` or `venv/`
- built binary like `private/go/server`
