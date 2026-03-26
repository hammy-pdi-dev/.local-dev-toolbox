# _update-repos.ps1

A PowerShell script for efficiently managing multiple Git repositories in bulk operations.

## Overview

`_update-repos.ps1` scans a specified root directory for Git repositories with a configurable prefix and performs bulk operations like fetching, pulling, and status reporting. It's designed for developers managing multiple related repositories.

## Features

- **Bulk Git Operations**: Fetch and pull multiple repositories simultaneously
- **Parallel Processing**: Concurrent repository updates via RunspacePool (PS 5.1 and 7+)
- **Smart Repository Detection**: Automatically finds repositories based on configurable naming patterns
- **Flexible Dirty Handling**: Skip or stash uncommitted changes before operations
- **Progress Tracking**: Real-time progress bar with per-repo completion output
- **Comprehensive Reporting**: Optional detailed summary with repository status and diffstat

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

# Limit parallel workers
.\_update-repos.ps1 --parallel 2

# Force sequential processing
.\_update-repos.ps1 --parallel 1
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
| `-Parallel <n>` | `--parallel`, `-p` | Number of concurrent workers (default: 4, use 1 for sequential) |

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

### Parallel Processing

Repositories are processed concurrently using a `RunspacePool`, which is available in both PowerShell 5.1 and 7+. The default concurrency is 4 workers, configurable via `--parallel <n>`.

Set `--parallel 1` to force sequential processing (identical behaviour to the original script).

## Requirements

- **PowerShell** 5.1 or later (cross-platform PowerShell Core recommended)
- **Git** command-line tools installed and in PATH
- **Network access** for remote operations (unless using `--no-pull`)

---

## Performance Design Spec

### Problem

The script processes repositories sequentially. Each repo requires multiple git subprocess calls, dominated by network I/O (`git fetch` + `git pull`). For 21 repos this takes ~35 seconds. The goal is to reduce wall time to ~8-12 seconds.

### Approach

Two phases applied in order:

1. **Phase B** - Reduce git subprocess calls per repo (from 7 to 4)
2. **Phase A** - Parallelise repo processing via RunspacePool

### Phase B: Reduce Git Subprocess Calls

#### Current call chain per repo (standard path, no stashing)

| # | Call | Purpose |
|---|------|---------|
| 1 | `git remote` | Check origin exists |
| 2 | `git rev-parse --git-dir` | Verify it's a git repo |
| 3 | `git symbolic-ref --short HEAD` | Get branch name |
| 4 | `git status --porcelain` | Check dirty state |
| 5 | `git fetch origin --prune` | Fetch updates |
| 6 | `git rev-parse --verify origin/$branch` | Verify remote branch exists |
| 7 | `git pull --ff-only --stat origin $branch` | Pull updates |

#### Reductions

- **Remove call #2** (`rev-parse --git-dir`): `Get-Repositories` already verified `.git` exists via `Test-Path`, and call #1 (`git remote`) would fail if it wasn't a git repo. Triple-checked for no reason.
- **Remove call #6** (`rev-parse --verify origin/$branch`): If the remote branch doesn't exist, `git pull` (call #7) will fail with a clear error. Pull failures are already handled. Let the pull itself be the check.
- **Combine calls #3 and #4** into a single `git status --porcelain --branch`, which returns the branch name on the first line and dirty state from remaining lines.

#### Optimised call chain (4 calls)

| # | Call | Purpose |
|---|------|---------|
| 1 | `git remote` | Check origin exists |
| 2 | `git status --porcelain --branch` | Branch name + dirty state in one call |
| 3 | `git fetch origin --prune` | Fetch updates |
| 4 | `git pull --ff-only --stat origin $branch` | Pull updates |

#### Parsing `git status --porcelain --branch`

The first line of `git status --porcelain -b` has the format:
```
## branch...origin/branch [ahead N, behind M]
```

- Branch name: extract text between `## ` and `...` (or end of line if no tracking)
- Detached HEAD: line reads `## HEAD (no branch)` or `## (detached)`
- Dirty state: any output lines after the first line indicate uncommitted changes

### Phase A: Parallel Processing via RunspacePool

#### Architecture

