# Contributing to mannn-hestia-proxy

Thank you for your interest in contributing! This project provides dynamic Nginx reverse proxy templates for HestiaCP.

## Ways to Contribute

- **Bug reports** — Open an issue with steps to reproduce, expected vs actual behavior, and relevant logs
- **Feature requests** — Open an issue describing the use case and proposed solution
- **Security vulnerabilities** — Please report privately via GitHub Security Advisories, not in public issues
- **Code contributions** — Pull requests welcome (see below)
- **Documentation** — Fixes, clarifications, and translations are all welcome

## Development Setup

### Prerequisites

- A server or VM running HestiaCP with nginx-only (no Apache)
- Bash shell
- `git`

### Local Workflow

```bash
# Clone
git clone https://github.com/mannnrachman/mannn-hestia-proxy.git
cd mannn-hestia-proxy

# Create a branch
git checkout -b feat/my-feature

# Make changes, test on your HestiaCP server
sudo ./install.sh all

# Rebuild a domain to test
sudo /usr/local/hestia/bin/v-rebuild-web-domains <user>
sudo systemctl reload nginx

# Verify
curl -I http://your-test-domain.example.com/

# Commit and push
git add .
git commit -m "feat: describe your change"
git push origin feat/my-feature
```

### Testing Your Changes

Before submitting a PR, verify:

1. **Install** — `sudo ./install.sh all` completes without errors
2. **Nginx config** — `sudo nginx -t` passes
3. **Domain works** — `curl http://your-test-domain/` returns expected response
4. **Security paths blocked**:
   ```bash
   curl -s -o /dev/null -w "%{http_code}" http://your-test-domain/.env          # expect 404
   curl -s -o /dev/null -w "%{http_code}" http://your-test-domain/wp-config.php # expect 404
   curl -s -o /dev/null -w "%{http_code}" http://your-test-domain/config.php.bak # expect 404
   curl -s -o /dev/null -w "%{http_code}" http://your-test-domain/              # expect 200
   ```
5. **Uninstall** — `sudo ./uninstall.sh all` removes templates cleanly
6. **No sensitive data** — Check that no IPs, passwords, or server-specific info is in your changes

## Code Style

### Shell Scripts (.sh)

- Use `set -u` for unset variable protection
- Quote all variable expansions: `"$var"` not `$var`
- Functions prefixed with `mannn_` to avoid collisions
- Source shared helper: `. "mannn-security.sh"`
- Use heredocs for generated configs: `cat > file << 'EOF'`

### Nginx Templates (.tpl / .stpl)

- Use 4-space indentation
- Keep all templates (nodejs, go, python, frankenphp, docker) **identical** except for template-specific variables
- Security directives go **before** the proxy include
- Location blocks ordered: dotfiles → private → extensions → config paths → proxy

### Documentation (.md)

- Generic examples: `myapp.example.com`, `devuser`, not real domains or IPs
- No passwords, credentials, or internal server details
- Update README.md, CHANGELOG.md, and relevant docs/ files together

## Pull Request Process

1. **One concern per PR** — bug fix, feature, or docs, not mixed
2. **Update CHANGELOG.md** — add your change under `[Unreleased]` or the next version
3. **Test on a real HestiaCP server** — include test results in the PR description
4. **No sensitive data** — PRs containing passwords, IPs, or server-specific config will be rejected
5. **Document new features** — update README.md and relevant docs/ files

## Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add support for Bun runtime
fix: correct port validation for Docker template
docs: clarify Docker proxy-only workflow
security: block additional sensitive file patterns
chore: update install script compatibility check
```

## Adding a New Runtime Template

To add a new runtime (e.g., Bun, Deno, Rust):

1. Create `templates/{runtime}/` with three files:
   - `mannn-{runtime}-proxy.tpl` — copy from existing, identical structure
   - `mannn-{runtime}-proxy.stpl` — copy from existing, identical structure
   - `mannn-{runtime}-proxy.sh` — follow existing pattern, pick a port range (check security.sh `MANNN_BLOCKED_PORTS`)
2. Add a placeholder app in `templates/{runtime}/todo-app/`
3. Register in `install.sh` and `uninstall.sh` `TEMPLATES` array
4. Add backup exclusion in `setup-backup-exclusions.sh`
5. Update README.md (templates table, directory structure, step-by-step guide)
6. Update CHANGELOG.md
7. Test: install → create domain → apply template → verify → uninstall

## Project Structure

```
mannn-hestia-proxy/
├── install.sh                  # Install templates to HestiaCP
├── uninstall.sh                # Remove templates from HestiaCP
├── setup-backup-exclusions.sh  # Exclude heavy dirs from backups
├── LICENSE                     # MIT license
├── README.md                   # Project overview and quick start
├── CHANGELOG.md                # Version history
├── CONTRIBUTING.md             # This file
├── docs/
│   ├── prerequisites.md        # Server setup guide
│   ├── architecture.md         # Template internals
│   ├── deployment.md           # Deployment workflows
│   └── troubleshooting.md      # Common issues and fixes
└── templates/
    ├── common/
    │   ├── mannn-security.sh       # Shared security helpers
    │   └── mannn-rate-limit.conf   # Rate limit zone definition
    ├── nodejs/                     # Node.js template
    ├── goproxy/                    # Go template
    ├── pypyroxy/                   # Python template
    ├── frankenphp/                 # FrankenPHP/Laravel Octane template
    └── docker/                     # Docker proxy-only template
```

## Questions?

Open an issue on [GitHub](https://github.com/mannnrachman/mannn-hestia-proxy/issues).

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
