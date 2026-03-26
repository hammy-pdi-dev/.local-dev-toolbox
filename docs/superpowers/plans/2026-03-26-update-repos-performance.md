# Update-Repos Performance Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce `_update-repos.ps1` wall time from ~35s to ~8-12s for 21 repositories by eliminating redundant git calls and parallelising repo processing.

**Architecture:** Two phases applied in order. Phase B rewrites `Get-RepoStatus` to use a single `git status --porcelain -b` call (replacing 3 separate git calls) and removes the redundant remote-branch verification from `Invoke-GitPull`. Phase A adds a `RunspacePool`-based parallel processing path that submits each repo to a self-contained scriptblock, polls for completions on the main thread, and displays a `Write-Progress` bar. A new `--parallel <n>` parameter controls concurrency (default 4, use 1 for sequential fallback).

**Tech Stack:** PowerShell 5.1+ (RunspacePool API from `System.Management.Automation.Runspaces`)

**Spec:** `scripts/powershell/utils/_update-repos.md` (Performance Design Spec section)

---

## File Structure

All changes are in a single file:

- **Modify:** `scripts/powershell/utils/_update-repos.ps1`
  - `Get-RepoStatus` (lines 243-272) — rewrite to use single `git status --porcelain -b`
  - `Invoke-GitPull` (lines 299-356) — remove `rev-parse --verify` check
  - `Get-ParsedArguments` (lines 35-86) — add `--parallel` parameter
  - `Invoke-RepositoryProcessing` (lines 622-642) — branch between sequential and parallel
  - New function `Invoke-ParallelRepositoryProcessing` — RunspacePool implementation
  - `Main` (lines 658-674) — pass `$parallel` parameter through
  - Script entry point (lines 676-697) — parse and pass `$parallel`

---

## Phase B: Reduce Git Subprocess Calls

### Task 1: Rewrite Get-RepoStatus to use single git call

**Files:**
- Modify: `scripts/powershell/utils/_update-repos.ps1:243-272`

This replaces 3 git subprocess calls (`rev-parse --git-dir`, `symbolic-ref --short HEAD`, `status --porcelain`) with a single `git status --porcelain -b` call.

- [ ] **Step 1: Replace Get-RepoStatus function body**

Replace the entire `Get-RepoStatus` function (lines 243-272) with:

```powershell
function Get-RepoStatus ([string]$path)
{
    try
    {
        # Single git call: --porcelain -b gives branch info on first line + dirty state
        $output = git -C $path status --porcelain -b 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $output) {
            Write-Warning "Failed to get status for: $path"
            return [PSCustomObject]@{ Branch = '(error)'; Dirty = $false; Error = $true }
        }

        $lines = @($output)
        $branchLine = $lines[0]

        # Parse branch from "## branch...origin/branch [ahead N]" or "## branch"
        $branch = if ($branchLine -match '^## (.+?)\.\.\.') {
            $Matches[1]
        }
        elseif ($branchLine -match '^## (.+)$') {
            $branchName = $Matches[1]
            # Detect detached HEAD variants
            if ($branchName -eq 'HEAD (no branch)') {
                $shortSha = git -C $path rev-parse --short HEAD 2>$null
                if ($shortSha) { "(detached at $shortSha)" } else { '(detached)' }
            }
            else {
                $branchName
            }
        }
        else {
            '(unknown)'
        }

        # Any lines beyond the branch line indicate uncommitted changes
        $dirty = $lines.Count -gt 1

        [PSCustomObject]@{ Branch = $branch; Dirty = $dirty; Error = $false }
    }
    catch
    {
        Write-Warning "Failed to get git status for '$path': $($_.Exception.Message)"
        [PSCustomObject]@{ Branch = '(error)'; Dirty = $false; Error = $true }
    }
}
```

Key parsing notes:
- `## develop...origin/develop` — branch is `develop`, has tracking remote
- `## feature/foo` — branch is `feature/foo`, no tracking remote (no `...`)
- `## HEAD (no branch)` — detached HEAD, needs one extra `rev-parse --short HEAD` call for the SHA
- Lines after the first `##` line are porcelain status entries (dirty files)

