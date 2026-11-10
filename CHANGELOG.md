# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.4.2] - 2026-11-10

### Fixed

- `install.sh`: an nginx reload that nginx itself rejects (e.g. changing the `limit_req` zone key — nginx keeps the old shared-memory zone and logs `[emerg]`, while systemd still reports the reload as successful) left the server silently running the OLD configuration. install.sh now detects a fresh `[emerg]` in the nginx error log after reload and recovers with a full `systemctl restart nginx` (drops open connections for ~1s), failing loudly if that also fails

## [1.4.1] - 2026-11-10

### Fixed

- `mannn-laravel` templates shipped none of the mannn hardening (no security headers, rate limiting, `server_tokens off`, sensitive-file blocking) — the PHP-FPM template now applies the same header set (`X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy`, CSP-Report-Only, `Permissions-Policy`), `limit_req` 429, `fastcgi_hide_header X-Powered-By`, and blocks backup/config files; archives (`.zip`/`.gz`/`.tar`) stay downloadable since PHP apps publish them legitimately

## [1.4.0] - 2026-11-10

Audit-driven hardening (empirically verified in containers: nginx behavior, firewall
lifecycle, concurrency; systemd sandbox verified against all four runtimes).

### Security

- **IPv6 firewall coverage** — app ports are now restricted via `ip6tables` in addition to `iptables`; previously the DROP rule was IPv4-only, leaving backends directly reachable over IPv6 on dual-stack servers
- **systemd sandbox expanded** (all runtime units): `PrivateDevices`, `ProtectClock`, `ProtectControlGroups`, `ProtectHostname`, `ProtectKernelLogs/Modules/Tunables`, `ProtectProc=invisible`, `RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK`, `RestrictRealtime`, `RestrictSUIDSGID`, `SystemCallFilter=@system-service`, `SystemCallArchitectures=native`, `LockPersonality`, `UMask=0027`
- **`MemoryMax` per runtime** (node 512M / go 256M / python 512M / frankenphp 1G) — runaway apps are OOM-killed instead of starving the server; override via a systemd drop-in (survives re-apply)
- **Port registry hardened** — directory `700` / entries `600` (unit-name-to-port mapping no longer readable by local users), mutations serialized with `flock` so concurrent applies of the same domain cannot interleave
- `MANNN_REQUIRE_FIREWALL=1` opt-in fail-closed mode for servers without iptables/ip6tables binaries (nftables-only hosts)
- FrankenPHP placeholder no longer discloses the PHP version in its response

### Fixed

- **Rate-limit budget shared across domains** — zone key is now `$server_name$binary_remote_addr`; previously all domains shared one per-IP bucket, so a burst against domain A returned 429 for domain B to the same client (verified: 15/15 cross-domain requests 429 before fix, 200 after)
- **Legacy firewall rules never cleaned** — pre-1.3.0 rules used `! -s 127.0.0.1/32` while cleanup only matched `! -i lo`; orphaned legacy rules (and their duplicates) now removed on re-apply/uninstall (verified in privileged container)
- **Early-Data not forwarded to backends** — SSL proxy include now sends `Early-Data: $rfc_early_data` (RFC 8470), matching HestiaCP's own 0-RTT guidance; backends can reject non-idempotent TLS 1.3 0-RTT replays
- Placeholder apps now prefer the service `PORT` environment variable over `.env` (editing `.env` + `systemctl restart` no longer silently changes the app port out from under nginx)
- `uninstall.sh` refuses to remove templates still referenced by domains (would break `nginx -t` on the next rebuild); override with `MANNN_FORCE_UNINSTALL=1`
- `mannn_unrestrict_all` could leave rules behind when more than 10 tagged rules existed (attempt cap raised to 200); now also covers IPv6

### Unchanged (documented decisions)

- No upstream keepalive pooling to app backends: `proxy_pass` to a literal address cannot use `upstream {}` keepalive from a server-context include, and the upgrade map's `Connection: close` for non-WS requests matches nginx's one-connection-per-request behavior
- No HTTP/3/QUIC listeners: target is distro nginx on Debian/Ubuntu, which ships without `http_v3_module` (enabling `quic` would break `nginx -t` there)

## [1.3.0] - 2026-11-10

### Added

- **Port registry** (`/usr/local/hestia/data/mannn-ports/<port>`) — two domains can no longer share a port (cross-tenant routing leak). Conflicting applies write a temporary 503 stub config, don't start the service, and error with instructions to change `PORT` in `.env`
- **WebSocket upgrade map** deployed to `/etc/nginx/conf.d/mannn-upgrade-map.conf` — `Connection: upgrade` only for real upgrade requests, `close` otherwise
- `X-Forwarded-Host` and `X-Forwarded-Port` proxy headers
- CI: shellcheck + nginx template render test (`scripts/render-templates-test.sh` in GitHub Actions)

### Changed

- `proxy_read_timeout` raised to 3600s (idle WebSocket survival); connect/send stay 60s; `proxy_buffering off` (SSE/streaming)
- Rate-limited requests now return **HTTP 429** (was 503); rate unchanged (10 req/s, burst 20)
- `X-XSS-Protection` header removed (obsolete, harmful on old browsers)
- CSP replaced by `Content-Security-Policy-Report-Only: frame-ancestors 'none'; base-uri 'self'; object-src 'none'` — apps can set their own enforcing CSP without double-policy breakage
- Hardcoded HSTS removed — HSTS is solely managed via the HestiaCP panel (`nginx.hsts.conf` include), avoiding duplicate STS headers
- TLS templates: `http2 on;` instead of deprecated `listen ... ssl http2` flag (nginx ≥ 1.25.1)
- systemd units: `After=`/`Wants=network-online.target`, `TimeoutStopSec=20`
- `go build` runs as the domain user via `runuser` (HOME=app dir, build cache under `private/go/.cache`) — root no longer compiles user-supplied code
- iptables rules tagged `mannn-<unit>-<port>`; changing `PORT` auto-removes the old rule

