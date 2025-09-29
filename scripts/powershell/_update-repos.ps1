<#
    Scans the specified root directory $Script:DefaultRootPath (default D:\Repos) 
    for immediate child folders beginning with prefix $Script:ChildFolderPrefix) (default H)
    that contain a .git directory. 
#>

Set-StrictMode -Version Latest 2>$null

# -------------------------------------------------------------------------
# Configuration Settings

# Default root directory to scan for repositories
$Script:DefaultRootPath = 'D:\Repos'

# Configurable prefix for immediate child folders to treat as repositories.
$Script:ChildFolderPrefix = 'H'

# -------------------------------------------------------------------------

function Parse-Arguments
{
    param([string[]]$ArgList)

    $result = [ordered]@{
        RootPath = $Script:DefaultRootPath; NoPull = $false; SkipDirty = $false; StashDirty = $false
        UseRebase = $false; FetchAllRemotes = $false; VerboseBranches = $false
        ShowVersion = $false; ShowHelp = $false; Invalid = @()
    }

    for ($i = 0; $i -lt $ArgList.Count; $i++) {
        $raw = $ArgList[$i]
        if (-not $raw) {
            continue
        }
        
        $namePart = $null; $valuePart = $null
        if ($raw -match '^(--?[^=]+)=(.+)$') { 
            $namePart = $Matches[1]; $valuePart = $Matches[2] 
        }
        else { 
            $namePart = $raw 
        }

        $normalized = $namePart.TrimStart('-').ToLowerInvariant()
        switch ($normalized) 
        {
            'rootpath' { if (-not $valuePart) { if ($i + 1 -lt $ArgList.Count) { $valuePart = $ArgList[++$i] } else { $result.Invalid += $raw; break } }; $result.RootPath = $valuePart; continue }
            'root-path' { if (-not $valuePart) { if ($i + 1 -lt $ArgList.Count) { $valuePart = $ArgList[++$i] } else { $result.Invalid += $raw; break } }; $result.RootPath = $valuePart; continue }
            'nopull' { $result.NoPull = $true; continue }
            'no-pull' { $result.NoPull = $true; continue }
            'skipdirty' { $result.SkipDirty = $true; continue }
            'skip-dirty' { $result.SkipDirty = $true; continue }
            'stashdirty' { $result.StashDirty = $true; continue }
            'stash-dirty' { $result.StashDirty = $true; continue }
            'userebase' { $result.UseRebase = $true; continue }
            'use-rebase' { $result.UseRebase = $true; continue }
            'fetchallremotes' { $result.FetchAllRemotes = $true; continue }
            'fetch-all-remotes' { $result.FetchAllRemotes = $true; continue }
            'fetch-all' { $result.FetchAllRemotes = $true; continue }
            'verbose-branches' { $result.VerboseBranches = $true; continue }
            'verbose' { $result.VerboseBranches = $true; continue }
            'v' { $result.VerboseBranches = $true; continue }
            'showversion' { $result.ShowVersion = $true; continue }
            'version' { $result.ShowVersion = $true; continue }
            'ver' { $result.ShowVersion = $true; continue }
            'showhelp' { $result.ShowHelp = $true; continue }
            'help' { $result.ShowHelp = $true; continue }
            'h' { $result.ShowHelp = $true; continue }
            default {
                if ($raw.StartsWith('-')) { $result.Invalid += $raw; continue }

                # Treat first non-switch value (that doesn't map to known switch) as RootPath if user changed it
                if ($result.RootPath -eq $Script:DefaultRootPath) { 
                    $result.RootPath = $raw; 
                    continue 
                }
                else { 
                    $result.Invalid += $raw; 
                    continue 
                }
            }
        }
    }

    return $result
}

$__parsed = Parse-Arguments -ArgList $args

if ($__parsed.Invalid.Count -gt 0)
{
    Write-Host (Format-Text -Text 'Unrecognized option(s):' -Color 'Red')
    $__parsed.Invalid | ForEach-Object { Write-Host (Format-Text -Text "  $_" -Color 'Red') }
    Write-Host (Format-Text -Text 'See details inside the script to view supported parameters.' -Color 'Yellow')
    exit 2
}

$RootPath        = $__parsed.RootPath
$NoPull          = $__parsed.NoPull
$SkipDirty       = $__parsed.SkipDirty
$StashDirty      = $__parsed.StashDirty
$UseRebase       = $__parsed.UseRebase
$FetchAllRemotes = $__parsed.FetchAllRemotes
$VerboseBranches = $__parsed.VerboseBranches
$ShowVersion     = $__parsed.ShowVersion
$ShowHelp        = $__parsed.ShowHelp

