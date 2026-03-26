Set-StrictMode -Version Latest 2>$null

# Ensure UTF-8 output so Unicode symbols render correctly
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# -------------------------------------------------------------------------
# Default root directory to scan for repositories
$Script:DefaultRootPath = 'D:\Repos'

# Prefix for immediate child folders to treat as repositories.
$Script:ChildFolderPrefix = 'Hydra' # Use H for all or Htec for SLIBs
# -------------------------------------------------------------------------

# Pre-compiled regex patterns
$Script:RegexPatterns = @{
    ArgumentParsingPattern = '^(--?[^=]+)=(.+)$'
    UpToDatePattern = "^($([regex]::Escape([RepositoryStatus]::UpToDate))|$([regex]::Escape([RepositoryStatus]::AlreadyUpToDate)))$"
    FailedErrorPattern = 'failed|error'
    SkippedDirtyPattern = 'skipped|dirty'
    ForwardedPattern = 'fast-forwarded|forwarded'
    GitErrorPattern = 'error:|fatal:|CONFLICT|merge conflict|divergent branches'
    StashConflictPattern = 'CONFLICT'
}

# Color mappings for console output
$Script:ColorCodes = @{
    'Black' = 30; 'Red' = 31; 'Green' = 32; 'Yellow' = 33; 'Blue' = 34; 'Magenta' = 35; 'Cyan' = 36; 'White' = 37
    'BrightRed' = 91; 'BrightGreen' = 92; 'BrightYellow' = 93; 'BrightBlue' = 94; 'BrightMagenta' = 95; 'BrightCyan' = 96; 'BrightWhite' = 97
}

# Derive valid color names from the keys
$Script:ValidColors = @($Script:ColorCodes.Keys)

