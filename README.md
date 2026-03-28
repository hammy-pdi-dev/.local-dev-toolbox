# .local-dev-toolbox

Cross-platform developer automation and environment setup toolkit. Bash and PowerShell scripts for bulk Git repository management, shell configuration, Git hooks, and Windows Sandbox provisioning.

## Repository Structure

```
scripts/
├── bash/               Bash scripts and dotfiles (.bashrc, .bash_profile, .zshrc)
├── powershell/
│   ├── utils/          Repository management, git history, timestamps
│   └── sandbox/        Windows Sandbox setup automation
├── batch/              Windows batch backup scripts
└── git-hooks/          Git hook scripts
```

Detailed documentation for each script lives in `.docs/scripts/`.

## Scripts

### Repository Management

| Script | Platform | Description | Docs |
|--------|----------|-------------|------|
| `scripts/powershell/utils/_update-repos.ps1` | Windows | Batch fetch/pull for multiple Git repositories with RunspacePool parallelism | [docs](.docs/scripts/powershell/_update-repos.md) |
| `scripts/bash/_update-repos.sh` | Linux/macOS | Bash equivalent using background subshells for parallel processing | [docs](.docs/scripts/bash/_update-repos.md) |

Both scripts scan a root directory for child folders matching a configurable prefix, then fetch and pull each repo in parallel (default: 4 workers). Supports `--skip-dirty`, `--stash-dirty`, `--use-rebase`, `--fetch-all-remotes`, and `--verbose`.

### Environment Setup

| Script | Platform | Description | Docs |
|--------|----------|-------------|------|
| `scripts/bash/setup-distro.sh` | Linux/macOS | Idempotent dev environment bootstrap — installs dev tools, CLI utilities, shell enhancements, language runtimes, cloud CLIs, web server tooling, containers, and PowerShell | [docs](.docs/scripts/bash/setup-distro.md) |
| `scripts/powershell/wsl/migrate-wsl-distro.ps1` | Windows | Migrate a WSL distribution to a new location with export/import | [docs](.docs/scripts/powershell/wsl/migrate-wsl-distro.md) |

### Utilities

| Script | Platform | Description | Docs |
|--------|----------|-------------|------|
| `scripts/powershell/utils/git-history.ps1` | Windows | Generate formatted release notes from Git commit history for specified time periods | [docs](.docs/scripts/powershell/git-history.md) |
| `scripts/powershell/utils/fix-timestamps.ps1` | Windows | Batch timestamp updates for build artifacts | [docs](.docs/scripts/powershell/fix-timestamps.md) |
| `scripts/bash/fc-rsync.sh` | Linux/macOS | Backup and sync repositories using rsync | [docs](.docs/scripts/bash/fc-rsync.md) |
| `scripts/batch/_backup_fc-repo.bat` | Windows | Repository backup via xcopy | — |

### Git Hooks

| Script | Description | Docs |
|--------|-------------|------|
| `scripts/git-hooks/pre-commit` | Runs [gitleaks](https://github.com/gitleaks/gitleaks) against staged changes to prevent secrets from being committed | [docs](.docs/scripts/git-hooks/pre-commit.md) |
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
| `scripts/bash/.bashrc` | Team-reusable Bash config for WSL/Linux with smart tool detection (fzf, eza, bat, zoxide) and graceful degradation | [docs](.docs/scripts/bash/bashrc.md) |
| `scripts/bash/.bash_profile` | Login shell startup | [docs](.docs/scripts/bash/bash-profile.md) |
| `scripts/bash/.bashrc.local` | Personal overrides template (gitignored) | [docs](.docs/scripts/bash/bashrc-local.md) |

### Windows Sandbox

`scripts/powershell/sandbox/` contains a full provisioning pipeline for Windows Sandbox — installs packages via winget and Chocolatey, sets up Node.js and Angular CLI. Entry point: `setup-wsb.ps1`. See [docs](.docs/scripts/powershell/sandbox.md).

## Quick Start

1. Clone this repository.
2. Adjust variables (like `$Script:ChildFolderPrefix`) in scripts as needed.
3. Run a script:

```bash
# Bootstrap a dev environment (macOS or Debian/Ubuntu)
bash ./scripts/bash/setup-distro.sh

# Install only specific categories
bash ./scripts/bash/setup-distro.sh --only=core,cli,languages

# PowerShell — fetch/pull all matching repos
pwsh ./scripts/powershell/utils/_update-repos.ps1 -root-path D:\Repos --no-pull

# Bash — same operation on Linux/macOS
bash ./scripts/bash/_update-repos.sh --root-path ~/repos --verbose --parallel 4

# Generate release notes for the last 4 weeks
pwsh ./scripts/powershell/utils/git-history.ps1 -Period "last_4_weeks"
```

## Contributing

- Add scripts under `scripts/<area>/`.
- Add a matching documentation file in `.docs/scripts/<area>/<script-name>.md`.