# Symbols for summary output 
# TODO: Change these to font glyphs
$Script:CheckMark = '+'
$Script:CrossMark = 'x'


function Format-Text
{
    param (
        [string]$Text,
        [ValidateSet('Black', 'Red', 'Green', 'Yellow', 'Blue', 'Magenta', 'Cyan', 'White', 
                     'BrightRed', 'BrightGreen', 'BrightYellow', 'BrightBlue', 
                     'BrightMagenta', 'BrightCyan', 'BrightWhite')]
        [string]$Color = 'White'
    )

    $colorCodes = @{
        'Black' = 30; 'Red' = 31; 'Green' = 32; 'Yellow' = 33; 'Blue' = 34; 'Magenta' = 35; 'Cyan' = 36; 'White' = 37
        'BrightRed' = 91; 'BrightGreen' = 92; 'BrightYellow' = 93; 'BrightBlue' = 94; 'BrightMagenta' = 95; 'BrightCyan' = 96; 'BrightWhite' = 97
    }

    $colorCode = $colorCodes[$Color]
    if (-not $colorCode) { 
        $colorCode = 37     # Default to white 
    }

    return "$([char]27)[$colorCode`m$Text$([char]27)[0m"
}

function Get-SuccessSymbol
{
    return Format-Text -Text $Script:CheckMark -Color 'Green'
}

function Get-FailureSymbol
{
    return Format-Text -Text $Script:CrossMark -Color 'Red'
}

# -------------------------------------------------------------------------

function Get-Repositories
{
    param ([string]$Root)
    
    try {
        if (-not (Test-Path $Root)) {
            Write-Warning "Root path '$Root' does not exist"
            return @()
        }
        
        $pattern = "$Script:ChildFolderPrefix*"
        Get-ChildItem -Path $Root -Directory -Filter $pattern -ErrorAction Stop |
            Where-Object { 
                try { Test-Path (Join-Path $_.FullName '.git') -ErrorAction Stop }
                catch { Write-Warning "Cannot access repository: $($_.FullName)"; $false }
            }
    }
    catch {
        Write-Warning "Failed to scan directory '$Root': $($_.Exception.Message)"
        return @()
    }
}

function Get-RepoStatus
{
    param ([string]$Path)
    
    try {
        # Check if it's actually a git repository
        $gitDir = git -C $Path rev-parse --git-dir 2>$null
        if (-not $gitDir) {
            Write-Warning "Not a git repository: $Path"
            return [PSCustomObject]@{ Branch = '(not a git repo)'; Dirty = $false; Error = $true }
        }
        
        # Get current branch
        $branch = git -C $Path symbolic-ref --short HEAD 2>$null
        if (-not $branch) { 
            # Try to get detached HEAD info with short SHA
            $shortSha = git -C $Path rev-parse --short HEAD 2>$null
            $branch = if ($shortSha) { "(detached at $shortSha)" } else { '(detached)' }
        }
        
        # Check for uncommitted changes
        $statusOutput = git -C $Path status --porcelain 2>$null
        $dirty = -not [string]::IsNullOrWhiteSpace($statusOutput)
        
        [PSCustomObject]@{ Branch = $branch; Dirty = $dirty; Error = $false }
    }
    catch {
        Write-Warning "Failed to get git status for '$Path': $($_.Exception.Message)"
        [PSCustomObject]@{ Branch = '(error)'; Dirty = $false; Error = $true }
    }
}

function Invoke-GitFetch
{
    param (
        [string]$Path,
        [switch]$All
    )
    
    try {
        $fetchArgs = if ($All) { @('fetch', '--all', '--prune') } else { @('fetch', 'origin', '--prune') }
        
        # Capture both stdout and stderr
        $result = & git -C $Path @fetchArgs 2>&1
        
        # Check for fetch errors
        $errorLines = $result | Where-Object { $_ -match 'error:|fatal:' }
        if ($errorLines) {
            Write-Warning "Fetch issues for '$(Split-Path $Path -Leaf)': $($errorLines -join '; ')"
            return $false
        }
        
        return $true
    }
    catch {
        Write-Warning "Failed to fetch for '$(Split-Path $Path -Leaf)': $($_.Exception.Message)"
        return $false
    }
}

