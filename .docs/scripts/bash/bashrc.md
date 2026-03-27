# .bashrc

A team-reusable Bash configuration for WSL (and native Linux). It provides a well-organised shell environment with smart tool detection, useful helper functions, and sensible alias defaults — without hardcoding secrets or personal paths.

## Table of Contents

- [Overview](#overview)
- [Installation](#installation)
- [Structure](#structure)
- [Shell Options](#shell-options)
- [History](#history)
- [Environment](#environment)
- [Functions](#functions)
  - [Utility Functions](#utility-functions)
  - [Git Functions](#git-functions)
  - [FZF Functions](#fzf-functions)
- [Aliases](#aliases)
  - [Navigation](#navigation)
  - [System](#system)
  - [File Operations](#file-operations)
  - [Listing](#listing)
  - [Text / IO](#text--io)
  - [Archives](#archives)
  - [Monitoring](#monitoring)
  - [Package Management](#package-management)
  - [Git](#git)
  - [Docker](#docker)
  - [Networking](#networking)
- [Keybindings](#keybindings)
- [Prompt and Enhancements](#prompt-and-enhancements)
- [External Integrations](#external-integrations)
- [Local Overrides](#local-overrides)
- [Optional Tools](#optional-tools)

## Overview

The `.bashrc` is designed around three principles:

1. **No secrets in version control** -- API tokens, PATs, and personal paths live in `~/.bashrc.local` (gitignored).
2. **Graceful degradation** -- every optional tool (`eza`, `bat`, `fzf`, `zoxide`, etc.) is detected at runtime. If it's not installed, the config falls back to standard utilities.
3. **Distro-aware** -- package management aliases adapt to Debian, Red Hat, and Arch families automatically.

## Installation

```bash
# Copy to home directory
cp scripts/bash/.bashrc ~/.bashrc
cp scripts/bash/.bash_profile ~/.bash_profile

# Create your personal overrides from the template
cp scripts/bash/.bashrc.local.example ~/.bashrc.local
# Edit ~/.bashrc.local with your secrets and personal aliases

# Reload
source ~/.bashrc
```

## Structure

The file is organised into clearly marked sections, loaded in this order:

| Section | Purpose |
|---------|---------|
| **INIT** | System defaults, bash-completion, system info (fastfetch/neofetch) |
| **SHELL OPTIONS** | `shopt` flags, readline bindings, terminal settings |
| **HISTORY** | History size, format, deduplication, write-on-command |
| **ENV** | XDG dirs, editor, colour, man pager, clipboard, PATH, NVM, FZF |
| **FUNCTIONS** | Reusable shell functions (see below) |
| **ALIASES** | Grouped alias definitions (see below) |
| **KEYBINDINGS** | Custom key bindings (Ctrl+F for zoxide) |
| **PROMPT / ENHANCEMENTS** | Starship prompt, zoxide init |
| **EXTERNAL** | Cargo, Deno, and other tool environments |
| **LOCAL OVERRIDES** | Sources `~/.bashrc.local` for personal config and secrets |

## Shell Options

| Option | Effect |
|--------|--------|
| `checkwinsize` | Update `LINES`/`COLUMNS` after each command |
| `histappend` | Append to history file instead of overwriting |
| `globstar` | Enable `**` recursive glob pattern |
| `bell-style none` | Silence the terminal bell |
| `completion-ignore-case` | Case-insensitive tab completion |
| `show-all-if-ambiguous` | Show all completions on first tab press |
| `stty -ixon` | Disable Ctrl+S/Ctrl+Q flow control (frees Ctrl+S for search) |

## History

| Setting | Value | Purpose |
|---------|-------|---------|
| `HISTSIZE` | 10,000 | Commands kept in memory |
| `HISTFILESIZE` | 20,000 | Lines kept in `~/.bash_history` |
| `HISTTIMEFORMAT` | `%F %T ` | Timestamps on every entry |
| `HISTCONTROL` | `erasedups:ignoredups:ignorespace` | No duplicates; space-prefixed commands are private |
| `PROMPT_COMMAND` | `history -a` | Write history after every command (no lost history on crash) |

## Environment

- **XDG Base Directories** -- sets `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME`, `XDG_CACHE_HOME` with sensible defaults.
- **Editor** -- defaults to `vim`; override with `export EDITOR=nvim` in `~/.bashrc.local`.
- **Coloured man pages** -- LESS terminal capabilities set for bold/underline colours. If `bat` is installed, it's used as the man pager.
- **Clipboard** -- detects WSL (`clip.exe`), Wayland (`wl-copy`), or X11 (`xclip`) and creates `copy`/`paste` aliases.
- **PATH** -- prepends `~/.local/bin` and `~/.cargo/bin`.
- **NVM** -- loads Node Version Manager if installed.
- **FZF** -- loads fuzzy finder with `fd` as the default file finder.

## Functions

### Utility Functions

| Function | Usage | Description |
|----------|-------|-------------|
| `cd` | `cd /path` | Overridden to auto-list directory contents after changing directory |
| `prompt_continue` | `prompt_continue "Continue?" && do_thing` | Interactive yes/no confirmation prompt |
| `extract` | `extract file.tar.gz file2.zip` | Extract any common archive format (tar, zip, 7z, rar, etc.) |
| `mkcd` | `mkcd my-project` | Create a directory and cd into it in one step |
| `bak` | `bak config.yml` | Create a `.bak` copy of a file or directory |
| `up` | `up 3` | Navigate up N parent directories |
| `search_files` | `search_files "TODO"` | Search file contents recursively using ripgrep or grep |
| `myip` | `myip` | Show internal (LAN) and external (public) IP addresses |
| `cheat` | `cheat curl` or `cheat python/lambda` | Look up a command cheatsheet from cht.sh |
| `get_distro` | (internal) | Detect Linux distro family for package management aliases |
| `_list_dir` | (internal) | List directory with best available tool (eza > exa > lsd > ls) |

### Git Functions

| Function | Usage | Description |
|----------|-------|-------------|
| `gcom` | `gcom "fix typo"` | Stage all files and commit with a message |
| `lazy` | `lazy "quick fix"` | Stage all, commit, and push in one command |
| `gclean` | `gclean` | Prune remote refs and delete local branches already merged |

### FZF Functions

These are only available when `fzf` and `fd` are installed.

| Function | Usage | Description |
|----------|-------|-------------|
| `fe` | `fe [query]` | Fuzzy-find a file and open it in your editor |
| `fcd` | `fcd [query]` | Fuzzy-find a directory and cd into it |
| `fkill` | `fkill [signal]` | Fuzzy-find a running process and kill it |
| `fshow` | `fshow [query]` | Fuzzy-find a file and preview it with bat syntax highlighting |

## Aliases

### Navigation

| Alias | Expands to | Description |
|-------|-----------|-------------|
| `..` | `cd ..` | Up one level |
| `...` | `cd ../..` | Up two levels |
| `....` | `cd ../../..` | Up three levels |
| `~` | `cd ~` | Home directory |

### System

| Alias | Expands to | Description |
|-------|-----------|-------------|
| `c` / `cls` | `clear` | Clear the terminal |
| `h` | `history` | Show command history |
| `j` | `jobs -l` | List background jobs with PIDs |
| `path` | (special) | Print PATH entries, one per line |
| `now` | `date +"%T"` | Current time |
| `nowdate` | `date +"%d-%m-%Y"` | Current date |
| `reload` | `source ~/.bashrc` | Reload bashrc without restarting |
| `please` | `sudo $(fc -ln -1)` | Re-run last command with sudo |
| `pathadd` | (special) | Add current directory to PATH |

### File Operations

| Alias | Expands to | Description |
|-------|-----------|-------------|
| `cp` | `cp -i` | Confirm before overwriting |
| `mv` | `mv -i` | Confirm before overwriting |
| `rm` | `rm -i` or `trash` | Confirm before deleting (uses trash-cli if available) |
| `mkdir` | `mkdir -pv` | Create parent directories, show what was made |

### Listing

Auto-detects the best tool available (eza > lsd > plain ls).

| Alias | Description |
|-------|-------------|
| `ls` | All files, one per line, with icons |
| `l` | Short listing (no hidden files) |
| `la` | All files including hidden |
| `ll` | Long format with timestamps |
| `lt` | Tree view (2 levels deep) |
| `dir` | Detailed listing sorted by time |
| `tree` | Colourised recursive tree |

### Text / IO

| Alias | Description |
|-------|-------------|
| `grep` | Colourised, skips `.git`, `node_modules`, `vendor`, `build`, `dist` |
| `cat` | Uses `bat` for syntax highlighting (if installed) |

### Archives

| Alias | Description |
|-------|-------------|
| `untar` | Extract a tarball |
| `targz` | Create a `.tar.gz` archive |

### Monitoring

| Alias | Expands to | Description |
|-------|-----------|-------------|
| `df` | `df -h` | Disk usage (human-readable) |
| `du` | `du -h` | Directory sizes (human-readable) |
| `free` | `free -h` | Memory usage (human-readable) |
| `ps` | `ps auxf` | All processes as a tree |
| `psg` | `ps aux \| grep` | Search running processes |
| `top` | `htop` | Interactive process viewer (if htop installed) |
| `ports` | `netstat -tulanp` or `ss -tulpen` | Show listening ports |

### Package Management

Distro-aware aliases that adapt automatically:

| Alias | Debian/Ubuntu | Red Hat/Fedora | Arch |
|-------|--------------|----------------|------|
| `install` | `sudo apt install` | `sudo dnf install` | `sudo pacman -S` |
| `update` | `sudo apt update && sudo apt full-upgrade` | `sudo dnf upgrade --refresh` | `sudo pacman -Syu` |
| `search` | `apt search` | `dnf search` | `pacman -Ss` |
| `remove` | `sudo apt remove && sudo apt autoremove` | `sudo dnf remove && sudo dnf autoremove` | `sudo pacman -R` |

### Git

| Alias | Expands to | Description |
|-------|-----------|-------------|
| `g` | `git` | Shorthand |
| `gs` | `git status` | Working tree status |
| `gst` | `git status -sb` | Short status with branch |
| `ga` | `git add` | Stage files |
| `gc` | `git commit` | Commit staged changes |
| `gp` | `git push` | Push to remote |
| `gl` | `git log --oneline` | Compact log |
| `gd` | `git diff` | Show unstaged changes |
| `gco` | `git checkout` | Switch branch or restore files |
| `gb` | `git branch --all` | List all branches |
| `ggraph` | `git log --graph ...` | Visual branch graph |
| `gamend` | `git commit --amend --no-edit` | Amend last commit (keep message) |
| `gca` | `git commit --amend` | Amend last commit (edit message) |
| `gcp` | `git cherry-pick` | Apply a commit from another branch |
| `gprune` | `git fetch --prune` | Remove stale remote-tracking refs |
| `guncommit` | `git reset --soft HEAD~1` | Undo last commit, keep changes staged |

### Docker

| Alias | Expands to | Description |
|-------|-----------|-------------|
| `d` | `docker` | Shorthand |
| `dc` | `docker compose` | Shorthand for compose |
| `dps` | `docker ps` | List running containers |
| `di` | `docker images` | List local images |
| `dclean` | `docker system prune -af` | Remove all unused images and containers |
| `dcu` | `docker compose up -d` | Start services in background |
| `dcd` | `docker compose down` | Stop and remove services |
| `dcb` | `docker compose build` | Build service images |
| `dcl` | `docker compose logs -f` | Follow service logs |
| `dexec` | `docker exec -it` | Exec into a running container |

### Networking

| Alias | Expands to | Description |
|-------|-----------|-------------|
| `ping` | `ping -c 5` | Limit to 5 pings |
| `wget` | `wget -c` | Resume partial downloads |
| `curl` | `curl -L` | Follow redirects |
| `ippublic` | `curl -s https://ifconfig.me` | Show public IP address |
| `serve` | `python3 -m http.server 8000` | Quick local HTTP server on port 8000 |

## Keybindings

| Key | Action |
|-----|--------|
| `Ctrl+F` | Invoke zoxide interactive (`zi`) for fuzzy directory jumping |

## Prompt and Enhancements

- **Starship** -- cross-shell customisable prompt. Config read from `$XDG_CONFIG_HOME/starship/starship.toml`.
- **Zoxide** -- smarter `cd` that learns your most-used directories. Use `z <partial>` to jump, or `Ctrl+F` for interactive selection.

## External Integrations

The following tool environments are sourced if present:

- `~/.local/bin/env` -- user-local environment (e.g. uv, rye)
- `~/.cargo/env` -- Rust toolchain
- `~/.deno/env` -- Deno runtime
- `~/.bash_aliases` -- separate alias file (if maintained)
- Deno bash completion

## Local Overrides

The file sources `~/.bashrc.local` at the very end, so anything defined there takes precedence. Use this for:

- API tokens and secrets (AWS, Azure DevOps, Atlassian, etc.)
- Machine-specific aliases and paths
- Tool configuration that varies per user
- Startup commands (e.g. `cdfs`, `git status`)

A template is provided at `scripts/bash/.bashrc.local.example`.

## Optional Tools

The bashrc works with plain coreutils but is enhanced by these tools when installed:

| Tool | Used for | Install |
|------|----------|---------|
| [eza](https://github.com/eza-community/eza) | Enhanced `ls` with icons and git status | `cargo install eza` |
| [bat](https://github.com/sharkdp/bat) | Syntax-highlighted `cat` and man pager | `apt install bat` |
| [fd](https://github.com/sharkdp/fd) | Fast file finder (used by FZF functions) | `apt install fd-find` |
| [fzf](https://github.com/junegunn/fzf) | Fuzzy finder for files, dirs, processes | `apt install fzf` |
| [ripgrep](https://github.com/BurntSushi/ripgrep) | Fast recursive search | `apt install ripgrep` |
| [zoxide](https://github.com/ajeetdsouza/zoxide) | Smarter cd with directory frecency | `cargo install zoxide` |
| [starship](https://starship.rs) | Cross-shell prompt | `curl -sS https://starship.rs/install.sh \| sh` |
| [lsd](https://github.com/lsd-rs/lsd) | Alternative enhanced `ls` | `cargo install lsd` |
| [htop](https://htop.dev) | Interactive process viewer | `apt install htop` |
| [trash-cli](https://github.com/andreafrancia/trash-cli) | Safe `rm` replacement (moves to trash) | `apt install trash-cli` |
| [fastfetch](https://github.com/fastfetch-cli/fastfetch) | System info on shell start | `apt install fastfetch` |
