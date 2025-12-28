param (
    [Parameter(Mandatory = $false)]
    [string]$RepositoryPath = "D:\Repos\Hydra.OPT.Service", # (Get-Location).Path,

    [Parameter(Mandatory = $false)]
    [ValidateSet("today", "this_week", "last_week", "last_4_weeks", "current_month", "last_month")]
    [string]$Period = "last_4_weeks",

    [Parameter(Mandatory = $false)]
    [switch]$OutputToConsole = $true
)

# Function to calculate date range based on period
function Get-DateRange ([string]$period) 
{
    $today = Get-Date
    $startDate = $null
    $endDate = $today.AddDays(1).Date  # Include up to end of today

    switch ($period) {
        "today" {
            $startDate = $today.Date
        }
        "this_week" {
            $startDate = $today.AddDays(-($today.DayOfWeek.value__)).Date
        }
        "last_week" {
            $startDate = $today.AddDays(-($today.DayOfWeek.value__ + 7)).Date
            $endDate = $today.AddDays(-($today.DayOfWeek.value__)).Date
        }
        "current_month" {
            $startDate = $today.AddDays(-($today.Day - 1)).Date
        }
        "last_month" {
            $lastMonth = $today.AddMonths(-1)
            $startDate = $lastMonth.AddDays(-($lastMonth.Day - 1)).Date
            $endDate = $today.AddDays(-($today.Day - 1)).Date
        }
        "last_4_weeks" {
            $startDate = $today.AddDays(-28).Date
        }
        default {
            Write-Error "Invalid period specified."
            exit 1
        }
    }

    return $startDate, $endDate
}

# Function to validate Git repository
function Test-GitRepository([string]$path)
{
    try {
        Push-Location -Path $path
        git rev-parse --is-inside-work-tree | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Directory '$path' is not a valid Git repository."
            exit 1
        }
    }
    finally {
        Pop-Location
    }
}

# Function to extract ticket numbers, messages, and datetimes
function Get-CommitData ([string]$path, [datetime]$startDate, [datetime]$endDate)
{
    try {
        Push-Location -Path $path
        $since = $startDate.ToString("yyyy-MM-dd")
        $until = $endDate.ToString("yyyy-MM-dd")
        
        # Get commits with author date, author name, and message
        $commits = git log --since="$since" --until="$until" --pretty="%ad|%an|%B" --date=iso --no-merges
        
        # Define regex patterns used for processing
        $commitData = @()
        $patterns = @{
            GitLogEntry = '^\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\s*[+-]\d{4}\|'
            TicketNumber = '^(#?\d+|#\d+:)\s*(.*)'
            MessageWithDash = '^-'
            SemicolonTruncate = '^([^;]*);'
            AndTruncate = '^(.*?) and '
            TrailingSemicolons = ';+$'
            TrailingPeriods = '\.+$'
            DuplicatePeriods = '\.\s*\.'
            ProperCase = '^((?:\d+\s*-\s*|\s*-\s*)?)(\w)(\w*)(.*)$'
            AuthorTwoNames = '(\w)\w*\s+(\w)'
            AuthorOneName = '(\w)'
        }
        
        foreach ($commit in ($commits -split "`n")) {
            $commit = $commit.Trim()
            
            # Step 1: Parse git log entry format (date|author|message)
            if ($commit -match $patterns.GitLogEntry) {
                $parts = $commit -split '\|', 3
                $commitDateStr = $parts[0].Trim()
                $authorName = $parts[1].Trim()
                $message = $parts[2].Trim()
                
                # Step 2: Extract ticket number and message
                if ($message -match $patterns.TicketNumber) {
                    $ticket = $matches[1] -replace '[^0-9]', ''
                    $commitMessage = $matches[2].Trim()
                    
                    # Step 3: Message cleanup and normalization
                    $commitMessage = Format-CommitMessage -message $commitMessage -patterns $patterns
                    
                    # Step 4: Extract author initials
                    $authorInitials = Get-AuthorInitials -authorName $authorName -patterns $patterns
                    
                    # Step 5: Parse commit date
                    $commitDate = Parse-CommitDate -dateString $commitDateStr
                    if ($null -eq $commitDate) { continue }
                    
                    # Step 6: Create commit data object
                    if ($ticket -and $commitMessage) {
                        $commitData += [PSCustomObject]@{
                            DateTime = $commitDate
                            AuthorInitials = $authorInitials
                            Ticket = $ticket
                            Message = $commitMessage
                        }
                    }
                }
            }
        }
        
        return $commitData
    }
    finally {
        Pop-Location
    }
}