function Get-AheadBehind
{
    param (
        [string]$Path,
        [string]$Branch
    )
    
    try {
        if ($Branch -eq '(detached)') { 
            return @(0,0) 
        }
        
        # Check if remote branch exists
        $exists = git -C $Path rev-parse --verify "origin/$Branch" 2>$null
        if (-not $exists -or $LASTEXITCODE -ne 0) { 
            return @(0,0) 
        }
        
        # Get ahead/behind counts with error checking
        $counts = git -C $Path rev-list --left-right --count "$Branch...origin/$Branch" 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Unable to compare '$Branch' with origin in '$(Split-Path $Path -Leaf)'"
            return 0,0
        }
        
        if ($counts -and $counts.Trim()) {
            $parts = $counts.Trim() -split '\s+'
            if ($parts.Count -eq 2) {
                try {
                    return @([int]$parts[0], [int]$parts[1])
                } catch {
                    Write-Warning "Invalid count format '$counts' in '$(Split-Path $Path -Leaf)'"
                    return @(0,0)
                }
            }
        }
        
        return @(0,0)
    }
    catch {
        Write-Warning "Error getting ahead/behind for '$(Split-Path $Path -Leaf)': $($_.Exception.Message)"
        return @(0,0)
    }
}

function Invoke-GitPull
{
    param (
        [string]$Path,
        [string]$Branch,
        [switch]$Rebase
    )
    
    try {
        if ($Branch -eq '(detached)') { 
            return $false, 'Detached HEAD (fetched)' 
        }
        
        # Verify remote branch exists
        $remoteExists = git -C $Path rev-parse --verify "origin/$Branch" 2>$null
        if (-not $remoteExists -or $LASTEXITCODE -ne 0) { 
            return $false, "No remote branch origin/$Branch" 
        }
        
        # Check if pull is needed
        $ahead, $behind = Get-AheadBehind -Path $Path -Branch $Branch
        if ($behind -eq 0) {
            return $true, "Already up to date"
        }
        
        # Prepare pull arguments
        $pullArgs = if ($Rebase) { @('pull', '--rebase', 'origin', $Branch) } else { @('pull', '--ff-only', 'origin', $Branch) }
        
        # Execute pull with comprehensive error detection
        $output = & git -C $Path @pullArgs 2>&1
        $success = $LASTEXITCODE -eq 0
        
        # Analyze output for specific error conditions
        $errorMessages = @()
        $output | ForEach-Object {
            $line = $_.ToString()
            if ($line -match 'error:|fatal:|CONFLICT|merge conflict|divergent branches') {
                $success = $false
                $errorMessages += $line
            }
            if ($VerbosePreference -eq 'Continue') {
                Write-Host "  $line" -ForegroundColor Gray
            }
        }
        
        if ($success) {
            $statusText = if ($Rebase) { 'Rebased' } else { 'Fast-forwarded' }
        } else {
            $statusText = if ($errorMessages) { 
                "Pull failed: $($errorMessages[0])" 
            } else { 
                'Pull failed' 
            }
        }
        
        return $success, $statusText
    }
    catch {
        return $false, "Pull error: $($_.Exception.Message)"
    }
}

function Push-StashIfNeeded
{
    param ([string]$Path)

    $msg = "auto-update-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    git -C $Path stash push -u -m $msg | Out-Null

    return (git -C $Path stash list | Select-String $msg | Select-Object -First 1).ToString().Split(':')[0]
}

function Pop-StashIfPresent
{
    param ([string]$Path)

    $ok = $true
    git -C $Path stash pop 2>&1 | ForEach-Object {
        if ($_ -match 'CONFLICT') { $ok = $false }
        Write-Host "  $_"
    }

    return $ok
}

