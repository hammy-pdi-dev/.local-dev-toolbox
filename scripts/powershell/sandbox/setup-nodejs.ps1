# setup-nodejs.ps1
# Standalone script for Node.js installation and verification

# Suppress progress bars to prevent them from polluting log files
$ProgressPreference = 'SilentlyContinue'

# Try to load shared functions, fallback if not available
$sharedFunctionsPath = Join-Path $PSScriptRoot "shared-functions.ps1"
if (Test-Path $sharedFunctionsPath) {
    . $sharedFunctionsPath
} else {
    # Define minimal fallback functions for standalone use
    Write-Warning "shared-functions.ps1 not found. Using fallback functions."
    
    function Test-Administrator {
        $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }

    function Update-EnvironmentPath {
        $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
        $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
        $env:Path = "$machinePath;$userPath"
    }

    function Add-PathIfMissing {
        param([string]$Directory)
        if ($env:Path -notlike "*$Directory*") {
            $env:Path = "$Directory;$env:Path"
        }
    }

    function Write-LogMessage {
        param(
            [string]$Message,
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
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            $logMessage = "[$timestamp] [$Level] $Message"
            Write-Host $logMessage -ForegroundColor $colors[$Level]
            Add-Content -Path $LogFile -Value $logMessage -ErrorAction SilentlyContinue
        } else {
            Write-Host $Message -ForegroundColor $colors[$Level]
        }
    }
}

# CONFIGURATION
$Script:Config = @{
    NodeVersion = "14.21.3"
    LogFile = $null  # Can be set externally
    EnvironmentSettleDelay = 5
}

function Install-NodeJs {
    param(
        [string]$Version = $Script:Config.NodeVersion,
        [string]$LogFile = $Script:Config.LogFile
    )

    Write-LogMessage "Installing Node.js version $Version..." -Level INFO -LogFile $LogFile

    try {
        Write-LogMessage "Using Chocolatey to install Node.js $Version " -Level INFO -LogFile $LogFile
        choco install nodejs --version=$Version -y --force --no-progress --limit-output 2>&1 | Out-Null

        Write-LogMessage "Node.js installation completed" -Level SUCCESS -LogFile $LogFile

        # Refresh environment and wait for installation to settle
        Write-LogMessage "Refreshing environment variables..." -Level INFO -LogFile $LogFile
        Update-EnvironmentPath
        Start-Sleep -Seconds $Script:Config.EnvironmentSettleDelay

        # Verify installation
        return Test-NodeJsInstallation -LogFile $LogFile
    }
    catch {
        Write-LogMessage "Failed to install Node.js: $_" -Level ERROR -LogFile $LogFile
        return $false
    }
}

function Test-NodeJsInstallation {
    param(
        [string]$LogFile = $Script:Config.LogFile
    )

    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue

    if ($nodeCmd) {
        $nodeVersion = & node --version 2>&1
        Write-LogMessage "Node.js $nodeVersion installed at $($nodeCmd.Path)" -Level SUCCESS -LogFile $LogFile

        $npmCmd = Get-Command npm -ErrorAction SilentlyContinue
        if ($npmCmd) {
            $npmVersion = & npm --version 2>&1
            Write-LogMessage "npm $npmVersion installed at $($npmCmd.Path)" -Level SUCCESS -LogFile $LogFile
        }
        else {
            Write-LogMessage "npm command not found after Node.js installation" -Level WARNING -LogFile $LogFile
        }

        return $true
    }

    # Fallback: search common locations
    Write-LogMessage "Node.js command not found - searching for installation..." -Level WARNING -LogFile $LogFile

    $nodePaths = @(
        "$env:ProgramFiles\nodejs\node.exe",
        "${env:ProgramFiles(x86)}\nodejs\node.exe",
        "$env:ALLUSERSPROFILE\chocolatey\lib\nodejs\tools\node.exe"
    )

    foreach ($path in $nodePaths) {
        if (Test-Path $path) {
            Write-LogMessage "Found node.exe at: $path" -Level SUCCESS -LogFile $LogFile
            $nodeDir = Split-Path $path -Parent
            Add-PathIfMissing -Directory $nodeDir
            [System.Environment]::SetEnvironmentVariable("Path", $env:Path, [System.EnvironmentVariableTarget]::Process)

            $nodeVersion = & $path --version 2>&1
            Write-LogMessage "Node.js version: $nodeVersion" -Level SUCCESS -LogFile $LogFile
            return $true
        }
    }

    return $false
}

function Find-NpmExecutable {
    param(
        [string]$LogFile = $Script:Config.LogFile
    )

    Update-EnvironmentPath

    $npmPaths = @(
        (Get-Command npm -ErrorAction SilentlyContinue),
        "$env:NVM_SYMLINK\npm.cmd",
        "$env:APPDATA\nvm\nodejs\npm.cmd",
        "$env:ProgramFiles\nodejs\npm.cmd",
        "C:\Program Files\nodejs\npm.cmd"
    )

    foreach ($path in $npmPaths) {
        if ($path -and (Test-Path $path)) {
            $npmExe = if ($path.Path) { $path.Path } else { $path }
            Write-LogMessage "Found npm at: $npmExe" -Level SUCCESS -LogFile $LogFile
            return $npmExe
        }
    }

    return $null
}

function Initialize-Environment {
    param(
        [string]$Version,
        [string]$LogFile = $null
    )

    # Set log file if provided
    if ($LogFile) {
        $Script:Config.LogFile = $LogFile
    }

    # Use default version if not specified
    if (-not $Version) {
        $Version = $Script:Config.NodeVersion
    }

    # Verify Administrator privileges
    if (-not (Test-Administrator)) {
        Write-LogMessage "ERROR: Script is not running with Administrator privileges!" -Level ERROR -LogFile $Script:Config.LogFile
        Read-Host "Press Enter to exit"
        exit 1
    }

    # Check if Node.js is already installed
    $nodeAvailable = $false
    try {
        $nodeVersion = node --version 2>$null
        if ($nodeVersion) {
            Write-LogMessage "Node.js is already installed. Version: $nodeVersion" -Level SUCCESS -LogFile $Script:Config.LogFile
            $nodeAvailable = $true
        }
    }
    catch {
        # Node.js not available
    }

    if (-not $nodeAvailable) {
        # Install Node.js
        $success = Install-NodeJs -Version $Version -LogFile $Script:Config.LogFile

        if (-not $success) {
            Write-LogMessage "Node.js installation failed" -Level ERROR -LogFile $Script:Config.LogFile
            exit 1
        }
    }

    Write-LogMessage "Node.js setup completed successfully" -Level SUCCESS -LogFile $Script:Config.LogFile
}

# Run installation if executed directly (not dot-sourced)
if ($MyInvocation.InvocationName -ne '.') {
    # Check if parameters were passed via environment variables
    $version = $env:NODE_VERSION
    $logFile = $env:NODE_LOGFILE

    Initialize-Environment -Version $version -LogFile $logFile
}
