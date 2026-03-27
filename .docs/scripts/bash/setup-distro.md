# setup-distro.sh

Cross-platform dev environment bootstrap script for macOS and Debian/Ubuntu (including WSL).

## Usage

```bash
# Install everything (default)
bash scripts/bash/setup-distro.sh

# Install only specific categories
bash scripts/bash/setup-distro.sh --only=core,cli,shell

# Skip categories
bash scripts/bash/setup-distro.sh --skip=cloud,containers

# Upgrade existing tools
bash scripts/bash/setup-distro.sh --upgrade

# Combine flags
bash scripts/bash/setup-distro.sh --only=core,cli --upgrade
```

## Categories

| Category | Flag | Tools |
|---|---|---|
| core | `--only=core` | curl, wget, git, unzip, build-essential, gitleaks |
| cli | `--only=cli` | bat, ripgrep, fzf, zoxide, fastfetch, htop |
| shell | `--only=shell` | starship, Nerd Font (FiraCode) |
| languages | `--only=languages` | nvm + Node LTS, python3 + pip |
| cloud | `--only=cloud` | aws-cli v2, azure-cli, wrangler (Cloudflare) |
| web | `--only=web` | nginx, certbot + nginx plugin, mkcert |
| containers | `--only=containers` | docker + docker compose |
| powershell | `--only=powershell` | pwsh (Microsoft package repo) |

## Options

| Option | Description |
|---|---|
| `--all` | Install all categories (default) |
| `--only=<csv>` | Install only listed categories |
| `--skip=<csv>` | Skip listed categories |
| `--upgrade` | Re-install/upgrade tools even if present |
| `--help` | Show usage |

`--only` and `--skip` are mutually exclusive.

## Platform Support

- **macOS**: Uses Homebrew (installed automatically if missing)
- **Debian/Ubuntu (including WSL)**: Uses apt + curl-based installers

## Behaviour

- **Idempotent**: skips tools already on PATH unless `--upgrade` is set
- **Non-fatal tool failures**: individual tool failures print a warning; script continues
- **Dependency order**: core runs first (curl/git needed by later installers), languages before cloud (npm needed for wrangler)

## Dependencies Between Categories

- **cloud** depends on **languages** for wrangler (npm). If Node is not installed and languages is skipped, wrangler is skipped with a warning.
