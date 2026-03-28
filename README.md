# .local-dev-toolbox

Cross-platform developer automation and environment setup toolkit. Bash and PowerShell scripts for bulk Git repository management, shell configuration, Git hooks, and Windows Sandbox provisioning.

## Repository Structure

```
scripts/
├── .docs/                     Per-script documentation (mirrors script folder layout)
├── bash/                      Bash scripts and dotfiles
│   ├── .bashrc                    Team-reusable shell config (WSL/Linux/macOS)
│   ├── .bash_profile              Login shell startup
│   ├── .bashrc.local              Personal overrides (gitignored, copied to ~ by bootstrap)
│   ├── .bashrc.local.example      Template with placeholders for new users
│   ├── .zshrc                     Zsh equivalent
│   ├── _update-repos.sh           Bulk Git fetch/pull
│   ├── setup-distro.sh            Dev environment bootstrap
│   └── fc-rsync.sh                Backup via rsync
├── powershell/
│   ├── utils/                     Repository management, git history, timestamps
│   ├── wsl/                       WSL distribution management
│   └── sandbox/                   Windows Sandbox setup automation for service solution
├── batch/                     Windows batch backup scripts
└── git-hooks/                 Git hook scripts (pre-commit, commit-msg)
```

## Scripts

### Repository Management

| Script | Platform | Description | Docs |
|--------|----------|-------------|------|
| `scripts/powershell/utils/_update-repos.ps1` | Windows | Batch fetch/pull for multiple Git repositories with RunspacePool parallelism | [docs](scripts/.docs/powershell/_update-repos.md) |
| `scripts/bash/_update-repos.sh` | Linux/macOS | Bash equivalent using background subshells for parallel processing | [docs](scripts/.docs/bash/_update-repos.md) |

Both scripts scan a root directory for child folders matching a configurable prefix, then fetch and pull each repo in parallel (default: 4 workers). Supports `--skip-dirty`, `--stash-dirty`, `--use-rebase`, `--fetch-all-remotes`, and `--verbose`.

### Environment Setup

| Script | Platform | Description | Docs |
|--------|----------|-------------|------|
| `scripts/bash/setup-distro.sh` | Linux/macOS | Idempotent dev environment bootstrap — symlinks dotfiles, installs dev tools, CLI utilities, shell enhancements, language runtimes, cloud CLIs, web server tooling, containers, and PowerShell | [docs](scripts/.docs/bash/setup-distro.md) |
| `scripts/powershell/wsl/migrate-wsl-distro.ps1` | Windows | Migrate a WSL distribution to a new location with export/import | [docs](scripts/.docs/powershell/wsl/migrate-wsl-distro.md) |

### Utilities

| Script | Platform | Description | Docs |
|--------|----------|-------------|------|
| `scripts/powershell/utils/git-history.ps1` | Windows | Generate formatted release notes from Git commit history for specified time periods | [docs](scripts/.docs/powershell/git-history.md) |
| `scripts/powershell/utils/fix-timestamps.ps1` | Windows | Batch timestamp updates for build artifacts | [docs](scripts/.docs/powershell/fix-timestamps.md) |
| `scripts/bash/fc-rsync.sh` | Linux/macOS | Backup and sync repositories using rsync | [docs](scripts/.docs/bash/fc-rsync.md) |
| `scripts/batch/_backup_fc-repo.bat` | Windows | Repository backup via xcopy | — |

### Git Hooks

| Script | Description | Docs |
|--------|-------------|------|
| `scripts/git-hooks/pre-commit` | Runs [gitleaks](https://github.com/gitleaks/gitleaks) against staged changes to prevent secrets from being committed | [docs](scripts/.docs/git-hooks/pre-commit.md) |
| `scripts/git-hooks/commit-msg` | Automatically prefixes commit messages with ticket numbers extracted from branch names (e.g. `feature/123-foo` → `123 - message`) | — |

Install hooks by copying them into your repository's `.git/hooks/` folder:

```bash
cp scripts/git-hooks/pre-commit .git/hooks/pre-commit
cp scripts/git-hooks/commit-msg .git/hooks/commit-msg
chmod +x .git/hooks/pre-commit .git/hooks/commit-msg
```

The pre-commit hook requires gitleaks to be installed. Repository-level configuration is in `.gitleaks.toml`.

### Shell Configuration

| File | Description | Docs |
|------|-------------|------|
| `scripts/bash/.bashrc` | Team-reusable Bash config for WSL/Linux with smart tool detection (fzf, eza, bat, zoxide) and graceful degradation | [docs](scripts/.docs/bash/bashrc.md) |
| `scripts/bash/.bash_profile` | Login shell startup | [docs](scripts/.docs/bash/bash-profile.md) |
| `scripts/bash/.bashrc.local` | Personal overrides — secrets, aliases, startup (gitignored, copied to `~` by bootstrap) | [docs](scripts/.docs/bash/bashrc-local.md) |
| `scripts/bash/.bashrc.local.example` | Template with placeholders for new users without an existing `.bashrc.local` | [docs](scripts/.docs/bash/bashrc-local.md) |

### Windows Sandbox

`scripts/powershell/sandbox/` contains a full provisioning pipeline for Windows Sandbox — installs packages via winget and Chocolatey, sets up Node.js and Angular CLI. Entry point: `setup-wsb.ps1`. See [docs](scripts/.docs/powershell/sandbox.md).

## Quick Start

### Bootstrapping a New WSL Distro

Run the bootstrap script directly from the Windows-mounted toolbox path on first launch:

```bash
bash /mnt/d/Repos/.local-dev-toolbox/scripts/bash/setup-distro.sh
```

This will:

1. **Symlink** `~/.bashrc` and `~/.bash_profile` to the toolbox versions — changes to the repo are reflected automatically in the shell.
2. **Copy** `.bashrc.local` from the toolbox to `~/.bashrc.local` (personal config with secrets, not symlinked). Falls back to `.bashrc.local.example` if no `.bashrc.local` exists.
3. **Install** all dev tools across 8 categories (core, cli, shell, languages, cloud, web, containers, powershell).
4. Set `DEV_TOOLBOX` to the toolbox bash scripts path, adding it to `PATH`.

After the bootstrap completes, reload the shell: `source ~/.bashrc`

### Other Commands

```bash
# Install only specific categories
bash ./scripts/bash/setup-distro.sh --only=core,cli,languages

# Only link dotfiles, skip tool installs
bash ./scripts/bash/setup-distro.sh --only=dotfiles

# Upgrade all tools
bash ./scripts/bash/setup-distro.sh --upgrade

# PowerShell — fetch/pull all matching repos
pwsh ./scripts/powershell/utils/_update-repos.ps1 -root-path D:\Repos --no-pull

# Bash — same operation on Linux/macOS
bash ./scripts/bash/_update-repos.sh --root-path ~/repos --verbose --parallel 4

# Generate release notes for the last 4 weeks
pwsh ./scripts/powershell/utils/git-history.ps1 -Period "last_4_weeks"
```

## Contributing

- Add scripts under `scripts/<area>/`.
- Add a matching documentation file in `scripts/.docs/<area>/<script-name>.md`.
