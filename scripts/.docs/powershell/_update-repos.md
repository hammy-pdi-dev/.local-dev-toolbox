# _update-repos.ps1

A PowerShell script for managing multiple Git repositories in bulk — fetch, pull, and report across dozens of repos in seconds.

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
- [Design Decisions](#design-decisions)
  - [Why RunspacePool Over ForEach-Object -Parallel](#why-runspacepool-over-foreach-object--parallel)
  - [Self-Contained Scriptblock](#self-contained-scriptblock)
  - [Hashtable Return From Runspaces](#hashtable-return-from-runspaces)
  - [Optimised Git Call Chain](#optimised-git-call-chain)
  - [Unicode via Char Escapes](#unicode-via-char-escapes)
  - [ANSI Escape Codes for Colour](#ansi-escape-codes-for-colour)

## Overview

`_update-repos.ps1` scans a root directory for Git repositories matching a configurable naming prefix, then fetches and pulls each one. By default it processes four repos concurrently using a `RunspacePool`, bringing wall time for ~21 repos from ~35 seconds down to ~10 seconds.

Results print as they complete, with a `Write-Progress` bar tracking overall progress. When run with `--verbose`, a summary table and per-repo diffstat are shown at the end.

## Requirements

- **PowerShell** 5.1 or later (PowerShell 7+ also supported)
- **Git** CLI installed and on PATH
- **Network access** for fetch/pull operations (unless using `--no-pull`)

## Configuration

Two script-level variables control which directories are scanned:

- `$Script:DefaultRootPath` — root directory to scan (default: `D:\Repos`)
- `$Script:ChildFolderPrefix` — only process child folders whose name starts with this prefix (default: `Hydra`)

Edit these directly in the script to match your environment.

## Usage

### Common Examples

```powershell
# Update all repositories with detailed output
.\_update-repos.ps1 --verbose

# Only fetch, skip pulling
.\_update-repos.ps1 --no-pull

# Skip repos with uncommitted changes
.\_update-repos.ps1 --skip-dirty

# Stash uncommitted changes, pull, then restore
.\_update-repos.ps1 --stash-dirty

# Use rebase instead of fast-forward merge
.\_update-repos.ps1 --use-rebase

# Scan a different directory
.\_update-repos.ps1 --root-path C:\Work\Repos

# Limit to 2 concurrent workers
.\_update-repos.ps1 --parallel 2

# Force sequential processing (original behaviour)
.\_update-repos.ps1 --parallel 1
```

## Parameters

| Parameter | Alias | Description |
|-----------|-------|-------------|
| `--root-path <path>` | first positional arg | Directory to scan for repositories |
| `--no-pull` | | Only fetch, don't pull changes |
| `--skip-dirty` | | Skip repositories with uncommitted changes |
| `--stash-dirty` | | Stash changes before updating, restore afterwards |
| `--use-rebase` | | Use `git pull --rebase` instead of `--ff-only` |
| `--fetch-all-remotes` | `--fetch-all` | Fetch from all remotes, not just origin |
| `--verbose-branches` | `--verbose` | Show REPORT table and CHANGES diffstat after processing |
| `--parallel <n>` | `-p` | Number of concurrent workers (default: `4`, set `1` for sequential) |

## Repository Detection

The script discovers repositories by:

1. Listing immediate child directories under the root path
2. Filtering to those whose name starts with `$Script:ChildFolderPrefix`
3. Keeping only directories containing a `.git` folder

Nested repositories or repositories outside the root are not scanned.

## Behaviour

### Dirty Working Tree Handling

By default, repositories with uncommitted changes are still fetched and pulled. This can be changed:

**`--skip-dirty`** — Skips the repository entirely. Useful when you want to preserve local changes and avoid merge conflicts.

**`--stash-dirty`** — Stashes uncommitted changes before fetching/pulling, then pops the stash afterwards. If the pop causes conflicts, the status is reported and the stash remains applied (not dropped). The stash message includes a timestamp (`WIP_20260326-143000`) for identification.

### Fetch Strategies

The default is `git fetch origin --prune`, which fetches from the `origin` remote and cleans up stale remote-tracking branches.

With `--fetch-all-remotes`, this changes to `git fetch --all --prune` to fetch from every configured remote.

### Pull Strategies

The default is `git pull --ff-only origin <branch>`, which only applies changes if they can be fast-forwarded. This avoids creating merge commits.

With `--use-rebase`, this changes to `git pull --rebase origin <branch>`, which replays local commits on top of the fetched changes instead of merging.

Both modes include `--stat` to capture file-change summaries for the verbose diffstat output.

### Parallel Processing

Repositories are processed concurrently by default using 4 workers. Each worker runs the full fetch-pull cycle for one repo independently.

The `--parallel <n>` parameter controls the number of concurrent workers:
- Default (`4`) — good balance for most networks and credential managers
- `--parallel 1` — forces sequential processing, identical to the original behaviour (ordered output, no progress bar)
- Higher values may help on fast networks but can overwhelm credential prompts or rate limits

During parallel processing, a `Write-Progress` bar shows overall completion (`[12/21] completed`). Repos print their status line as they finish, so the order is non-deterministic. The final REPORT table is always sorted alphabetically regardless of completion order.

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

## Design Decisions

This section documents the "why" behind non-obvious technical choices. If you're modifying the script, read this first.

### Why RunspacePool Over ForEach-Object -Parallel

`ForEach-Object -Parallel` is cleaner syntax but only exists in PowerShell 7+. The script needs to support PowerShell 5.1 (Windows PowerShell), which is still the default on most Windows machines. `RunspacePool` is available in both 5.1 and 7+ through the `System.Management.Automation.Runspaces` namespace, so a single code path covers both runtimes without conditional branching or external modules.

The alternative was `Start-Job`, but jobs have much higher overhead (each one spawns a new process), making them slower than sequential processing for small-to-medium repo counts.

### Self-Contained Scriptblock

The scriptblock passed to each runspace (`New-RepoProcessingScriptBlock`) must be entirely self-contained. PowerShell runspaces do not inherit script-scoped variables, functions, or class definitions from the parent session. This means:

- All per-repo logic (status check, fetch, pull, stash handling) is inlined inside the scriptblock
- The `RepositoryStatus` and `PullStatus` class constants are replaced with string literals (`'Fast-forwarded'`, `'Pull failed'`, etc.)
- Regex patterns (`GitErrorPattern`, `StashConflictPattern`) are passed in as string parameters rather than referencing `$Script:RegexPatterns`
- No `Write-Host` or `Write-Message` calls — all console output happens on the main thread after polling

This duplicates logic from `Invoke-SingleRepositoryProcessing`, which still exists for the sequential path (`--parallel 1`). The duplication is intentional: sharing code between the two paths would require injecting function definitions into runspaces via `InitialSessionState`, which adds complexity for no real benefit. If the per-repo logic changes, both places need updating — but this is a single file and the functions are adjacent.

### Hashtable Return From Runspaces

The scriptblock returns a `[hashtable]` rather than a `[PSCustomObject]`. Custom objects created inside a runspace can lose type fidelity when marshalled back to the calling thread — properties may be missing or typed differently. Hashtables survive the boundary reliably. The main thread converts each hashtable into a `[PSCustomObject]` after `EndInvoke()` so downstream functions (`Write-RepositoryProgress`, `Write-Summary`) work unchanged.

### Optimised Git Call Chain

Each repository originally required 7 git subprocess calls. This was reduced to 4 by eliminating redundant checks:

| Before | After | Rationale |
|--------|-------|-----------|
| `git rev-parse --git-dir` | Removed | `Get-Repositories` already verified `.git` exists, and `git remote` (the first call) would fail on a non-git directory |
| `git symbolic-ref --short HEAD` + `git status --porcelain` | Combined into `git status --porcelain -b` | A single call returns both the branch name (first line: `## branch...origin/branch`) and dirty state (any subsequent lines) |
| `git rev-parse --verify origin/$branch` | Removed | If the remote branch doesn't exist, `git pull` fails with `fatal: couldn't find remote ref` which is already caught by the error-detection regex |

The one exception is detached HEAD: `git status --porcelain -b` reports `## HEAD (no branch)` without a SHA, so a single extra `git rev-parse --short HEAD` call is made in that case to show the short hash. Detached HEAD is rare in typical workflows, so this adds negligible overhead.

### Unicode via Char Escapes

Status symbols (checkmarks, crosses, emoji) are defined using `[char]0xNNNN` expressions rather than literal Unicode characters in the source. This is because Windows PowerShell 5.1 reads `.ps1` files as ANSI (Windows-1252) by default unless the file has a UTF-8 BOM. Literal Unicode characters would be garbled at parse time. Using char escapes generates the correct code points at runtime regardless of file encoding.

The script also sets `[Console]::OutputEncoding` and `$OutputEncoding` to UTF-8 at startup to ensure the console renders these characters correctly.

### ANSI Escape Codes for Colour

The script builds ANSI escape sequences manually (`$([char]27)[32m...`) rather than using `Write-Host -ForegroundColor`. This gives control over colour within interpolated strings (e.g., colouring just the branch name inside a progress line) and works consistently across Windows Terminal, VS Code terminal, and PowerShell 7. The trade-off is that legacy PowerShell ISE won't render colours, but ISE is effectively deprecated.