```
Main thread                          RunspacePool (N workers)
-----------                          ------------------------
Create pool (throttle limit)
For each repo:
  Submit scriptblock to pool -------> Runspace executes:
                                        git remote
Polling loop:                           git status --porcelain -b
  Check handle.IsCompleted              git fetch
  Update Write-Progress bar             git pull --stat
  Collect completed results <--------- Return result object
  Print per-repo progress line

Dispose pool
Write-Summary / CHANGES
```

#### RunspacePool details

- **API**: `[System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool()`
- **Compatibility**: Works identically on PowerShell 5.1 and 7+
- **Throttle limit**: `[Math]::Min($repos.Count, $Parallel)` where `$Parallel` defaults to 4
- **Scriptblock**: Must be self-contained. Script-scoped functions, classes, and variables are not available inside runspaces.

#### Passing context into runspaces

The following must be passed into each runspace as parameters to the scriptblock:

- Repository path (`$path`)
- Processing flags (`$skipDirty`, `$stashDirty`, `$noPull`, `$useRebase`, `$fetchAllRemotes`)
- Regex patterns (the raw pattern strings, not the `$Script:RegexPatterns` hashtable)
- Status string constants (the values from `RepositoryStatus` and `PullStatus` classes)

The scriptblock contains the full per-repo processing logic (equivalent to `Invoke-SingleRepositoryProcessing`) inlined, returning a `[hashtable]` result (not `[PSCustomObject]`, as custom objects from runspaces can lose type fidelity).

#### Main thread polling loop

```powershell
while ($completedCount -lt $totalRepos) {
    for each ($job in $pendingJobs) {
        if ($job.Handle.IsCompleted) {
            $result = $job.PowerShell.EndInvoke($job.Handle)
            # Print per-repo progress line
            # Add to results list
            $completedCount++
        }
    }
    Write-Progress -Activity "Updating repositories" `
                   -Status "[$completedCount/$totalRepos] completed" `
                   -PercentComplete (($completedCount / $totalRepos) * 100)
    Start-Sleep -Milliseconds 100
}
Write-Progress -Activity "Updating repositories" -Completed
```

- Repos print as they complete (non-deterministic order)
- Progress bar updates every 100ms
- Final REPORT table is sorted by name regardless of completion order

#### Error isolation

- Each runspace is independent. A git auth error, network timeout, or unexpected failure in one repo does not affect others.
- The scriptblock wraps all git operations in try/catch and returns a result hashtable with a status field indicating success or failure.
- The main thread collects all results and reports failures in the summary, same as today.

#### Resource cleanup

- Each `[PowerShell]` instance is disposed after `EndInvoke`
- The `RunspacePool` is disposed after all jobs complete
- Wrapped in try/finally to ensure cleanup even on script termination

### New Parameter

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--parallel <n>` | `4` | Number of concurrent RunspacePool workers. Set to `1` for sequential processing (current behaviour). |

Added to `Get-ParsedArguments` switch block with aliases `parallel` and `p`.

### Backwards Compatibility

- All existing parameters and output formats remain unchanged
- `--parallel 1` produces identical output to the current sequential behaviour (ordered, no progress bar)
- The REPORT table, CHANGES section, and completion message are unaffected
- The only visible differences at default settings:
  - Repos may print in non-deterministic order during processing
  - A `Write-Progress` bar appears during execution
  - Execution is significantly faster

### Testing Considerations

- **Sequential fallback**: `--parallel 1` must produce identical output to current behaviour (ordered, no progress bar)
- **Error handling**: A repo that fails fetch/pull must not crash the pool or block other repos
- **Stashing under parallelism**: Stash operations are repo-local, safe to run concurrently with no cross-repo interference
- **Edge cases**: Single repo, all repos dirty/skipped, no network, mixed PS 5.1/7+
- **Throttle boundary**: `--parallel` value greater than repo count should clamp to repo count
- **Cleanup**: Verify RunspacePool and PowerShell instances are disposed on both success and failure paths

### Expected Performance

| Scenario | Before | After (Phase B) | After (Phase A+B) |
|----------|--------|------------------|--------------------|
| 21 repos | ~35s | ~25-28s | ~8-12s |
| Per repo git calls | 7 | 4 | 4 (concurrent) |
| Bottleneck | Sequential network I/O | Sequential network I/O | Parallel network I/O |
