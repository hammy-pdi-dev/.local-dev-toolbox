# setup-distro.sh — Cross-Platform Dev Environment Setup

**Date:** 2026-03-27
**Status:** Approved
**Script:** `scripts/bash/setup-distro.sh`

## Purpose

Idempotent, cross-platform script to bootstrap a development environment on macOS and Debian/Ubuntu (including WSL). Installs dev tools, CLI utilities, shell enhancements, language runtimes, cloud CLIs, web server tooling, containers, and PowerShell. Follows the coding conventions established by `_update-repos.sh`.

## CLI Interface

```
Usage: setup-distro.sh [OPTIONS]

Options:
  --all                Install all categories (default)
  --only=<csv>         Install only these categories (e.g. --only=core,cli)
  --skip=<csv>         Skip these categories (e.g. --skip=cloud,containers)
  --upgrade            Re-install/upgrade tools even if already present
  --help               Show this help message

Categories: core, cli, shell, languages, cloud, web, containers, powershell
```

**Behaviour:**
- Default is `--all` — every category runs.
- `--only` and `--skip` are mutually exclusive; script exits with error if both provided.
- Each tool is guarded by `cmd_exists` — skipped if already installed unless `--upgrade` is set.
- Exit codes: 0 = success, 1 = fatal error, 2 = invalid arguments.

## Architecture

### Script Structure

Follows `_update-repos.sh` conventions exactly:

```
#!/usr/bin/env bash
set -euo pipefail

# Section separators: # -------...
# Globals: UPPER_SNAKE_CASE
# Locals: declared with `local`, lower_snake_case
# Functions: snake_case, Allman-ish brace placement matching _update-repos.sh
```

### Sections (in order)

1. **Shebang + strict mode**
2. **ANSI colours + symbols** — same variables as `_update-repos.sh` (`C_RED`, `SYM_SUCCESS`, etc.)
3. **Formatting helpers** — `fmt()`, `msg()`, `warn()`, `err()` from `_update-repos.sh` plus `step()`, `success()`, `failure()` wrappers matching `migrate-wsl-distro.ps1` style
4. **Platform detection** — sets `PLATFORM` ("macos" | "debian") and `PKG_MANAGER` ("brew" | "apt"); exits on unsupported
5. **Package manager abstraction** — `pkg_install()`, `pkg_update()`, `pkg_upgrade()`, `pkg_has()`, `cmd_exists()`, `curl_install()`, `pkg_name()`
6. **Category install functions** — one per category: `install_core()`, `install_cli()`, etc.
7. **Argument parsing** — `parse_args()`, `show_usage()`
8. **Main + entry point** — orchestrates categories in dependency order

### Platform Detection

Reuses `get_distro()` from `.bashrc` (extended to return `"macos"`) and `extract()` for archive unpacking. Copied into the script — `.bashrc` cannot be sourced from non-interactive scripts due to its `[[ $- != *i* ]] && return` guard.

```
get_distro():
  macOS        -> "macos"
  ubuntu/debian/mint -> "debian"
  fedora/rhel/centos -> "redhat"
  arch/manjaro -> "arch"
  *            -> "unknown"

detect_platform():
  calls get_distro()
  "macos"  -> PLATFORM="macos",  PKG_MANAGER="brew"
  "debian" -> PLATFORM="debian", PKG_MANAGER="apt"
  else     -> error + exit 1
```

On macOS, if Homebrew is not installed, the script installs it first.

### Package Manager Abstraction

The `pkg` layer eliminates per-tool platform branching:

- **`pkg_install <name...>`** — translates names via `pkg_name()`, runs `brew install` or `sudo apt install -y`. Skips empty names (allows platform-specific exclusions like `build-essential` on macOS).
- **`pkg_update()`** — `brew update` or `sudo apt update`.
- **`pkg_upgrade <name...>`** — `brew upgrade` or `sudo apt install --only-upgrade -y`.
- **`pkg_has <name>`** — checks if a package is available in the repo (for guarding optional installs).
- **`cmd_exists <cmd>`** — `command -v` wrapper returning true/false.
- **`curl_install <url>`** — `curl -fsSL <url> | bash` for tools using this pattern (starship, nvm).
- **`pkg_name <name>`** — name normalisation table for cross-platform differences:

| Input | apt | brew |
|---|---|---|
| `build-essential` | `build-essential` | *(empty — skip)* |
| `fd-find` | `fd-find` | `fd` |
| `bat` | `bat` | `bat` |
| `ripgrep` | `ripgrep` | `ripgrep` |

