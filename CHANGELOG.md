# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[1.2.0]: https://github.com/mannnrachman/mannn-hestia-proxy/releases/tag/v1.2.0
[1.1.0]: https://github.com/mannnrachman/mannn-hestia-proxy/releases/tag/v1.1.0
[1.0.1]: https://github.com/mannnrachman/mannn-hestia-proxy/releases/tag/v1.0.1
[1.0.0]: https://github.com/mannnrachman/mannn-hestia-proxy/releases/tag/v1.0.0