function Invoke-RepositoryProcessing
{
    param (
        [string]$Path, [switch]$SkipDirty, [switch]$StashDirty, [switch]$NoPull,
        [switch]$UseRebase, [switch]$FetchAllRemotes, [switch]$VerboseBranches,
        [int]$RepoIndex = 1, [int]$TotalRepos = 1
    )

    $name = Split-Path $Path -Leaf
    $paddedIndex = $RepoIndex.ToString().PadLeft(2, '0')
    $paddedTotal = $TotalRepos.ToString().PadLeft(2, '0')
    $progressText = "[$paddedIndex/$paddedTotal] $name"

    # Write progress without newline so we can add status icon on same line
    Write-Host (Format-Text -Text $progressText -Color 'Cyan') -NoNewline
    
    $remoteExists = (git -C $Path remote 2>$null) -contains 'origin'
    if (-not $remoteExists)
    {
        Write-Host (Format-Text -Text " ⚠ No origin" -Color 'Yellow')
        return [PSCustomObject]@{ Name=$name; Branch=''; Ahead=''; Behind=''; Dirty=''; Pulled='No origin'; Status='Skipped (no origin)' }
    }

    $status = Get-RepoStatus -Path $Path
    if ($status.Dirty -and $SkipDirty)
    {
        Write-Host (Format-Text -Text ' ⛔ Dirty / skipped' -Color 'Yellow')
        return [PSCustomObject]@{ Name=$name; Branch=$status.Branch; Ahead=''; Behind=''; Dirty='Yes'; Pulled='Skipped'; Status='Dirty / skipped' }
    }

    $stashRef = $null
    if ($status.Dirty -and $StashDirty)
    {
        $stashRef = Push-StashIfNeeded -Path $Path
        if ($stashRef) { Write-Host (Format-Text -Text "Stashed changes as $stashRef" -Color 'Cyan') }
    }

    Invoke-GitFetch -Path $Path -All:$FetchAllRemotes
    $ahead, $behind = Get-AheadBehind -Path $Path -Branch $status.Branch
    $pulled = 'No'
    $statusNote = 'Fetched'
    $needPull = $behind -gt 0

    if ($needPull -and -not $NoPull)
    {
        $ok, $note = Invoke-GitPull -Path $Path -Branch $status.Branch -Rebase:$UseRebase
        $statusNote = $note
        if ($ok) 
        { 
            $pulled='Yes'; $ahead, $behind = Get-AheadBehind -Path $Path -Branch $status.Branch 
        }

        if (-not $ok -and $note -eq 'Pull failed') 
        { 
            Write-Host (Format-Text -Text 'Pull failed (merge/rebase needed). Manual intervention required.' -Color 'Red') 
        }
    }
    elseif (-not $NoPull -and -not $needPull) 
    { 
        $statusNote = 'Up to date' 
    }
    elseif ($NoPull) 
    { 
        $statusNote = 'Fetched only' 
    }

    if ($stashRef)
    {
        $ok = Pop-StashIfPresent -Path $Path
        if ($ok) { $statusNote += ' (Stash restored)' } else { $statusNote += ' (Stash conflicts)' }
        $status.Dirty = (Get-RepoStatus -Path $Path).Dirty
    }
    else 
    {
        $status.Dirty = (Get-RepoStatus -Path $Path).Dirty
    }

    # Show completion status with icon on the same line
    $statusIcon = if ($statusNote -eq 'up to date') { '✅' } 
                 elseif ($statusNote -match 'failed|error') { '🔴' }
                 elseif ($statusNote -match 'skipped|dirty') { '⛔' }
                 else { '•' }
    
    $statusColor = if ($statusNote -eq 'up to date') { 'Green' } 
                  elseif ($statusNote -match 'failed|error') { 'Red' }
                  elseif ($statusNote -match 'skipped|dirty') { 'Yellow' }
                  else { 'White' }
    
    # Build status text with optional ahead/behind info
    $statusText = " $statusIcon $statusNote"
    if ($status.Branch -ne '(detached)' -and ($VerboseBranches -or $ahead -gt 0 -or $behind -gt 0))
    {
        $statusText += (Format-Text -Text " (Ahead: $ahead Behind: $behind)" -Color 'Magenta')
    }
    
    Write-Host (Format-Text -Text $statusText -Color $statusColor)

    [PSCustomObject]@{
        Name   = $name
        Branch = $status.Branch
        Ahead  = $ahead
        Behind = $behind
        Dirty  = if ($status.Dirty) { 'Yes' } else { 'No' }
        Pulled = $pulled
        Status = $statusNote
    }
}