function Get-ParsedArguments ([string[]]$argList)
{
    $result = [ordered]@{
        RootPath = $Script:DefaultRootPath; NoPull = $false; SkipDirty = $false; StashDirty = $false
        UseRebase = $false; FetchAllRemotes = $false; VerboseBranches = $false
        Invalid = @()
    }

    for ($i = 0; $i -lt $argList.Count; $i++) {
        $raw = $argList[$i]
        if (-not $raw) {
            continue
        }

        $namePart = $null; $valuePart = $null
        if ($raw -match $Script:RegexPatterns.ArgumentParsingPattern) {
            $namePart = $Matches[1]; $valuePart = $Matches[2]
        }
        else {
            $namePart = $raw
        }

        $normalized = $namePart.TrimStart('-').ToLowerInvariant()
        switch ($normalized)
        {
            'root-path' { if (-not $valuePart) { if ($i + 1 -lt $argList.Count) { $valuePart = $argList[++$i] } else { $result.Invalid += $raw; break } }; $result.RootPath = $valuePart; continue }
            'no-pull' { $result.NoPull = $true; continue }
            'skip-dirty' { $result.SkipDirty = $true; continue }
            'stash-dirty' { $result.StashDirty = $true; continue }
            'use-rebase' { $result.UseRebase = $true; continue }
            'fetch-all-remotes' { $result.FetchAllRemotes = $true; continue }
            'fetch-all' { $result.FetchAllRemotes = $true; continue }
            'verbose-branches' { $result.VerboseBranches = $true; continue }
            'verbose' { $result.VerboseBranches = $true; continue }
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

$Script:StatusSymbols = @{
    # Progress status indicators (use [char] escapes so file encoding doesn't matter)
    Warning     = "$([char]0x26A0)$([char]0xFE0F)"         # ⚠️
    Error       = "$([char]0x26D4)"                        # ⛔
    Success     = "$([char]0x2705)"                        # ✅
    Failed      = "$([char]::ConvertFromUtf32(0x1F534))"   # 🔴
    Forwarded   = "$([char]0x23E9)"                        # ⏩
    Skipped     = "$([char]0x23ED)$([char]0xFE0F)"         # ⏭️
    Info        = "$([char]0x2139)$([char]0xFE0F)"         # ℹ️

    # Summary table symbols
    CheckMark   = "$([char]0x2714)"                        # ✔
    CrossMark   = "$([char]0x2716)"                        # ✖

    # Process indicators
    Fetching    = "$([char]0x2B07)$([char]0xFE0F)"         # ⬇️
    Updating    = "$([char]::ConvertFromUtf32(0x1F504))"   # 🔄
    Complete    = "$([char]0x2728)"                        # ✨
}

# Status-to-icon/color mapping for Get-StatusIcon
$Script:StatusIconMap = @(
    @{ Pattern = $Script:RegexPatterns.UpToDatePattern;    Icon = $Script:StatusSymbols.Success;   Color = 'Green' }
    @{ Pattern = $Script:RegexPatterns.FailedErrorPattern; Icon = $Script:StatusSymbols.Failed;    Color = 'Red' }
    @{ Pattern = $Script:RegexPatterns.SkippedDirtyPattern;Icon = $Script:StatusSymbols.Skipped;   Color = 'Yellow' }
    @{ Pattern = $Script:RegexPatterns.ForwardedPattern;   Icon = $Script:StatusSymbols.Forwarded; Color = 'Cyan' }
)

function Format-Text ([string]$text,
                      [ValidateScript({ $_ -in $Script:ValidColors })]
                      [string]$color = 'White')
{
    $colorCode = $Script:ColorCodes[$color]
    if (-not $colorCode) {
        $colorCode = 37
    }

    return "$([char]27)[$colorCode`m$text$([char]27)[0m"
}

function Write-Message ([string]$text,
                       [ValidateScript({ $_ -in $Script:ValidColors })]
                       [string]$color = 'White',
                       [bool]$newLine = $true)
{
    $formattedText = Format-Text -text $text -color $color
    Write-Host $formattedText -NoNewline:(-not $newLine)
}

function Get-SuccessSymbol { return Format-Text -text $Script:StatusSymbols.CheckMark -color 'Green' }

function Get-FailureSymbol { return Format-Text -text $Script:StatusSymbols.CrossMark -color 'Red' }

function Get-StatusIcon ([string]$status)
{
    foreach ($entry in $Script:StatusIconMap) {
        if ($status -match $entry.Pattern) {
            return Format-Text -text "$($entry.Icon) " -color $entry.Color
        }
    }

    return Format-Text -text "$($Script:StatusSymbols.Info) " -color 'White'
}

# -------------------------------------------------------------------------
class RepositoryStatus
{
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

class PullStatus
{
    static [string] $Yes = 'Yes'
    static [string] $No = 'No'
    static [string] $NoOrigin = 'No origin'
    static [string] $Skipped = 'Skipped'
}

class RepositoryResultFactory
{
    static [PSCustomObject] CreateResult([string]$Name, [string]$Branch, [string]$Dirty,
                                       [string]$Pulled, [string]$Status, [bool]$HasRemote,
                                       [array]$StashMessages, [array]$PullMessages,
                                       [array]$DiffStat)
    {
        return [PSCustomObject]@{
            Name = $Name
            Branch = $Branch
            Dirty = $Dirty
            Pulled = $Pulled
            Status = $Status
            HasRemote = $HasRemote
            StashMessages = $StashMessages
            PullMessages = $PullMessages
            DiffStat = $DiffStat
        }
    }

    static [PSCustomObject] CreateNoRemoteResult([string]$Name)
    {
        return [RepositoryResultFactory]::CreateResult($Name, '', 'No',
            [PullStatus]::NoOrigin, [RepositoryStatus]::SkippedNoOrigin, $false, @(), @(), @())
    }

    static [PSCustomObject] CreateDirtySkippedResult([string]$Name, [string]$Branch)
    {
        return [RepositoryResultFactory]::CreateResult($Name, $Branch, 'Yes',
            [PullStatus]::Skipped, [RepositoryStatus]::DirtySkipped, $true, @(), @(), @())
    }
}

function Get-Repositories ([string]$root)
{
    try
    {
        if (-not (Test-Path $root))
        {
            Write-Warning "Root path '$root' does not exist"
            return @()
        }

        $pattern = "$Script:ChildFolderPrefix*"
        Get-ChildItem -Path $root -Directory -Filter $pattern -ErrorAction Stop |
            Where-Object {
                try
                {
                    Test-Path (Join-Path $_.FullName '.git') -ErrorAction Stop
                }
                catch
                {
                    Write-Warning "Cannot access repository: $($_.FullName)";
                    $false
                }
            }
    }
    catch
    {
        Write-Warning "Failed to scan directory '$root': $($_.Exception.Message)"
        return @()
    }
}

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

function Invoke-GitFetch ([string]$path, [switch]$all)
{
    try
    {
        $fetchArgs = if ($all) { @('fetch', '--all', '--prune') } else { @('fetch', 'origin', '--prune') }

        # Use faster null redirection and direct exit code check
        & git -C $path @fetchArgs >$null 2>$null
        $success = $LASTEXITCODE -eq 0

        if (-not $success) {
            Write-Warning "Fetch failed for '$(Split-Path $path -Leaf)' (exit code: $LASTEXITCODE)"
            return $false
        }

        return $true
    }
    catch
    {
        Write-Warning "Failed to fetch for '$(Split-Path $path -Leaf)': $($_.Exception.Message)"
        return $false
    }
}

function Invoke-GitPull ([string]$path, [string]$branch, [switch]$rebase)
{
    try
    {
        if ($branch -eq '(detached)') {
            return $false, [RepositoryStatus]::DetachedHead, @()
        }

        # Verify remote branch exists
        $remoteExists = git -C $path rev-parse --verify "origin/$branch" 2>$null
        if (-not $remoteExists -or $LASTEXITCODE -ne 0) {
            return $false, "$([RepositoryStatus]::NoRemoteBranch) origin/$branch", @()
        }

        # Prepare pull arguments
        $pullArgs = if ($rebase) { @('pull', '--rebase', '--stat', 'origin', $branch) } else { @('pull', '--ff-only', '--stat', 'origin', $branch) }

        # Execute pull with comprehensive error detection
        $output = & git -C $path @pullArgs 2>&1
        $success = $LASTEXITCODE -eq 0

        # Analyze output for specific error conditions
        $errorMessages = [System.Collections.Generic.List[string]]::new()
        $diffStatLines = [System.Collections.Generic.List[string]]::new()
        $output | ForEach-Object {
            $line = $_.ToString()
            if ($line -match $Script:RegexPatterns.GitErrorPattern) {
                $success = $false
                $errorMessages.Add($line)
            }
            # Capture diffstat lines (file change lines and summary line)
            if ($line -match '^\s+\S.*\|' -or $line -match '^\s+\d+ files? changed') {
                $diffStatLines.Add($line)
            }
            if ($VerbosePreference -eq 'Continue') {
                Write-Message "  $line" 'White'
            }
        }

        if ($success) {
            $statusText = if ($rebase) { [RepositoryStatus]::Rebased } else { [RepositoryStatus]::FastForwarded }
        }
        else
        {
            $statusText = if ($errorMessages.Count -gt 0) {
                "$([RepositoryStatus]::PullFailed): $($errorMessages[0])"
            } else {
                [RepositoryStatus]::PullFailed
            }
        }

        return $success, $statusText, @($diffStatLines)
    }
    catch
    {
        return $false, "$([RepositoryStatus]::PullError): $($_.Exception.Message)", @()
    }
}

function Push-StashIfNeeded ([string]$path)
{
    $msg = "WIP_$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    git -C $path stash push -u -m $msg | Out-Null

    # Extract the full stash entry with reference and message
    $match = git -C $path stash list | Select-String $msg | Select-Object -First 1
    if (-not $match) {
        return $null
    }

    $stashEntry = $match.ToString()
    # Format: "stash@{0}: On branch: message" -> return "stash@{0}: message"
    $parts = $stashEntry.Split(':', 3)
    if ($parts.Length -ge 3) {
        return "$($parts[0]): $($parts[2].Trim())"
    }

    return $stashEntry
}

function Pop-StashIfPresent ([string]$path)
{
    $ok = $true
    git -C $path stash pop 2>&1 | ForEach-Object {
        if ($_ -match $Script:RegexPatterns.StashConflictPattern) { $ok = $false }
        Write-Host "  $_"
    }

    return $ok
}

function Invoke-SingleRepositoryProcessing ([string]$path, [switch]$skipDirty, [switch]$stashDirty, [switch]$noPull, [switch]$useRebase, [switch]$fetchAllRemotes)
{
    $name = Split-Path $path -Leaf
    $remoteExists = (git -C $path remote 2>$null) -contains 'origin'
    if (-not $remoteExists)
    {
        return [RepositoryResultFactory]::CreateNoRemoteResult($name)
    }

    $status = Get-RepoStatus -path $path
    if ($status.Dirty -and $skipDirty)
    {
        return [RepositoryResultFactory]::CreateDirtySkippedResult($name, $status.Branch)
    }

    $stashRef = $null
    $stashMessages = [System.Collections.Generic.List[string]]::new()
    if ($status.Dirty -and $stashDirty)
    {
        $stashRef = Push-StashIfNeeded -path $path
        if ($stashRef) { $stashMessages.Add("Stashed changes: $stashRef") }
    }

    $null = Invoke-GitFetch -path $path -all:$fetchAllRemotes
    $pulled = [PullStatus]::No
    $statusNote = [RepositoryStatus]::Fetched
    $pullMessages = [System.Collections.Generic.List[string]]::new()
    $diffStatLines = @()

    if (-not $noPull)
    {
        $ok, $note, $stat = Invoke-GitPull -path $path -branch $status.Branch -rebase:$useRebase
        $statusNote = $note
        if ($stat) { $diffStatLines = @($stat) }
        if ($ok)
        {
            $pulled = [PullStatus]::Yes
        }

        if (-not $ok -and $note -eq [RepositoryStatus]::PullFailed)
        {
            $pullMessages.Add('Pull failed (merge/rebase needed). Manual intervention required.')
        }
    }
    else
    {
        $statusNote = [RepositoryStatus]::FetchedOnly
    }

    if ($stashRef)
    {
        $ok = Pop-StashIfPresent -path $path
        # Extract just the stash reference (e.g., "stash@{0}") from the full stash message
        $stashRefOnly = $stashRef.Split(':')[0]
        if ($ok) {
            $statusNote += " (Stash $stashRefOnly restored)"
        } else {
            $statusNote += " (Stash $stashRefOnly conflicts)"
        }

        # Quick dirty check without full status call
        $quickStatus = git -C $path status --porcelain 2>$null
        $status.Dirty = -not [string]::IsNullOrWhiteSpace($quickStatus)
    }

    return [PSCustomObject]@{
        Name   = $name
        Branch = $status.Branch
        Dirty  = if ($status.Dirty) { 'Yes' } else { 'No' }
        Pulled = $pulled
        Status = $statusNote
        HasRemote = $true
        StashMessages = @($stashMessages)
        PullMessages = @($pullMessages)
        DiffStat = $diffStatLines
    }
}

function Write-RepositoryProgress ([PSCustomObject]$repoResult, [int]$repoIndex = 1, [int]$totalRepos = 1, [switch]$verboseBranches)
{
    if (-not $repoResult -or -not $repoResult.PSObject.Properties['Name'])
    {
        Write-Warning "Invalid RepoResult object passed to Write-RepositoryProgress"
        return
    }

    $name = $repoResult.Name
    $paddedIndex = $repoIndex.ToString().PadLeft(2, '0')
    $paddedTotal = $totalRepos.ToString().PadLeft(2, '0')

    # Build progress text with formatting
    $indexPart = Format-Text -text "[$paddedIndex/$paddedTotal]" -color 'White'
    $namePart = Format-Text -text $name -color 'Cyan'
    $branchPart = Format-Text -text "($($repoResult.Branch))" -color 'Magenta'
    $progressText = "$indexPart $namePart $branchPart"

    # Write progress without newline so we can add status icon on same line
    Write-Host $progressText -NoNewline

    # Stash messages
    if ($repoResult.PSObject.Properties['StashMessages'] -and $repoResult.StashMessages -and $repoResult.StashMessages.Count -gt 0) {
        foreach ($msg in $repoResult.StashMessages) {
            Write-Host ""
            Write-Message "  $msg" 'Cyan'
        }
        Write-Message $progressText 'Cyan' $false
    }

    # Pull messages
    if ($repoResult.PSObject.Properties['PullMessages'] -and $repoResult.PullMessages -and $repoResult.PullMessages.Count -gt 0) {
        foreach ($msg in $repoResult.PullMessages) {
            Write-Host ""
            Write-Message "  $msg" 'Red'
        }
        Write-Message $progressText 'Cyan' $false
    }

    if (-not $repoResult.HasRemote)
    {
        Write-Message " $($Script:StatusSymbols.Warning) No origin" 'Yellow'
        return
    }

    if ($repoResult.Status -eq [RepositoryStatus]::DirtySkipped)
    {
        Write-Message " $($Script:StatusSymbols.Error) Dirty / skipped" 'Yellow'
        return
    }

    # Show completion status
    $statusIconFormatted = Get-StatusIcon -status $repoResult.Status

    # Build status text
    $statusText = " $statusIconFormatted$($repoResult.Status)"

    Write-Message $statusText 'White'
}

function Write-Summary ([array]$results, [TimeSpan]$elapsed, [int]$totalRepos)
{
    Write-Host ''
    Write-Message 'REPORT:' 'BrightMagenta'

    # Convert to array to ensure proper pipeline processing
    $resultsArray = @($results)
    $sorted = $resultsArray | Sort-Object Name

    $notUpToDateItems = @($sorted | Where-Object {
        $_.PSObject.Properties['Status'] -and $_.Status -and $_.Status -notmatch $Script:RegexPatterns.UpToDatePattern
    })
    $allUpToDate = $notUpToDateItems.Count -eq 0

    # Filter out empty objects
    $cleanSorted = $sorted | Where-Object { $_ -and $_.PSObject.Properties['Name'] -and $_.Name -and $_.Name.Trim() -ne '' }

    # Create formatted objects with colors + symbols, preserving DiffStat for display
    $formattedData = $cleanSorted | ForEach-Object {
        $branchFormatted = if ($_.Branch -notin @('develop', 'master', 'main', '(detached)', '')) {
            Format-Text -text $_.Branch -color 'Magenta'
        } else {
            $_.Branch
        }

        $dirtySymbol = if ($_.Dirty -eq 'Yes') { Get-FailureSymbol } else { Get-SuccessSymbol }
        $pulledSymbol = if ($_.Pulled -eq 'Yes') { Get-SuccessSymbol } else { Get-FailureSymbol }
        $statusFormatted = "$(Get-StatusIcon -status $_.Status)$($_.Status)"

        [PSCustomObject]@{
            Name = $_.Name
            Branch = $branchFormatted
            Clean = $dirtySymbol
            Pulled = $pulledSymbol
            Status = $statusFormatted
            DiffStat = $_.DiffStat
        }
    }

    if ($allUpToDate)
    {
        # Omit Status column when everything is Up to date
        $formattedData | Select-Object Name, Branch, Clean, Pulled | Format-Table -AutoSize
    }
    else
    {
        # Show Status as the last column when mixed states exist
        $formattedData | Select-Object Name, Branch, Clean, Pulled, Status | Format-Table -AutoSize
    }

    # Show diffstat beneath the table for repos that had changes
    $reposWithChanges = @($formattedData | Where-Object { $_.DiffStat -and $_.DiffStat.Count -gt 0 })
    if ($reposWithChanges.Count -gt 0)
    {
        Write-Message 'CHANGES:' 'BrightMagenta'
        foreach ($repo in $reposWithChanges)
        {
            Write-Message "  $($repo.Name)" 'Cyan'
            foreach ($line in $repo.DiffStat)
            {
                Write-Message "    $line" 'White'
            }
        }
    }

    Write-Host ''
    Write-Message ("Completed in {0:0.0}s for {1} repositories." -f $elapsed.TotalSeconds, $totalRepos) 'Green'
}

function Test-Prerequisites ([string]$rootPath)
{
    if (-not (Test-Path -Path $rootPath -PathType Container))
    {
        Write-Error "RootPath '$rootPath' does not exist or is not a directory.";
        $global:LASTEXITCODE = 1;
        return $false;
    }

    return $true;
}

function Get-RepositoriesForProcessing ([string]$rootPath)
{
    Write-Message "Scanning '$rootPath' for repositories starting with '$Script:ChildFolderPrefix'... " 'Cyan'

    $repos = Get-Repositories -Root $rootPath
    if (-not $repos) {
        Write-Warning 'No repositories found matching pattern.';
        return $null;
    }

    return $repos;
}

function Invoke-RepositoryProcessing ([array]$repositories, [switch]$skipDirty, [switch]$stashDirty, [switch]$noPull, [switch]$useRebase, [switch]$fetchAllRemotes, [switch]$verboseBranches)
{
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    if (-not $repositories -or $repositories.Count -eq 0)
    {
        Write-Warning "No repositories provided for processing";
        return @($results)
    }

    for ($i = 0; $i -lt $repositories.Count; $i++)
    {
        $repo = $repositories[$i]

        $repoResult = Invoke-SingleRepositoryProcessing -path $repo.FullName -skipDirty:$skipDirty -stashDirty:$stashDirty -noPull:$noPull -useRebase:$useRebase -fetchAllRemotes:$fetchAllRemotes
        Write-RepositoryProgress -repoResult $repoResult -repoIndex ($i + 1) -totalRepos $repositories.Count -verboseBranches:$verboseBranches

        $results.Add($repoResult)
    }

    return @($results)
}

function Write-CompletionSummary ([array]$results, [System.TimeSpan]$elapsed, [int]$totalRepos, [switch]$verboseBranches)
{
    if ($verboseBranches)
    {
        Write-Summary -results $results -elapsed $elapsed -totalRepos $totalRepos
    }
    else
    {
        Write-Host ''
        Write-Message ("Completed in {0:0.0}s for {1} repositories." -f $elapsed.TotalSeconds, $totalRepos) 'Green'
        Write-Host ''
    }
}

function Main ([string]$rootPath, [switch]$noPull, [switch]$skipDirty, [switch]$stashDirty, [switch]$useRebase, [switch]$fetchAllRemotes, [switch]$verboseBranches)
{
    # Validate path
    if (-not (Test-Prerequisites -rootPath $rootPath)) { return }

    # Discover repositories to process
    $repos = Get-RepositoriesForProcessing -rootPath $rootPath
    if (-not $repos) { return }

    # Process repositories
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $results = Invoke-RepositoryProcessing -Repositories $repos -skipDirty:$skipDirty -stashDirty:$stashDirty -noPull:$noPull -useRebase:$useRebase -fetchAllRemotes:$fetchAllRemotes -verboseBranches:$verboseBranches
    $sw.Stop()

    # Show completion summary
    Write-CompletionSummary -Results $results -Elapsed $sw.Elapsed -TotalRepos $repos.Count -verboseBranches:$verboseBranches
}

$parsedArgs = Get-ParsedArguments -ArgList $args
if ($parsedArgs.Invalid.Count -gt 0)
{
    Write-Message 'Unrecognized option(s):' 'Red'

    $parsedArgs.Invalid | ForEach-Object {
        Write-Message "  $_" 'Red'
    }

    Write-Message 'See details inside the script to view supported parameters.' 'Yellow';
    $global:LASTEXITCODE = 2;

    return
}

Main -rootPath $parsedArgs.RootPath `
     -noPull:$parsedArgs.NoPull `
     -skipDirty:$parsedArgs.SkipDirty `
     -stashDirty:$parsedArgs.StashDirty `
     -useRebase:$parsedArgs.UseRebase `
     -fetchAllRemotes:$parsedArgs.FetchAllRemotes `
     -verboseBranches:$parsedArgs.VerboseBranches
