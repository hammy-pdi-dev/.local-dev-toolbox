# _update-repos.sh

A Bash script for managing multiple Git repositories in bulk — fetch, pull, and report across dozens of repos in seconds. Cross-platform equivalent of `_update-repos.ps1` for macOS and Linux.

## Table of Contents

- [Overview](#overview)
- [Requirements](#requirements)
- [Configuration](#configuration)
- [Usage](#usage)
  - [Common Examples](#common-examples)
- [Parameters](#parameters)
- [Repository Detection](#repository-detection)
- [Behaviour](#behaviour)
  - [Dirty Working Tree Handling](#dirty-working-tree-handling)
  - [Fetch Strategies](#fetch-strategies)
  - [Pull Strategies](#pull-strategies)
  - [Parallel Processing](#parallel-processing)
  - [Verbose Output and Reporting](#verbose-output-and-reporting)
- [Exit Codes](#exit-codes)
- [Platform Notes](#platform-notes)

## Overview

`update-repos.sh` scans a root directory for Git repositories matching a configurable naming prefix, then fetches and pulls each one. By default it processes four repos concurrently using background subshells, with results printing as they complete.

When run with `--verbose`, a summary table and per-repo diffstat are shown at the end.

## Requirements

- **Bash** 4.0 or later (macOS ships with 3.2 — install Bash 5 via Homebrew: `brew install bash`)
- **Git** CLI installed and on PATH
- **Network access** for fetch/pull operations (unless using `--no-pull`)
- Standard POSIX utilities: `awk`, `sed`, `date`, `mktemp`

## Configuration

Two variables at the top of the script control which directories are scanned:

| Variable | Default | Description |
|----------|---------|-------------|
| `DEFAULT_ROOT_PATH` | `$HOME/repos` | Root directory to scan |
| `CHILD_FOLDER_PREFIX` | `Hydra` | Only process child folders whose name starts with this prefix |

Edit these directly in the script to match your environment.

## Usage

### Common Examples

```bash
# Update all repositories with detailed output
./_update-repos.sh --verbose

# Only fetch, skip pulling
./_update-repos.sh --no-pull

# Skip repos with uncommitted changes
./_update-repos.sh --skip-dirty

# Stash uncommitted changes, pull, then restore
./_update-repos.sh --stash-dirty

# Use rebase instead of fast-forward merge
./_update-repos.sh --use-rebase

# Scan a different directory
./_update-repos.sh --root-path ~/work/repos

# Limit to 2 concurrent workers
./_update-repos.sh --parallel 2

# Force sequential processing
./_update-repos.sh --parallel 1

# Positional root path (shorthand)
./_update-repos.sh ~/work/repos --verbose
```

## Parameters

| Parameter             | Alias                | Description                                                         |
| --------------------- | -------------------- | ------------------------------------------------------------------- |
| `--root-path <path>`  | first positional arg | Directory to scan for repositories                                  |
| `--no-pull`           |                      | Only fetch, don't pull changes                                      |
| `--skip-dirty`        |                      | Skip repositories with uncommitted changes                          |
| `--stash-dirty`       |                      | Stash changes before updating, restore afterwards                   |
| `--use-rebase`        |                      | Use `git pull --rebase` instead of `--ff-only`                      |
| `--fetch-all-remotes` | `--fetch-all`        | Fetch from all remotes, not just origin                             |
| `--verbose-branches`  | `--verbose`          | Show REPORT table and CHANGES diffstat after processing             |
| `--parallel <n>`      | `-p`                 | Number of concurrent workers (default: `4`, set `1` for sequential) |
| `--help`              |                      | Show usage information                                              |

All parameters support `--key=value` and `--key value` syntax.

## Repository Detection

The script discovers repositories by:

1. Listing immediate child directories under the root path matching `${CHILD_FOLDER_PREFIX}*`
2. Keeping only directories containing a `.git` folder

Nested repositories or repositories outside the root are not scanned.

## Behaviour

### Dirty Working Tree Handling

By default, repositories with uncommitted changes are still fetched and pulled. This can be changed:

**`--skip-dirty`** — Skips the repository entirely. Useful when you want to preserve local changes and avoid merge conflicts.

**`--stash-dirty`** — Stashes uncommitted changes before fetching/pulling, then pops the stash afterwards. If the pop causes conflicts, the status is reported and the stash remains applied. The stash message includes a timestamp (`WIP_YYYYMMDD-HHMMSS`) for identification.

### Fetch Strategies

The default is `git fetch origin --prune`, which fetches from the `origin` remote and cleans up stale remote-tracking branches.

With `--fetch-all-remotes`, this changes to `git fetch --all --prune` to fetch from every configured remote.

### Pull Strategies

The default is `git pull --ff-only origin <branch>`, which only applies changes if they can be fast-forwarded.

With `--use-rebase`, this changes to `git pull --rebase origin <branch>`, which replays local commits on top of the fetched changes.

Both modes include `--stat` to capture file-change summaries for the verbose diffstat output.

### Parallel Processing

Repositories are processed concurrently by default using 4 background subshells. Each worker runs the full fetch-pull cycle for one repo independently.

The `--parallel <n>` parameter controls the number of concurrent workers:
- Default (`4`) — good balance for most networks
- `--parallel 1` — forces sequential processing (ordered output)
- Higher values may help on fast networks but can overwhelm credential prompts or rate limits

During parallel processing, repos print their status line as they finish, so the order is non-deterministic. The final REPORT table is always sorted alphabetically regardless of completion order.

### Verbose Output and Reporting

When `--verbose` is passed, a summary is shown after all repos are processed:

**REPORT table** — one row per repo with columns: Name, Branch, Clean (check/cross), Pulled (check/cross), and Status (shown only when not all repos are up-to-date).

**CHANGES section** — appears below the table when any repos had file changes. Shows the `git diff --stat` output for each repo that was fast-forwarded or rebased.

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Invalid root path |
| 2 | Invalid command-line arguments |

## Platform Notes

### macOS

- macOS ships with Bash 3.2 which does not support all features used by this script (e.g. `${BASH_REMATCH}` in certain contexts). Install Bash 5 via Homebrew: `brew install bash`.
- The `date` command on macOS does not support `%N` (nanoseconds). The script detects this and falls back to second-precision timing. For millisecond precision, install GNU coreutils: `brew install coreutils`.
- Unicode symbols require a terminal with UTF-8 support (Terminal.app and iTerm2 both work).

### Linux

- Works out of the box on any modern distribution with Bash 4+.
- ANSI colour codes work in all common terminal emulators.

### Differences from _update-repos.ps1

| Feature | PowerShell | Bash |
|---------|-----------|------|
| Parallelism | RunspacePool | Background subshells |
| Progress bar | Write-Progress | Not available (prints lines as repos complete) |
| Result passing | PSCustomObject / Hashtable | Pipe-delimited string via temp files |
| Timing precision | Stopwatch (sub-millisecond) | Epoch milliseconds (or seconds on macOS) |
| Parameters | Identical | Identical (plus `--help`) |