function Write-Summary
{
    param (
        [System.Collections.IEnumerable]$Results,
        [TimeSpan]$Elapsed
    )

    Write-Host ''
    Write-Host (Format-Text -Text 'Summary:' -Color 'Cyan')
    
    $sorted = $Results | Sort-Object Name
    $allUpToDate = -not ($sorted | Where-Object { 
        $_.PSObject.Properties['Status'] -and $_.Status -and $_.Status -ne 'up to date' 
    })

    $branchExpr = @{ Name = 'Branch'; Expression = { if ($_.Branch -notin @('develop', 'master', 'main', '(detached)', '')) { Format-Text -Text $_.Branch -Color 'Cyan' } else { $_.Branch } } }    
    $dirtyExpr  = @{ Name = 'Dirty';  Expression = { if ($_.Dirty  -eq 'Yes') { Get-SuccessSymbol } else { Get-FailureSymbol } } }
    $pulledExpr = @{ Name = 'Pulled'; Expression = { if ($_.Pulled -eq 'Yes') { Get-SuccessSymbol } else { Get-FailureSymbol } } }

    if ($allUpToDate)
    {
        # Omit Status column when everything is Up to date
        $sorted |
            Select-Object Name, $branchExpr, $dirtyExpr, $pulledExpr |
            Format-Table -AutoSize
    }
    else
    {
        # Show Status as the last column when mixed states exist
        $sorted |
            Select-Object Name, $branchExpr, $dirtyExpr, $pulledExpr, Status |
            Format-Table -AutoSize -Wrap
    }

    Write-Host ''
    Write-Host (Format-Text -Text ("Completed in {0:0.0}s for {1} repositories." -f $Elapsed.TotalSeconds, ($Results | Measure-Object).Count) -Color 'Green')
}

function Show-HelpShort
{
    param()

    Get-Help -Detailed -ErrorAction SilentlyContinue | Out-Null
    Write-Host (Format-Text -Text 'Use Get-Help .\_update-repos.ps1 -Detailed for full help.' -Color 'Cyan')
}

function Show-VersionInfo
{
    $scriptPath = $MyInvocation.MyCommand.Path
    if (-not $scriptPath -and (Get-Variable -Name PSCommandPath -ErrorAction SilentlyContinue)) { $scriptPath = $PSCommandPath }
    if (-not $scriptPath) { $scriptPath = (Get-Location).ProviderPath }

    $gitHead = $null
    $gitVer  = $null
    if (Get-Command git -ErrorAction SilentlyContinue)
    {
        try { $gitHead = git rev-parse --short HEAD 2>$null } catch {}
        try { $gitVer  = git --version 2>$null } catch {}
    }

    $fileInfo = $null
    try { $fileInfo = Get-Item $scriptPath -ErrorAction Stop } catch {}

    Write-Host (Format-Text -Text ("Script: {0}" -f (Split-Path $scriptPath -Leaf 2>$null)) -Color 'Cyan')
    Write-Host (Format-Text -Text ("Path:   {0}" -f $scriptPath) -Color 'White')
    if ($fileInfo) { Write-Host (Format-Text -Text ("Modified (Local): {0}" -f $fileInfo.LastWriteTime) -Color 'White') }
    if ($gitVer)  { Write-Host (Format-Text -Text "Git:    $gitVer" -Color 'White') }
    if ($gitHead) { Write-Host (Format-Text -Text "HEAD:   $gitHead" -Color 'BrightGreen') }
}

function Main
{
    if ($ShowHelp)
    {
        Write-Host @"
Usage: .\_update-repos.ps1 [options]
See details inside the script to view supported parameters.

"@
        return
    }

    if ($ShowVersion) { Show-VersionInfo; return }
    if (-not (Test-Path -Path $RootPath -PathType Container)) 
    { 
        Write-Error "RootPath '$RootPath' does not exist or is not a directory."; 
        exit 1 
    }

    Write-Host (Format-Text -Text "Scanning '$RootPath' for repositories starting with '$Script:ChildFolderPrefix'... " -Color 'Cyan')
    $repos = Get-Repositories -Root $RootPath
    if (-not $repos) { 
        Write-Warning 'No repositories found matching pattern.'; return 
    }

    $results = @()
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $totalRepos = $repos.Count

    for ($i = 0; $i -lt $repos.Count; $i++)
    {
        $r = $repos[$i]
        $repoResult = Invoke-RepositoryProcessing -Path $r.FullName -SkipDirty:$SkipDirty -StashDirty:$StashDirty -NoPull:$NoPull -UseRebase:$UseRebase -FetchAllRemotes:$FetchAllRemotes -VerboseBranches:$VerboseBranches -RepoIndex ($i + 1) -TotalRepos $totalRepos
        $results += $repoResult
    }

    $sw.Stop()
    
    # Only show summary in verbose mode
    if ($VerboseBranches) {
        Write-Summary -Results $results -Elapsed $sw.Elapsed
    } else {
        Write-Host (Format-Text -Text ("Completed in {0:0.0}s for {1} repositories." -f $sw.Elapsed.TotalSeconds, ($results | Measure-Object).Count) -Color 'Green')
    }
}

Main