### Removed

- `ssl_stapling` (Let's Encrypt ends OCSP support in 2025 — matches upstream HestiaCP)

### Fixed

- Two domains of the same runtime could pick the same port, routing both to one app
- iptables rule leak on port change; uninstall now flushes every `mannn-*` rule, stops every `mannn-*` service, and removes the registry
- Restored upstream HestiaCP TLS 1.3 0-RTT anti-replay handling (`$anti_replay`) and `/vstats/` location (domain statistics)
- `uninstall.sh` now also removes the `laravel` template (was missing from the removal list)

## [1.2.0] - 2026-06-05

### Added

- **Sensitive file blocking** at nginx level — `.bak`, `.backup`, `.old`, `.orig`, `.save`, `.swp`, `.tmp`, `.sql`, `.zip`, `.tar`, `.gz`, `.rar`, `.log` extensions return 404 before reaching the backend
- **Config file path blocking** — `wp-config.php`, `config.php`, `settings.php`, `database.yml`, `appsettings.json` return 404 at nginx level
- **Rate limiting** — 10 req/s per IP with burst of 20 (configurable zone `mannn` in `/etc/nginx/conf.d/mannn-rate-limit.conf`)
- **`server_tokens off`** — hides nginx version from response headers
- **`client_max_body_size 10m`** — explicit upload size limit
- `mannn-rate-limit.conf` — shared rate limit zone definition deployed to `/etc/nginx/conf.d/`
- Install script auto-deploys rate-limit config and reloads nginx
- Uninstall script cleans up rate-limit config when all templates removed

### Changed

- Fixed **soft 404 vulnerability** — proxy backends returning 200 for non-existent paths. Sensitive paths now blocked at nginx layer with proper 404.
- All `.tpl` and `.stpl` templates now include additional location blocks for file extension and config path blocking

### Security

- Prevents attackers from enumerating sensitive files via HTTP status codes
- Rate limiting mitigates brute-force and automated scanning attacks
- Previously, paths like `/wp-config.php`, `/config.php`, `/config.php.bak` would return 200 (via backend catch-all). Now return 404 at nginx level.

## [1.1.0] - 2026-06-04

### Added

- `access_log` directives (combined + bytes format) to all `.tpl` and `.stpl` templates
  - Enables HestiaCP **Logs** UI tab for proxy domains (previously empty)
  - Enables bandwidth statistics via `.bytes` log
  - Enables log analysis tools (GoAccess, Matomo, fail2ban)

### Changed

- Security headers hardened across all templates:
  - `Content-Security-Policy` with `frame-ancestors 'none'`
  - `Permissions-Policy` denying camera, microphone, geolocation, payment
  - `Strict-Transport-Security` (HSTS) on all SSL templates
  - `proxy_hide_header X-Powered-By` to prevent backend fingerprinting

## [1.0.1] - 2026-06-02

### Changed

- Docker template switched to **proxy-only** mode — no longer creates systemd services
- Existing Docker systemd services are cleaned up on re-apply
- Docker documentation clarified to explain proxy-only workflow

### Fixed

- Port path alignment for Docker template
- Documentation corrections for Docker backend setup

## [1.0.0] - 2026-05-26

### Added

- 5 runtime proxy templates for HestiaCP:
  - **Node.js** proxy (port 3100–3999)
  - **Go** proxy (port 4100–4999)
  - **Python** proxy (port 8100–8999)
  - **FrankenPHP / Laravel Octane** proxy (port 7100–7999)
  - **Docker / Compose** proxy (port 9100–9999)
- Interactive install/uninstall scripts with selective template support
- Shared security helper (`mannn-security.sh`) with hash-based naming, port validation, iptables restrictions
- Backup exclusion script (`setup-backup-exclusions.sh`) to skip `node_modules`, `venv`, `vendor`, binaries from HestiaCP backups
- Full documentation:
  - `README.md` — quick start, usage, reference
  - `docs/prerequisites.md` — server setup guide
  - `docs/architecture.md` — template internals
  - `docs/deployment.md` — deployment workflows per runtime
  - `docs/troubleshooting.md` — error codes and fixes

[1.4.2]: https://github.com/mannnrachman/mannn-hestia-proxy/releases/tag/v1.4.2
[1.4.0]: https://github.com/mannnrachman/mannn-hestia-proxy/releases/tag/v1.4.0
[1.4.1]: https://github.com/mannnrachman/mannn-hestia-proxy/releases/tag/v1.4.1
[1.3.0]: https://github.com/mannnrachman/mannn-hestia-proxy/releases/tag/v1.3.0
[1.2.0]: https://github.com/mannnrachman/mannn-hestia-proxy/releases/tag/v1.2.0
[1.1.0]: https://github.com/mannnrachman/mannn-hestia-proxy/releases/tag/v1.1.0
[1.0.1]: https://github.com/mannnrachman/mannn-hestia-proxy/releases/tag/v1.0.1
[1.0.0]: https://github.com/mannnrachman/mannn-hestia-proxy/releases/tag/v1.0.0