# Helper function to format and clean commit messages
function Format-CommitMessage([string]$message, [hashtable]$patterns)
{
    $commitMessage = $message
    
    # Handle messages starting with a dash
    if ($commitMessage -match $patterns.MessageWithDash) {
        $commitMessage = " $commitMessage"
    }
    
    # Clean up dash spacing
    $commitMessage = $commitMessage -replace "- ", " "
    
    # Truncate at first semicolon or " and "
    if ($commitMessage -match $patterns.SemicolonTruncate) {
        $commitMessage = $matches[1].Trim()
    } elseif ($commitMessage -match $patterns.AndTruncate) {
        $commitMessage = $matches[1].Trim()
    }
    
    # Remove trailing punctuation
    $commitMessage = $commitMessage -replace $patterns.TrailingSemicolons, ''
    $commitMessage = $commitMessage -replace $patterns.TrailingPeriods, ''
    $commitMessage = $commitMessage -replace $patterns.DuplicatePeriods, '.'
    $commitMessage = $commitMessage.Trim()
    
    # Apply proper case to first word
    if ($commitMessage -match $patterns.ProperCase) {
        $prefix = $matches[1]        # Optional prefix: "digits - " or "- " or empty
        $firstLetter = $matches[2]   # First letter of the actual word
        $restOfWord = $matches[3]    # Rest of first word
        $restOfMessage = $matches[4] # Everything after first word
        $commitMessage = $prefix + $firstLetter.ToUpper() + $restOfWord.ToLower() + $restOfMessage
    }
    
    return $commitMessage
}

# Helper function to extract author initials
function Get-AuthorInitials([string]$authorName, [hashtable]$patterns)
{
    $authorInitials = ""
    if ($authorName -match $patterns.AuthorTwoNames) {
        $authorInitials = "$($matches[1])$($matches[2])".ToUpper()
    } elseif ($authorName -match $patterns.AuthorOneName) {
        $authorInitials = $matches[1].ToUpper()
    }
    
    return $authorInitials
}

# Helper function to parse commit dates
function Parse-CommitDate([string]$dateString)
{
    try 
    {
        # Handle ISO date format with timezone offset
        return [datetime]::ParseExact($dateString, "yyyy-MM-dd HH:mm:ss zzz", $null)
    } 
    catch {
        try {
            # Fallback to general parsing
            return [datetime]::Parse($dateString)
        } catch {
            Write-Warning "Failed to parse date '$dateString' for commit. Skipping."
            return $null
        }
    }
}

# Main script
try 
{
    # Validate repository
    Test-GitRepository -path $RepositoryPath

    # Get repository name
    $repoName = Split-Path $RepositoryPath -Leaf

    # Get date range
    $startDate, $endDate = Get-DateRange -period $Period

    # Get commit data
    $commitData = Get-CommitData -path $RepositoryPath -startDate $startDate -endDate $endDate

    # Group by ticket number and collect unique tickets
    $tickets = $commitData | Select-Object -Property Ticket -Unique | Sort-Object Ticket
    $releaseNotes = "# $repoName Release Notes`n`n"
    
    # Add ticket links
    if ($tickets.Count -gt 0) {
        $releaseNotes += "## Ticket Links`n"
        foreach ($ticket in $tickets) {
            $ticketNumber = $ticket.Ticket
            $releaseNotes += "- [$ticketNumber](https://pdidev.visualstudio.com/HTEC-Fuel/_workitems/edit/$ticketNumber)`n"
        }
        $releaseNotes += "`n"
    }

    # Add commit history
    $releaseNotes += "## $repoName History`n"
    $releaseNotes += "----------------------------------------------------------------`n"
    foreach ($commit in $commitData) {
        $formattedDate = $commit.DateTime.ToString("yyyyMM dd HH:mm:ss")
        $releaseNotes += "$formattedDate | $($commit.AuthorInitials) | - #$($commit.Ticket): $($commit.Message).`n"
    }

    # If no commits found
    if ($commitData.Count -eq 0) {
        $releaseNotes += "- No commits found for the specified period.`n"
    }

    # Output based on parameter
    if ($OutputToConsole) {
        Write-Output $releaseNotes
    } else {
        $outputFile = Join-Path $RepositoryPath "$repoName-release-notes.md"
        $releaseNotes | Out-File -FilePath $outputFile -Encoding utf8
        Write-Host "Release notes generated at: $outputFile"
    }
}
catch 
{
    Write-Error "An error occurred: $_"
    exit 1
}
