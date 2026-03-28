# setup-distro.sh

Cross-platform dev environment bootstrap script for macOS and Debian/Ubuntu (including WSL). Idempotent — skips tools already installed unless `--upgrade` is set.

## Table of Contents

- [Usage](#usage)
- [Options](#options)
- [Categories](#categories)
- [Platform Support](#platform-support)
- [Behaviour](#behaviour)
- [Output](#output)
- [Exit Codes](#exit-codes)
- [Dependencies Between Categories](#dependencies-between-categories)

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

# Syntax check only
bash -n scripts/bash/setup-distro.sh
```

## Options

| Option | Description |
|---|---|
| `--all` | Install all categories (default) |
| `--only=<csv>` | Install only listed categories (e.g. `--only=core,cli`) |
| `--skip=<csv>` | Skip listed categories (e.g. `--skip=cloud,containers`) |
| `--upgrade` | Re-install/upgrade tools even if already present |
| `--help` | Show usage |

`--only` and `--skip` are mutually exclusive — providing both exits with code 2.

All options support `--key=value` and `--key value` syntax.

## Categories

Categories run in dependency order: core → cli → shell → languages → cloud → web → containers → powershell.

| Category | Tools | Install Methods |
|---|---|---|
| core | curl, wget, git, unzip, build-essential, gitleaks | Package manager; gitleaks via GitHub release binary |
| cli | bat, ripgrep, fzf, zoxide, fastfetch, htop | Package manager |
| shell | starship, Nerd Font (FiraCode) | Starship via curl installer; font via brew cask (macOS) or GitHub release (Linux) |
| languages | nvm + Node LTS, python3 + pip + venv | nvm via curl installer; python3 via package manager |
| cloud | aws-cli v2, azure-cli, wrangler | aws-cli via official installer (Linux) or brew (macOS); azure-cli via Microsoft script (Linux) or brew (macOS); wrangler via npm |
| web | nginx, certbot + nginx plugin, mkcert | Package manager |
| containers | docker + docker compose | Official Docker script (Linux) or brew cask (macOS) |
| powershell | pwsh | Microsoft package repo (Linux) or brew cask (macOS) |

## Platform Support

- **macOS**: Uses Homebrew (installed automatically if missing). Package names are translated via `pkg_name()` — e.g. `build-essential` is skipped, `python3-pip` and `python3-venv` are omitted (included in brew's `python3`).
- **Debian/Ubuntu (including WSL)**: Uses apt. On Debian, `bat` installs as `batcat` — the script detects this correctly.

Unsupported platforms exit with code 1.

## Behaviour

- **Idempotent**: each tool is guarded by `needs_install()` which checks `command -v`. Skipped if already on PATH unless `--upgrade` is set.
- **Package index update**: `pkg_update` (brew update / apt update) runs at the start of every invocation to ensure fresh package lists.
- **Non-fatal tool failures**: individual tool failures print a failure message; the script continues to the next tool.
- **Temporary file cleanup**: functions that download files use `trap ... RETURN` to ensure temp directories are cleaned up even on unexpected errors.
- **Upgrade mode**: when `--upgrade` is set, `needs_install` guards are bypassed and tools are re-installed or upgraded. Curl-based installers (starship, nvm) handle upgrades natively.

## Output

Each tool prints a status line:

```
▶️  Installing core tools...
  ✅ curl (already installed)
  ✅ wget (already installed)
  ✅ git (already installed)
  ✅ build-essential (installed)
  ✅ gitleaks v8.21.0 (installed)
```

Status labels: `(already installed)`, `(installed)`, `(upgraded)`, `(skipped — <reason>)`, `(failed)`.

An end-of-run summary shows totals:

```
Summary:
  Installed: 12
  Skipped:   8
  Failed:    0

✅ Setup complete.
```

If any tools failed, the final message changes to a warning with the failure count.

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success (all tools installed or skipped) |
| 1 | Fatal error (unsupported platform) |
| 2 | Invalid arguments (`--only` and `--skip` combined, or unrecognised options) |

## Dependencies Between Categories

- **cloud** depends on **languages** for wrangler (npm). If Node is not installed and the languages category is skipped, wrangler is skipped with a warning.
- **core** should run first as curl and git are needed by later installers that download from the internet or GitHub.