### Category Install Functions

Each function follows this pattern:

```bash
install_<category>() {
    step "Installing <category> tools..."

    # Simple package-manager tools
    cmd_exists <tool> && ! $UPGRADE || pkg_install <tool>

    # Tools needing special installers
    install_<specific_tool>
}
```

#### core (`--core`)

| Tool | Method |
|---|---|
| curl | `pkg_install` |
| wget | `pkg_install` |
| git | `pkg_install` |
| unzip | `pkg_install` |
| build-essential | `pkg_install` (skipped on macOS via `pkg_name`) |
| gitleaks | GitHub release binary download (latest from `github.com/gitleaks/gitleaks/releases`) |

#### cli (`--cli`)

| Tool | Method |
|---|---|
| bat | `pkg_install` |
| ripgrep | `pkg_install` |
| fzf | `pkg_install` |
| zoxide | `pkg_install` |
| fastfetch | `pkg_install` |
| htop | `pkg_install` |

#### shell (`--shell`)

| Tool | Method |
|---|---|
| starship | `curl_install` via `starship.rs` installer |
| Nerd Font (FiraCode) | brew cask on macOS; manual download + install to `~/.local/share/fonts` on Linux |

#### languages (`--languages`)

| Tool | Method |
|---|---|
| nvm + Node LTS | `curl_install` via nvm installer, then `nvm install --lts` |
| python3 + pip | `pkg_install python3 python3-pip` (apt) / `pkg_install python3` (brew, pip included) |

React/Next.js available via `npx` once Node is installed — no global install needed.

#### cloud (`--cloud`)

| Tool | Method |
|---|---|
| aws-cli v2 | Official installer: download zip, unzip, run `./aws/install` (Linux); `brew install awscli` (macOS) |
| azure-cli | Microsoft install script (Linux); `brew install azure-cli` (macOS) |
| wrangler (Cloudflare) | `npm install -g wrangler` (requires Node from languages category) |

**Dependency:** wrangler requires Node. If `--skip=languages` and Node is not present, warn and skip wrangler.

#### web (`--web`)

| Tool | Method |
|---|---|
| nginx | `pkg_install` |
| certbot | `pkg_install` (apt: `certbot python3-certbot-nginx`; brew: `certbot`) |
| mkcert | `pkg_install` (available in both apt and brew) |

#### containers (`--containers`)

| Tool | Method |
|---|---|
| docker + compose | Official Docker install script (`get.docker.com`) on Linux; `brew install --cask docker` on macOS |

Post-install on Linux: add current user to `docker` group.

#### powershell (`--powershell`)

| Tool | Method |
|---|---|
| pwsh | Microsoft package repo (apt) on Linux; `brew install --cask powershell` on macOS |

### Execution Order

Categories run in dependency order:

1. **core** — curl/git needed by later installers
2. **cli** — no deps
3. **shell** — no deps
4. **languages** — nvm/node needed by cloud (wrangler)
5. **cloud** — may need npm from languages
6. **web** — no deps
7. **containers** — no deps
8. **powershell** — no deps

### Upgrade Behaviour

When `--upgrade` is set:
- `pkg_update()` runs at the start
- `cmd_exists` checks are bypassed — tools are re-installed/upgraded
- For curl-based installers, the installer script handles upgrades natively (starship, nvm)
- For GitHub release binaries (gitleaks), the latest version is downloaded and replaces existing

### Output Style

Matches `_update-repos.sh` and `migrate-wsl-distro.ps1` output:

```
▶️  Installing core tools...
  ✅ curl (already installed)
  ✅ wget (already installed)
  ✅ git (already installed)
  ✅ unzip (already installed)
  ✅ build-essential (installed)
  ✅ gitleaks v8.21.0 (installed)
▶️  Installing CLI tools...
  ...
```

Each tool prints either:
- `(already installed)` — skipped
- `(installed)` — newly installed
- `(upgraded)` — when `--upgrade` used
- `(skipped — <reason>)` — dependency missing or platform unsupported
- `(failed)` — installation failed, warning printed, script continues

### Error Handling

- Individual tool failures are warnings, not fatal — script continues to next tool.
- Category-level issues (e.g. no package manager) are fatal.
- Summary at the end shows what was installed, skipped, and failed.

### Testing

No test framework. Validation is:
- `bash -n setup-distro.sh` for syntax check
- Manual run with `--only=core` on both macOS and Ubuntu/Debian WSL
- Verify idempotency by running twice — second run should skip everything
