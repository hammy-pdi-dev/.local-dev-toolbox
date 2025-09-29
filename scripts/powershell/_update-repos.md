# _update-repos.ps1

A PowerShell script for efficiently managing multiple Git repositories in bulk operations.

## Overview

`_update-repos.ps1` scans a specified root directory for Git repositories with a configurable prefix and performs bulk operations like fetching, pulling, and status reporting. It's designed for developers managing multiple related repositories.

## Features

- **Bulk Git Operations**: Fetch and pull multiple repositories simultaneously
- **Smart Repository Detection**: Automatically finds repositories based on configurable naming patterns
- **Flexible Dirty Handling**: Skip or stash uncommitted changes before operations
- **Progress Tracking**: Real-time progress display with status indicators
- **Comprehensive Reporting**: Optional detailed summary with repository status

## Configuration

The script uses two main configuration variables:

- `$Script:DefaultRootPath` - Default directory to scan (default: `D:\Repos`)
- `$Script:ChildFolderPrefix` - Repository name prefix filter (default: `H`)

## Usage

### Common Examples
```powershell
# Update all repositories with detailed output
.\_update-repos.ps1 --verbose-branches

# Only fetch, don't pull
.\_update-repos.ps1 --no-pull

# Skip repositories with uncommitted changes
.\_update-repos.ps1 --skip-dirty

# Stash changes before updating
.\_update-repos.ps1 --stash-dirty

# Use rebase instead of merge
.\_update-repos.ps1 --use-rebase

# Scan different directory
.\_update-repos.ps1 /path/to/repos

# Fetch from all remotes
.\_update-repos.ps1 --fetch-all-remotes
```

## Parameters

### Primary Parameters

| Parameter | Alias | Description |
|-----------|-------|-------------|
| `-RootPath <path>` | `--root-path` | Directory to scan for repositories |
| `-NoPull` | `--no-pull` | Only fetch, don't pull changes |
| `-SkipDirty` | `--skip-dirty` | Skip repositories with uncommitted changes |
| `-StashDirty` | `--stash-dirty` | Stash uncommitted changes before updating |
| `-UseRebase` | `--use-rebase` | Use rebase instead of merge for pulls |
| `-FetchAllRemotes` | `--fetch-all`, `--fetch-all-remotes` | Fetch from all remotes, not just origin |
| `-VerboseBranches` | `--verbose-branches`, `--verbose`, `-v` | Show detailed output and summary table |

## Repository Detection

The script searches for:
1. **Immediate child directories** in the root path
2. **Directories matching the prefix** (e.g., `H*`)
3. **Containing a `.git` directory**


## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Invalid root path |
| 2 | Invalid command-line arguments |
| >0 | Number of repository failures (script continues) |

## Advanced Features

### Dirty Working Tree Handling

#### Skip Dirty (`--skip-dirty`)
- Repositories with uncommitted changes are skipped
- Useful for read-only operations or when changes should be preserved

#### Stash Dirty (`--stash-dirty`)
- Automatically stashes uncommitted changes before updating
- Attempts to restore stash after operations
- Reports conflicts if stash restoration fails

### Fetch Strategies

#### Origin Only (Default)
```bash
git fetch origin --prune
```

#### All Remotes (`--fetch-all-remotes`)
```bash
git fetch --all --prune
```

### Pull Strategies

#### Fast-Forward Only (Default)
```bash
git pull --ff-only origin <branch>
```

#### Rebase (`--use-rebase`)
```bash
git pull --rebase origin <branch>
```

## Requirements

- **PowerShell** 5.1 or later (cross-platform PowerShell Core recommended)
- **Git** command-line tools installed and in PATH
- **Network access** for remote operations (unless using `--no-pull`)