- [ ] **Step 2: Verify the script loads without parse errors**

Run:
```bash
pwsh -NoProfile -Command "& { . './scripts/powershell/utils/_update-repos.ps1' --no-pull }" 2>&1 | head -5
```

Expected: No parse errors. The script should start scanning for repositories (or report that the default path doesn't exist if not on the target machine).

- [ ] **Step 3: Commit**

```bash
git add scripts/powershell/utils/_update-repos.ps1
git commit -m "perf: replace 3 git calls in Get-RepoStatus with single git status --porcelain -b"
```

---

### Task 2: Remove redundant remote-branch verification from Invoke-GitPull

**Files:**
- Modify: `scripts/powershell/utils/_update-repos.ps1:299-356`

The `git rev-parse --verify "origin/$branch"` call before pulling is redundant — if the remote branch doesn't exist, `git pull` will fail with a clear error that's already handled by the error detection logic.

- [ ] **Step 1: Remove the rev-parse --verify block from Invoke-GitPull**

Remove these lines from `Invoke-GitPull` (currently lines 307-311):

```powershell
        # Verify remote branch exists
        $remoteExists = git -C $path rev-parse --verify "origin/$branch" 2>$null
        if (-not $remoteExists -or $LASTEXITCODE -ne 0) {
            return $false, "$([RepositoryStatus]::NoRemoteBranch) origin/$branch", @()
        }
```

The pull's error output will be captured by the existing `GitErrorPattern` regex and reported as a pull failure, which is the correct behaviour.

- [ ] **Step 2: Verify the function still handles missing remote branches**

The pull command `git pull --ff-only origin $branch` will output `fatal: couldn't find remote ref $branch` which matches the `GitErrorPattern` regex (`fatal:` is in the pattern). This causes `$success = $false` and the status to be set to `Pull failed: fatal: couldn't find remote ref $branch`. Confirm the regex matches:

```bash
pwsh -NoProfile -Command "'fatal: couldn''t find remote ref develop' -match 'error:|fatal:|CONFLICT|merge conflict|divergent branches'"
```

Expected: `True`

- [ ] **Step 3: Commit**

```bash
git add scripts/powershell/utils/_update-repos.ps1
git commit -m "perf: remove redundant rev-parse --verify before git pull"
```

---

## Phase A: Parallel Processing via RunspacePool

### Task 3: Add --parallel parameter to argument parsing

**Files:**
- Modify: `scripts/powershell/utils/_update-repos.ps1:35-86` (Get-ParsedArguments)
- Modify: `scripts/powershell/utils/_update-repos.ps1:658-674` (Main)
- Modify: `scripts/powershell/utils/_update-repos.ps1:676-697` (entry point)

- [ ] **Step 1: Add Parallel to the parsed arguments result hashtable**

In `Get-ParsedArguments`, add `Parallel = 4` to the `$result` ordered hashtable (line 39 area):

```powershell
    $result = [ordered]@{
        RootPath = $Script:DefaultRootPath; NoPull = $false; SkipDirty = $false; StashDirty = $false
        UseRebase = $false; FetchAllRemotes = $false; VerboseBranches = $false
        Parallel = 4
        Invalid = @()
    }
```

- [ ] **Step 2: Add switch cases for --parallel and -p**

Add these cases to the `switch ($normalized)` block, after the `'verbose'` case:

```powershell
            'parallel' { if (-not $valuePart) { if ($i + 1 -lt $argList.Count) { $valuePart = $argList[++$i] } else { $result.Invalid += $raw; break } }; $result.Parallel = [int]$valuePart; continue }
            'p' { if (-not $valuePart) { if ($i + 1 -lt $argList.Count) { $valuePart = $argList[++$i] } else { $result.Invalid += $raw; break } }; $result.Parallel = [int]$valuePart; continue }
```

- [ ] **Step 3: Add $parallel parameter to Main function signature**

Update the `Main` function signature to include `[int]$parallel = 4`:

```powershell
function Main ([string]$rootPath, [switch]$noPull, [switch]$skipDirty, [switch]$stashDirty, [switch]$useRebase, [switch]$fetchAllRemotes, [switch]$verboseBranches, [int]$parallel = 4)
```

Pass it through to `Invoke-RepositoryProcessing`:

```powershell
    $results = Invoke-RepositoryProcessing -Repositories $repos -skipDirty:$skipDirty -stashDirty:$stashDirty -noPull:$noPull -useRebase:$useRebase -fetchAllRemotes:$fetchAllRemotes -verboseBranches:$verboseBranches -parallel $parallel
```

- [ ] **Step 4: Update the script entry point to pass $parallel**

Update the `Main` call at the bottom of the script:

```powershell
Main -rootPath $parsedArgs.RootPath `
     -noPull:$parsedArgs.NoPull `
     -skipDirty:$parsedArgs.SkipDirty `
     -stashDirty:$parsedArgs.StashDirty `
     -useRebase:$parsedArgs.UseRebase `
     -fetchAllRemotes:$parsedArgs.FetchAllRemotes `
     -verboseBranches:$parsedArgs.VerboseBranches `
     -parallel $parsedArgs.Parallel
```

- [ ] **Step 5: Verify parsing works**

```bash
pwsh -NoProfile -Command "
    Set-StrictMode -Version Latest 2>`$null
    class RepositoryStatus { static [string] `$UpToDate = 'Up to date'; static [string] `$AlreadyUpToDate = 'Already up to date' }
    . './scripts/powershell/utils/_update-repos.ps1' --parallel 2 --no-pull 2>&1 | Select-Object -First 1
"
```

Expected: Script starts with parallel=2 (no parse errors).

- [ ] **Step 6: Commit**

```bash
git add scripts/powershell/utils/_update-repos.ps1
git commit -m "feat: add --parallel parameter for concurrent repo processing"
```

---

### Task 4: Create self-contained scriptblock for runspace processing

**Files:**
- Modify: `scripts/powershell/utils/_update-repos.ps1` — add new function `New-RepoProcessingScriptBlock`

This is the most critical piece. The scriptblock must be fully self-contained because runspaces don't have access to script-scoped functions, classes, or variables.

- [ ] **Step 1: Add New-RepoProcessingScriptBlock function**

Add this function after `Pop-StashIfPresent` and before `Invoke-SingleRepositoryProcessing`. The function returns a scriptblock that contains all per-repo processing logic inlined:

```powershell
function New-RepoProcessingScriptBlock
{
    return {
        param(
            [string]$Path,
            [bool]$SkipDirty,
            [bool]$StashDirty,
            [bool]$NoPull,
            [bool]$UseRebase,
            [bool]$FetchAllRemotes,
            [string]$GitErrorPattern,
            [string]$StashConflictPattern
        )

        $name = Split-Path $Path -Leaf

        # Helper: create result hashtable
        function New-Result([string]$n, [string]$branch, [string]$dirty, [string]$pulled,
                           [string]$status, [bool]$hasRemote, [array]$stashMsgs, [array]$pullMsgs,
                           [array]$diffStat) {
            return @{
                Name = $n; Branch = $branch; Dirty = $dirty; Pulled = $pulled
                Status = $status; HasRemote = $hasRemote
                StashMessages = $stashMsgs; PullMessages = $pullMsgs; DiffStat = $diffStat
            }
        }

        # Check origin exists
        $remoteExists = (git -C $Path remote 2>$null) -contains 'origin'
        if (-not $remoteExists) {
            return (New-Result $name '' 'No' 'No origin' 'Skipped (no origin)' $false @() @() @())
        }

        # Get branch + dirty state in one call
        $output = git -C $Path status --porcelain -b 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $output) {
            return (New-Result $name '(error)' 'No' 'No' 'Error' $true @() @('Failed to read status') @())
        }

        $lines = @($output)
        $branchLine = $lines[0]

        $branch = if ($branchLine -match '^## (.+?)\.\.\.') {
            $Matches[1]
        }
        elseif ($branchLine -match '^## (.+)$') {
            $branchName = $Matches[1]
            if ($branchName -eq 'HEAD (no branch)') {
                $shortSha = git -C $Path rev-parse --short HEAD 2>$null
                if ($shortSha) { "(detached at $shortSha)" } else { '(detached)' }
            }
            else { $branchName }
        }
        else { '(unknown)' }

        $dirty = $lines.Count -gt 1

        # Handle dirty + skip
        if ($dirty -and $SkipDirty) {
            return (New-Result $name $branch 'Yes' 'Skipped' 'Dirty / skipped' $true @() @() @())
        }

        # Handle dirty + stash
        $stashRef = $null
        $stashMessages = @()
        if ($dirty -and $StashDirty) {
            $msg = "WIP_$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            git -C $Path stash push -u -m $msg 2>$null | Out-Null

            $stashMatch = git -C $Path stash list 2>$null | Select-String $msg | Select-Object -First 1
            if ($stashMatch) {
                $stashEntry = $stashMatch.ToString()
                $parts = $stashEntry.Split(':', 3)
                if ($parts.Length -ge 3) {
                    $stashRef = "$($parts[0]): $($parts[2].Trim())"
                } else {
                    $stashRef = $stashEntry
                }
                $stashMessages += "Stashed changes: $stashRef"
            }
        }

        # Fetch
        $fetchArgs = if ($FetchAllRemotes) { @('fetch', '--all', '--prune') } else { @('fetch', 'origin', '--prune') }
        & git -C $Path @fetchArgs >$null 2>$null

        $pulled = 'No'
        $statusNote = 'Fetched'
        $pullMessages = @()
        $diffStatLines = @()

        if (-not $NoPull) {
            if ($branch -match '^\(detached') {
                $statusNote = 'Detached HEAD (fetched)'
            }
            else {
                $pullArgs = if ($UseRebase) { @('pull', '--rebase', '--stat', 'origin', $branch) } else { @('pull', '--ff-only', '--stat', 'origin', $branch) }
                $pullOutput = & git -C $Path @pullArgs 2>&1
                $pullSuccess = $LASTEXITCODE -eq 0

                $errorMessages = @()
                $pullOutput | ForEach-Object {
                    $line = $_.ToString()
                    if ($line -match $GitErrorPattern) {
                        $pullSuccess = $false
                        $errorMessages += $line
                    }
                    if ($line -match '^\s+\S.*\|' -or $line -match '^\s+\d+ files? changed') {
                        $diffStatLines += $line
                    }
                }

                if ($pullSuccess) {
                    $statusNote = if ($UseRebase) { 'Rebased' } else { 'Fast-forwarded' }
                    $pulled = 'Yes'
                }
                else {
                    $statusNote = if ($errorMessages.Count -gt 0) { "Pull failed: $($errorMessages[0])" } else { 'Pull failed' }
                    $pullMessages += 'Pull failed (merge/rebase needed). Manual intervention required.'
                }
            }
        }
        else {
            $statusNote = 'Fetched only'
        }

        # Pop stash if we stashed earlier
        if ($stashRef) {
            $stashRefOnly = $stashRef.Split(':')[0]
            $popOutput = git -C $Path stash pop 2>&1
            $popOk = $true
            $popOutput | ForEach-Object {
                if ($_ -match $StashConflictPattern) { $popOk = $false }
            }
            if ($popOk) {
                $statusNote += " (Stash $stashRefOnly restored)"
            } else {
                $statusNote += " (Stash $stashRefOnly conflicts)"
            }

            $quickStatus = git -C $Path status --porcelain 2>$null
            $dirty = -not [string]::IsNullOrWhiteSpace($quickStatus)
        }

        $dirtyStr = if ($dirty) { 'Yes' } else { 'No' }
        return (New-Result $name $branch $dirtyStr $pulled $statusNote $true $stashMessages $pullMessages $diffStatLines)
    }
}
```

Key design decisions:
- Returns a `[hashtable]` (not `[PSCustomObject]`) because custom objects from runspaces can lose type fidelity
- Uses string literals for status constants (`'Fast-forwarded'`, `'Pull failed'`, etc.) instead of class references — classes aren't available inside runspaces
- `New-Result` is a local helper function defined inside the scriptblock
- Regex patterns are passed in as string parameters rather than referencing script-scope variables
- `Write-Host`/`Write-Message` are not called — all output happens on the main thread

- [ ] **Step 2: Verify the scriptblock creates without errors**

```bash
pwsh -NoProfile -Command "
    class RepositoryStatus { static [string] `$UpToDate = 'Up to date'; static [string] `$AlreadyUpToDate = 'Already up to date' }
    . './scripts/powershell/utils/_update-repos.ps1' --no-pull 2>&1 | Select-Object -First 1
"
```

Expected: No parse errors.

- [ ] **Step 3: Commit**

```bash
git add scripts/powershell/utils/_update-repos.ps1
git commit -m "feat: add self-contained scriptblock for runspace-based repo processing"
```

---

### Task 5: Create Invoke-ParallelRepositoryProcessing function

**Files:**
- Modify: `scripts/powershell/utils/_update-repos.ps1` — add new function `Invoke-ParallelRepositoryProcessing`

This function creates a `RunspacePool`, submits all repos, polls for completion with `Write-Progress`, and collects results.

- [ ] **Step 1: Add Invoke-ParallelRepositoryProcessing function**

Add this function after `Invoke-SingleRepositoryProcessing` and before `Write-RepositoryProgress`:

```powershell
function Invoke-ParallelRepositoryProcessing ([array]$repositories, [switch]$skipDirty, [switch]$stashDirty, [switch]$noPull, [switch]$useRebase, [switch]$fetchAllRemotes, [int]$parallel = 4)
{
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    if (-not $repositories -or $repositories.Count -eq 0) {
        Write-Warning "No repositories provided for processing"
        return @($results)
    }

    $throttle = [Math]::Min($repositories.Count, $parallel)
    $scriptBlock = New-RepoProcessingScriptBlock
    $gitErrorPattern = $Script:RegexPatterns.GitErrorPattern
    $stashConflictPattern = $Script:RegexPatterns.StashConflictPattern

    $pool = [RunspaceFactory]::CreateRunspacePool(1, $throttle)
    $pool.Open()

    try {
        # Submit all repos to the pool
        $jobs = [System.Collections.Generic.List[hashtable]]::new()
        foreach ($repo in $repositories) {
            $ps = [PowerShell]::Create().AddScript($scriptBlock)
            $ps.AddParameter('Path', $repo.FullName)
            $ps.AddParameter('SkipDirty', [bool]$skipDirty)
            $ps.AddParameter('StashDirty', [bool]$stashDirty)
            $ps.AddParameter('NoPull', [bool]$noPull)
            $ps.AddParameter('UseRebase', [bool]$useRebase)
            $ps.AddParameter('FetchAllRemotes', [bool]$fetchAllRemotes)
            $ps.AddParameter('GitErrorPattern', $gitErrorPattern)
            $ps.AddParameter('StashConflictPattern', $stashConflictPattern)
            $ps.RunspacePool = $pool

            $handle = $ps.BeginInvoke()
            $jobs.Add(@{ PowerShell = $ps; Handle = $handle; RepoName = $repo.Name })
        }

        # Poll for completions
        $totalRepos = $repositories.Count
        $completedCount = 0

        while ($completedCount -lt $totalRepos) {
            for ($i = $jobs.Count - 1; $i -ge 0; $i--) {
                $job = $jobs[$i]
                if ($job.Handle.IsCompleted) {
                    try {
                        $rawResult = $job.PowerShell.EndInvoke($job.Handle)
                        $resultHash = if ($rawResult -and $rawResult.Count -gt 0) { $rawResult[0] } else { $null }

                        if ($resultHash -and $resultHash -is [hashtable]) {
                            $resultObj = [PSCustomObject]@{
                                Name          = $resultHash.Name
                                Branch        = $resultHash.Branch
                                Dirty         = $resultHash.Dirty
                                Pulled        = $resultHash.Pulled
                                Status        = $resultHash.Status
                                HasRemote     = $resultHash.HasRemote
                                StashMessages = @($resultHash.StashMessages)
                                PullMessages  = @($resultHash.PullMessages)
                                DiffStat      = @($resultHash.DiffStat)
                            }
                        }
                        else {
                            $resultObj = [RepositoryResultFactory]::CreateResult(
                                $job.RepoName, '(error)', 'No', 'No', 'Runspace error',
                                $false, @(), @('Runspace returned unexpected result'), @())
                        }
                    }
                    catch {
                        $resultObj = [RepositoryResultFactory]::CreateResult(
                            $job.RepoName, '(error)', 'No', 'No', "Runspace error: $($_.Exception.Message)",
                            $false, @(), @($_.Exception.Message), @())
                    }
                    finally {
                        $job.PowerShell.Dispose()
                    }

                    $completedCount++
                    $results.Add($resultObj)

                    # Print per-repo progress line (non-deterministic order)
                    Write-RepositoryProgress -repoResult $resultObj -repoIndex $completedCount -totalRepos $totalRepos

                    $jobs.RemoveAt($i)
                }
            }

            if ($completedCount -lt $totalRepos) {
                Write-Progress -Activity "Updating repositories" `
                               -Status "[$completedCount/$totalRepos] completed" `
                               -PercentComplete (($completedCount / $totalRepos) * 100)
                Start-Sleep -Milliseconds 100
            }
        }

        Write-Progress -Activity "Updating repositories" -Completed
    }
    finally {
        # Clean up any remaining jobs on error
        foreach ($job in $jobs) {
            try { $job.PowerShell.Dispose() } catch {}
        }
        $pool.Close()
        $pool.Dispose()
    }

    return @($results)
}
```

Key design decisions:
- Iterates jobs list in reverse when removing completed items to avoid index shifting issues
- Converts the returned hashtable to `[PSCustomObject]` on the main thread so downstream functions (`Write-RepositoryProgress`, `Write-Summary`) work unchanged
- Wraps `EndInvoke` in try/catch so a single runspace failure doesn't crash the entire pool
- `finally` block ensures pool is always disposed, even on Ctrl+C or exceptions
- `Write-Progress` is only called while waiting (not after the final completion)
- Reuses existing `Write-RepositoryProgress` for per-repo output

- [ ] **Step 2: Commit**

```bash
git add scripts/powershell/utils/_update-repos.ps1
git commit -m "feat: add Invoke-ParallelRepositoryProcessing with RunspacePool"
```

---

### Task 6: Wire parallel path into Invoke-RepositoryProcessing and Main

**Files:**
- Modify: `scripts/powershell/utils/_update-repos.ps1` — `Invoke-RepositoryProcessing`, `Main`, entry point

- [ ] **Step 1: Update Invoke-RepositoryProcessing to branch on parallel count**

Replace the `Invoke-RepositoryProcessing` function with:

```powershell
function Invoke-RepositoryProcessing ([array]$repositories, [switch]$skipDirty, [switch]$stashDirty, [switch]$noPull, [switch]$useRebase, [switch]$fetchAllRemotes, [switch]$verboseBranches, [int]$parallel = 4)
{
    if (-not $repositories -or $repositories.Count -eq 0)
    {
        Write-Warning "No repositories provided for processing"
        return @()
    }

    if ($parallel -le 1) {
        # Sequential path (original behaviour)
        $results = [System.Collections.Generic.List[PSCustomObject]]::new()
        for ($i = 0; $i -lt $repositories.Count; $i++)
        {
            $repo = $repositories[$i]
            $repoResult = Invoke-SingleRepositoryProcessing -path $repo.FullName -skipDirty:$skipDirty -stashDirty:$stashDirty -noPull:$noPull -useRebase:$useRebase -fetchAllRemotes:$fetchAllRemotes
            Write-RepositoryProgress -repoResult $repoResult -repoIndex ($i + 1) -totalRepos $repositories.Count -verboseBranches:$verboseBranches
            $results.Add($repoResult)
        }
        return @($results)
    }
    else {
        # Parallel path
        return Invoke-ParallelRepositoryProcessing -repositories $repositories -skipDirty:$skipDirty -stashDirty:$stashDirty -noPull:$noPull -useRebase:$useRebase -fetchAllRemotes:$fetchAllRemotes -parallel $parallel
    }
}
```

- [ ] **Step 2: Update Main to accept and pass $parallel**

The `Main` function signature should be (if not already updated in Task 3):

```powershell
function Main ([string]$rootPath, [switch]$noPull, [switch]$skipDirty, [switch]$stashDirty, [switch]$useRebase, [switch]$fetchAllRemotes, [switch]$verboseBranches, [int]$parallel = 4)
```

The `Invoke-RepositoryProcessing` call inside `Main` should be:

```powershell
    $results = Invoke-RepositoryProcessing -Repositories $repos -skipDirty:$skipDirty -stashDirty:$stashDirty -noPull:$noPull -useRebase:$useRebase -fetchAllRemotes:$fetchAllRemotes -verboseBranches:$verboseBranches -parallel $parallel
```

- [ ] **Step 3: Update the entry point Main call**

The `Main` call at the bottom of the script should be:

```powershell
Main -rootPath $parsedArgs.RootPath `
     -noPull:$parsedArgs.NoPull `
     -skipDirty:$parsedArgs.SkipDirty `
     -stashDirty:$parsedArgs.StashDirty `
     -useRebase:$parsedArgs.UseRebase `
     -fetchAllRemotes:$parsedArgs.FetchAllRemotes `
     -verboseBranches:$parsedArgs.VerboseBranches `
     -parallel $parsedArgs.Parallel
```

- [ ] **Step 4: Commit**

```bash
git add scripts/powershell/utils/_update-repos.ps1
git commit -m "feat: wire parallel processing into main execution path"
```

---

### Task 7: Manual verification

- [ ] **Step 1: Test sequential fallback (--parallel 1)**

Run:
```powershell
.\_update-repos.ps1 --verbose --parallel 1
```

Expected: Repos process in order (01/N, 02/N, ...), no Write-Progress bar, REPORT table displays correctly. Behaviour is identical to the original script.

- [ ] **Step 2: Test parallel processing (default)**

Run:
```powershell
.\_update-repos.ps1 --verbose
```

Expected: Write-Progress bar appears showing `[X/N] completed`. Repos print as they complete (order may vary). REPORT table is sorted by name. CHANGES section shows diffstat for repos that had changes. Completion time is significantly lower than sequential.

- [ ] **Step 3: Test parallel with custom throttle**

Run:
```powershell
.\_update-repos.ps1 --verbose --parallel 2
```

Expected: Same as default parallel but with only 2 concurrent workers. Should be slower than default (4) but faster than sequential (1).

- [ ] **Step 4: Test with --no-pull**

Run:
```powershell
.\_update-repos.ps1 --no-pull --verbose
```

Expected: Only fetches, no pulls. Status shows "Fetched only" for all repos.

- [ ] **Step 5: Test with --skip-dirty on a dirty repo**

Make a change in one repo, then:
```powershell
.\_update-repos.ps1 --skip-dirty --verbose
```

Expected: The dirty repo shows "Dirty / skipped", others process normally.

- [ ] **Step 6: Test error isolation**

Temporarily disconnect network or use a repo with invalid remote, then:
```powershell
.\_update-repos.ps1 --verbose
```

Expected: The failed repo shows an error status. Other repos complete successfully. The pool doesn't hang or crash.

- [ ] **Step 7: Commit any fixes discovered during testing**

```bash
git add scripts/powershell/utils/_update-repos.ps1
git commit -m "fix: address issues found during parallel processing verification"
```

Only create this commit if fixes were needed.
