# Git History Script

Generates formatted release notes from Git commit history for a specified time period. 
The commit titles can also be used for the WTS timesheets entries.

## Features

- **Flexible Date Ranges**: Support for various time periods (today, this week, last week, current month, etc.)
- **Ticket Extraction**: Automatically extracts ticket numbers from commit messages
- **Message Cleanup**: Normalizes commit messages with proper formatting and case
- **Author Initials**: Extracts author initials from commit author names  
- **Output Options**: Console output or file generation
- **Azure DevOps Integration**: Generates clickable ticket links for Azure DevOps workitems

## Usage

```powershell
# Generate release notes for last 4 weeks (default)
.\git-history.ps1

# Generate for specific repository path
.\git-history.ps1 -RepositoryPath "D:\Repos\Hydra.OPT.Service" -Period "this_week"

# Generate for specific time period and output to file
.\git-history.ps1 -Period "current_month" -OutputToConsole:$false

# Output to file instead of console
.\git-history.ps1 -OutputToConsole:$false
```

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `RepositoryPath` | string | Current directory | Path to Git repository |
| `Period` | string | `last_4_weeks` | Time period for commit history |
| `OutputToConsole` | switch | `$true` | Output to console vs file |

## Supported Periods

- `today` - Today's commits only
- `this_week` - Current week (Monday-Sunday) 
- `last_week` - Previous week
- `current_month` - Current month to date
- `last_month` - Previous month
- `last_4_weeks` - Last 4 weeks (28 days) (default)

## Output Format

The script generates release notes with:

1. **Ticket Links Section**: Clickable links to Azure DevOps workitems
2. **Commit History Section**: Formatted commit entries with:
   - Date/time (YYYYMM DD HH:mm:ss format)
   - Author initials
   - Ticket number
   - Cleaned commit message

## Commit Message Processing

The script automatically:
- Extracts ticket numbers from commit messages (e.g., `#12345:`, `12345`)
- Normalizes message formatting (proper case, punctuation cleanup)
- Truncates at semicolons or " and " for concise messages
- Handles dash-prefixed messages
- Removes trailing punctuation and duplicate periods

## Examples

### Basic Usage
```powershell
.\git-history.ps1 -RepositoryPath "D:\Repos\MyProject" -Period "current_month"
```

### Generate File Output
```powershell  
.\git-history.ps1 -OutputToConsole:$false
# Creates: MyProject-release-notes.md
```

### Sample Output
```
# MyProject Release Notes

## Ticket Links
- [12345](https://pdidev.visualstudio.com/HTEC-Fuel/_workitems/edit/12345)
- [12346](https://pdidev.visualstudio.com/HTEC-Fuel/_workitems/edit/12346)

## REPO History
----------------------------------------------------------------
202410 09 14:30:15 | HB | - #12345: Fix authentication jwt token expiration.
202410 09 11:22:30 | HB | - #12346: Add new user validation.
```