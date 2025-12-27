# shared-functions.ps1
# Common helper functions shared across setup scripts

# Common configuration
$Script:SharedConfig = @{
    MaxRetries       = 3
    RetryDelaySeconds = 5
}

function Test-Administrator {
    <#
    .SYNOPSIS
    Checks if the current PowerShell session is running with Administrator privileges.
    #>
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Update-EnvironmentPath {
    <#
    .SYNOPSIS
    Refreshes the PATH environment variable by combining Machine and User paths.
    #>
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

function Add-PathIfMissing {
    <#
    .SYNOPSIS
    Adds a directory to the PATH environment variable if it's not already present.

    .PARAMETER Directory
    The directory path to add to PATH.
    #>
    param([string]$Directory)

    if ($env:Path -notlike "*$Directory*") {
        $env:Path = "$Directory;$env:Path"
    }
}

function Test-DotNetFramework {
    <#
    .SYNOPSIS
    Checks if .NET Framework 4.x is installed.
    #>
    $release = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full\' -ErrorAction SilentlyContinue |
               Get-ItemPropertyValue -Name Release -ErrorAction SilentlyContinue
    return $null -ne $release
}

function Write-LogMessage {
    <#
    .SYNOPSIS
    Unified logging function with optional file logging and timestamps.
    
    .PARAMETER Message
    The message to log.
    
    .PARAMETER Level
    The log level (INFO, SUCCESS, WARNING, ERROR).
    
    .PARAMETER LogFile
    Optional path to a log file. If provided, adds timestamps and writes to file.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Message = "",
        
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR")]
        [string]$Level = "INFO",
        
        [string]$LogFile = $null
    )

    $colors = @{
        INFO    = "Cyan"
        SUCCESS = "Green"
        WARNING = "Yellow"
        ERROR   = "Red"
    }

    if ($LogFile) {
        # With file logging: add timestamp
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logMessage = "[$timestamp] [$Level] $Message"
        Write-Host $logMessage -ForegroundColor $colors[$Level]
        Add-Content -Path $LogFile -Value $logMessage -ErrorAction SilentlyContinue
    } else {
        # Console only: no timestamp
        Write-Host $Message -ForegroundColor $colors[$Level]
    }
}

function Invoke-WithRetry {
    <#
    .SYNOPSIS
    Executes a script block with retry logic.
    
    .PARAMETER ScriptBlock
    The script block to execute.
    
    .PARAMETER OperationName
    Name of the operation for logging purposes.
    
    .PARAMETER MaxRetries
    Maximum number of retry attempts.
    
    .PARAMETER DelaySeconds
    Delay in seconds between retries.
    
    .PARAMETER LogFile
    Optional path to a log file for logging.
    #>
    param(
        [scriptblock]$ScriptBlock,
        [string]$OperationName,
        [int]$MaxRetries = $Script:SharedConfig.MaxRetries,
        [int]$DelaySeconds = $Script:SharedConfig.RetryDelaySeconds,
        [string]$LogFile = $null
    )

    $attempt = 0
    $success = $false

    while (-not $success -and $attempt -lt $MaxRetries) {
        $attempt++
        try {
            $result = & $ScriptBlock
            $success = $true
            return $result
        }
        catch {
            Write-LogMessage "$OperationName attempt $attempt failed: $_" -Level WARNING -LogFile $LogFile
            if ($attempt -lt $MaxRetries) {
                Write-LogMessage "Retrying in $DelaySeconds seconds..." -Level INFO -LogFile $LogFile
                Start-Sleep -Seconds $DelaySeconds
                Update-EnvironmentPath
            }
        }
    }

    if (-not $success) {
        Write-LogMessage "$OperationName failed after $MaxRetries attempts" -Level ERROR -LogFile $LogFile
    }
    
    return $null
}

