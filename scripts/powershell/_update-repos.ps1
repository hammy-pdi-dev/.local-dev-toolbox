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

function Get-ParsedArguments
{
    param([string[]]$ArgList)

    $result = [ordered]@{
        RootPath = $Script:DefaultRootPath; NoPull = $false; SkipDirty = $false; StashDirty = $false
        UseRebase = $false; FetchAllRemotes = $false; VerboseBranches = $false
        Invalid = @()
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

# Symbols for summary output 
# TODO: Change these to font glyphs
$Script:CheckMark = '+'
$Script:CrossMark = 'x'

class RepositoryStatus {
    static [string] $Fetched = 'Fetched'
    static [string] $UpToDate = 'Up to date'
    static [string] $AlreadyUpToDate = 'Already up to date'
    static [string] $FetchedOnly = 'Fetched only'
    static [string] $Rebased = 'Rebased'
    static [string] $FastForwarded = 'Fast-forwarded'
    static [string] $PullFailed = 'Pull failed'
    static [string] $DetachedHead = 'Detached HEAD (fetched)'
    static [string] $NoRemoteBranch = 'No remote branch'
    static [string] $PullError = 'Pull error'
    static [string] $SkippedNoOrigin = 'Skipped (no origin)'
    static [string] $DirtySkipped = 'Dirty / skipped'
    static [string] $StashRestored = ' (Stash restored)'
    static [string] $StashConflicts = ' (Stash conflicts)'
}

class PullStatus {
    static [string] $Yes = 'Yes'
    static [string] $No = 'No'
    static [string] $NoOrigin = 'No origin'
    static [string] $Skipped = 'Skipped'
}

class RepositoryResultFactory {
    static [PSCustomObject] CreateResult([string]$Name, [string]$Branch, [int]$Ahead, [int]$Behind, 
                                       [string]$Dirty, [string]$Pulled, [string]$Status, 
                                       [bool]$HasRemote, [array]$StashMessages, [array]$PullMessages) 
    {
        return [PSCustomObject]@{
            Name = $Name
            Branch = $Branch
            Ahead = $Ahead
            Behind = $Behind
            Dirty = $Dirty
            Pulled = $Pulled
            Status = $Status
            HasRemote = $HasRemote
            StashMessages = $StashMessages
            PullMessages = $PullMessages
        }
    }
    
    static [PSCustomObject] CreateNoRemoteResult([string]$Name) 
    {
        return [RepositoryResultFactory]::CreateResult($Name, '', 0, 0, 'No', 
            [PullStatus]::NoOrigin, [RepositoryStatus]::SkippedNoOrigin, $false, @(), @())
    }
    
    static [PSCustomObject] CreateDirtySkippedResult([string]$Name, [string]$Branch) 
    {
        return [RepositoryResultFactory]::CreateResult($Name, $Branch, 0, 0, 'Yes', 
            [PullStatus]::Skipped, [RepositoryStatus]::DirtySkipped, $true, @(), @())
    }
}

# Pre-compiled regex patterns for performance
$Script:RegexPatterns = @{
    UpToDatePattern = "^($([regex]::Escape([RepositoryStatus]::UpToDate))|$([regex]::Escape([RepositoryStatus]::AlreadyUpToDate)))$"
    FailedErrorPattern = 'failed|error'
    SkippedDirtyPattern = 'skipped|dirty'
}

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
    return Format-Text -Text $Script:CheckMark -Color 'Red'
}

function Get-FailureSymbol
{
    return Format-Text -Text $Script:CrossMark -Color 'Green'
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
        
        # Use faster null redirection and direct exit code check
        & git -C $Path @fetchArgs >$null 2>$null
        $success = $LASTEXITCODE -eq 0
        
        if (-not $success) {
            Write-Warning "Fetch failed for '$(Split-Path $Path -Leaf)' (exit code: $LASTEXITCODE)"
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
            return $false, [RepositoryStatus]::DetachedHead 
        }
        
        # Verify remote branch exists
        $remoteExists = git -C $Path rev-parse --verify "origin/$Branch" 2>$null
        if (-not $remoteExists -or $LASTEXITCODE -ne 0) { 
            return $false, "$([RepositoryStatus]::NoRemoteBranch) origin/$Branch" 
        }
        
        # Check if pull is needed
        $ahead, $behind = Get-AheadBehind -Path $Path -Branch $Branch
        if ($behind -eq 0) {
            return $true, [RepositoryStatus]::AlreadyUpToDate
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
            $statusText = if ($Rebase) { [RepositoryStatus]::Rebased } else { [RepositoryStatus]::FastForwarded }
        } else {
            $statusText = if ($errorMessages) { 
                "$([RepositoryStatus]::PullFailed): $($errorMessages[0])" 
            } else { 
                [RepositoryStatus]::PullFailed 
            }
        }
        
        return $success, $statusText
    }
    catch {
        return $false, "$([RepositoryStatus]::PullError): $($_.Exception.Message)"
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

function Invoke-SingleRepositoryProcessing
{
    param (
        [string]$Path, [switch]$SkipDirty, [switch]$StashDirty, [switch]$NoPull,
        [switch]$UseRebase, [switch]$FetchAllRemotes
    )

    $name = Split-Path $Path -Leaf
    
    $remoteExists = (git -C $Path remote 2>$null) -contains 'origin'
    if (-not $remoteExists)
    {
        return [RepositoryResultFactory]::CreateNoRemoteResult($name)
    }

    $status = Get-RepoStatus -Path $Path
    if ($status.Dirty -and $SkipDirty)
    {
        return [RepositoryResultFactory]::CreateDirtySkippedResult($name, $status.Branch)
    }

    $stashRef = $null
    $stashMessages = @()
    if ($status.Dirty -and $StashDirty)
    {
        $stashRef = Push-StashIfNeeded -Path $Path
        if ($stashRef) { $stashMessages += "Stashed changes as $stashRef" }
    }

    $null = Invoke-GitFetch -Path $Path -All:$FetchAllRemotes
    $ahead, $behind = Get-AheadBehind -Path $Path -Branch $status.Branch
    $pulled = [PullStatus]::No
    $statusNote = [RepositoryStatus]::Fetched
    $needPull = $behind -gt 0
    $pullMessages = @()

    if ($needPull -and -not $NoPull)
    {
        $ok, $note = Invoke-GitPull -Path $Path -Branch $status.Branch -Rebase:$UseRebase
        $statusNote = $note
        if ($ok) 
        { 
            $pulled = [PullStatus]::Yes
            $ahead, $behind = Get-AheadBehind -Path $Path -Branch $status.Branch 
        }

        if (-not $ok -and $note -eq [RepositoryStatus]::PullFailed) 
        { 
            $pullMessages += 'Pull failed (merge/rebase needed). Manual intervention required.'
        }
    }
    elseif (-not $NoPull -and -not $needPull) 
    { 
        $statusNote = [RepositoryStatus]::UpToDate 
    }
    elseif ($NoPull) 
    { 
        $statusNote = [RepositoryStatus]::FetchedOnly 
    }

    if ($stashRef)
    {
        $ok = Pop-StashIfPresent -Path $Path
        if ($ok) { $statusNote += [RepositoryStatus]::StashRestored } else { $statusNote += [RepositoryStatus]::StashConflicts }
        # Quick dirty check without full status call
        $quickStatus = git -C $Path status --porcelain 2>$null
        $status.Dirty = -not [string]::IsNullOrWhiteSpace($quickStatus)
    }

    return [PSCustomObject]@{
        Name   = $name
        Branch = $status.Branch
        Ahead  = $ahead
        Behind = $behind
        Dirty  = if ($status.Dirty) { 'Yes' } else { 'No' }
        Pulled = $pulled
        Status = $statusNote
        HasRemote = $true
        StashMessages = $stashMessages
        PullMessages = $pullMessages
    }
}

function Write-RepositoryProgress
{
    param (
        [PSCustomObject]$RepoResult,
        [int]$RepoIndex = 1,
        [int]$TotalRepos = 1,
        [switch]$VerboseBranches
    )

    # Validate input
    if (-not $RepoResult -or -not $RepoResult.PSObject.Properties['Name']) {
        Write-Warning "Invalid RepoResult object passed to Write-RepositoryProgress"
        return
    }

    $name = $RepoResult.Name
    $paddedIndex = $RepoIndex.ToString().PadLeft(2, '0')
    $paddedTotal = $TotalRepos.ToString().PadLeft(2, '0')
    
    # Build enhanced progress text with better formatting
    $indexPart = Format-Text -Text "[$paddedIndex/$paddedTotal]" -Color 'White'
    $namePart = Format-Text -Text $name -Color 'Cyan'
    $branchPart = Format-Text -Text "($($RepoResult.Branch))" -Color 'Magenta'
    $progressText = "$indexPart $namePart $branchPart"

    # Write progress without newline so we can add status icon on same line
    Write-Host $progressText -NoNewline
    
    # Display any stash messages
    if ($RepoResult.PSObject.Properties['StashMessages'] -and $RepoResult.StashMessages -and $RepoResult.StashMessages.Count -gt 0) {
        foreach ($msg in $RepoResult.StashMessages) {
            Write-Host ""
            Write-Host (Format-Text -Text "  $msg" -Color 'Cyan')
        }
        Write-Host (Format-Text -Text $progressText -Color 'Cyan') -NoNewline
    }

    # Display any pull error messages
    if ($RepoResult.PSObject.Properties['PullMessages'] -and $RepoResult.PullMessages -and $RepoResult.PullMessages.Count -gt 0) {
        foreach ($msg in $RepoResult.PullMessages) {
            Write-Host ""
            Write-Host (Format-Text -Text "  $msg" -Color 'Red')
        }
        Write-Host (Format-Text -Text $progressText -Color 'Cyan') -NoNewline
    }
    
    if (-not $RepoResult.HasRemote)
    {
        Write-Host (Format-Text -Text " ⚠ No origin" -Color 'Yellow')
        return
    }

    if ($RepoResult.Status -eq [RepositoryStatus]::DirtySkipped)
    {
        Write-Host (Format-Text -Text ' ⛔ Dirty / skipped' -Color 'Yellow')
        return
    }

    # Show completion status with icon on the same line
    $statusIcon = if ($RepoResult.Status -match $Script:RegexPatterns.UpToDatePattern) { '✅' } 
                 elseif ($RepoResult.Status -match $Script:RegexPatterns.FailedErrorPattern) { '🔴' }
                 elseif ($RepoResult.Status -match $Script:RegexPatterns.SkippedDirtyPattern) { '⛔' }
                 else { '•' }
    
    $statusColor = if ($RepoResult.Status -match $Script:RegexPatterns.UpToDatePattern) { 'Green' } 
                  elseif ($RepoResult.Status -match $Script:RegexPatterns.FailedErrorPattern) { 'Red' }
                  elseif ($RepoResult.Status -match $Script:RegexPatterns.SkippedDirtyPattern) { 'Yellow' }
                  else { 'White' }
    
    # Build status text with optional ahead/behind info
    $statusText = " $statusIcon $($RepoResult.Status)"
    if ($RepoResult.Branch -ne '(detached)' -and ($VerboseBranches -or $RepoResult.Ahead -gt 0 -or $RepoResult.Behind -gt 0))
    {
        $statusText += (Format-Text -Text " (Ahead: $($RepoResult.Ahead) Behind: $($RepoResult.Behind))" -Color 'Magenta')
    }
    
    Write-Host (Format-Text -Text $statusText -Color $statusColor)
}

function Write-Summary
{
    param (
        $Results,
        [TimeSpan]$Elapsed,
        [int]$TotalRepos
    )

    Write-Host ''
    Write-Host (Format-Text -Text 'REPORT:' -Color 'BrightMagenta')
    
    # Convert to array to ensure proper pipeline processing
    $resultsArray = @($Results)
    $sorted = $resultsArray | Sort-Object Name
    
    $notUpToDateItems = @($sorted | Where-Object { 
        $_.PSObject.Properties['Status'] -and $_.Status -and $_.Status -notmatch $Script:RegexPatterns.UpToDatePattern 
    })
    $allUpToDate = $notUpToDateItems.Count -eq 0

    # Filter out empty objects
    $cleanSorted = $sorted | Where-Object { $_ -and $_.PSObject.Properties['Name'] -and $_.Name -and $_.Name.Trim() -ne '' }
    
    # Create formatted objects with colors and symbols
    $formattedData = $cleanSorted | ForEach-Object {
        $branchFormatted = if ($_.Branch -notin @('develop', 'master', 'main', '(detached)', '')) { 
            Format-Text -Text $_.Branch -Color 'Magenta' 
        } else { 
            $_.Branch 
        }

        $dirtySymbol = if ($_.Dirty -ne 'Yes') { Get-FailureSymbol } else { Get-SuccessSymbol }
        $pulledSymbol = if ($_.Pulled -eq 'Yes') { Get-SuccessSymbol } else { Get-FailureSymbol }
        
        [PSCustomObject]@{
            Name = $_.Name
            Branch = $branchFormatted
            Dirty = $dirtySymbol
            Pulled = $pulledSymbol
            Status = $_.Status
        }
    }
    
    if ($allUpToDate)
    {
        # Omit Status column when everything is Up to date
        $formattedData | Select-Object Name, Branch, Dirty, Pulled | Format-Table -AutoSize
    }
    else
    {
        # Show Status as the last column when mixed states exist
        $formattedData | Format-Table -AutoSize
    }

    Write-Host ''
    Write-Host (Format-Text -Text ("Completed in {0:0.0}s for {1} repositories." -f $Elapsed.TotalSeconds, $TotalRepos) -Color 'Green')
}

function Check-Prerequisites
{
    if (-not (Test-Path -Path $RootPath -PathType Container)) 
    { 
        Write-Error "RootPath '$RootPath' does not exist or is not a directory.";
        $global:LASTEXITCODE = 1;
        return $false;
    }

    return $true;
}

function Get-RepositoriesForProcessing
{
    Write-Host (Format-Text -Text "Scanning '$RootPath' for repositories starting with '$Script:ChildFolderPrefix'... " -Color 'Cyan')
    
    $repos = Get-Repositories -Root $RootPath
    if (-not $repos) { 
        Write-Warning 'No repositories found matching pattern.';
        return $null;
    }
    
    return $repos;
}

function Invoke-RepositoryProcessing
{
    param([array]$Repositories)
    
    $results = @()
    if (-not $Repositories -or $Repositories.Count -eq 0) {
        Write-Warning "No repositories provided for processing";
        return $results;
    }
    
    for ($i = 0; $i -lt $Repositories.Count; $i++) {
        $repo = $Repositories[$i]

        $repoResult = Invoke-SingleRepositoryProcessing -Path $repo.FullName -SkipDirty:$SkipDirty -StashDirty:$StashDirty -NoPull:$NoPull -UseRebase:$UseRebase -FetchAllRemotes:$FetchAllRemotes
        Write-RepositoryProgress -RepoResult $repoResult -RepoIndex ($i + 1) -TotalRepos $Repositories.Count -VerboseBranches:$VerboseBranches
        
        $results += $repoResult
    }

    return $results
}

function Write-CompletionSummary
{
    param([array]$Results, [System.TimeSpan]$Elapsed, [int]$TotalRepos)
    
    if ($VerboseBranches) {
        Write-Summary -Results $Results -Elapsed $Elapsed -TotalRepos $TotalRepos
    } else {
        Write-Host ''
        Write-Host (Format-Text -Text ("Completed in {0:0.0}s for {1} repositories." -f $Elapsed.TotalSeconds, $TotalRepos) -Color 'Green')
        Write-Host ''
    }
}

function Main
{
    # Validate prerequisites
    if (-not (Check-Prerequisites)) { return }
    
    # Discover repositories to process
    $repos = Get-RepositoriesForProcessing
    if (-not $repos) { return }
    
    # Process repositories
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $results = Invoke-RepositoryProcessing -Repositories $repos
    $sw.Stop()
    
    # Show completion summary
    Write-CompletionSummary -Results $results -Elapsed $sw.Elapsed -TotalRepos $repos.Count
}

$__parsed = Get-ParsedArguments -ArgList $args

if ($__parsed.Invalid.Count -gt 0)
{
    Write-Host (Format-Text -Text 'Unrecognized option(s):' -Color 'Red');

    $__parsed.Invalid | ForEach-Object { 
        Write-Host (Format-Text -Text "  $_" -Color 'Red') 
    }
    
    Write-Host (Format-Text -Text 'See details inside the script to view supported parameters.' -Color 'Yellow');

    $global:LASTEXITCODE = 2;
    return
}

$RootPath        = $__parsed.RootPath
$NoPull          = $__parsed.NoPull
$SkipDirty       = $__parsed.SkipDirty
$StashDirty      = $__parsed.StashDirty
$UseRebase       = $__parsed.UseRebase
$FetchAllRemotes = $__parsed.FetchAllRemotes
$VerboseBranches = $__parsed.VerboseBranches

Main
