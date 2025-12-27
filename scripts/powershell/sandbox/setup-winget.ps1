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

    function Test-DotNetFramework {
        $release = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full\' -ErrorAction SilentlyContinue |
                   Get-ItemPropertyValue -Name Release -ErrorAction SilentlyContinue
        return $null -ne $release
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

        Write-Host $Message -ForegroundColor $colors[$Level]
    }

    function Invoke-WithRetry {
        param(
            [scriptblock]$ScriptBlock,
            [string]$OperationName,
            [int]$MaxRetries = 3,
            [int]$DelaySeconds = 5,
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
                Write-LogMessage "$OperationName attempt $attempt failed: $_" -Level WARNING
                if ($attempt -lt $MaxRetries) {
                    Write-LogMessage "Retrying in $DelaySeconds seconds..." -Level INFO
                    Start-Sleep -Seconds $DelaySeconds
                    Update-EnvironmentPath
                }
            }
        }

        if (-not $success) {
            Write-LogMessage "$OperationName failed after $MaxRetries attempts" -Level ERROR
        }
        
        return $null
    }
}

# CONFIGURATION
$Script:Config = @{
    MaxRetries       = 3
    RetryDelaySeconds = 5
}

function Install-Winget {
    $ProgressPreference = 'SilentlyContinue'
    try {
        Write-LogMessage "Installing winget via PowerShell module..." -Level INFO

        # Install NuGet package provider
        Install-PackageProvider -Name NuGet -Force 2>&1 | Out-Null

        # Install Microsoft.WinGet.Client module
        try {
            Install-Module -Name Microsoft.WinGet.Client -Force 2>&1 | Out-Null
        }
        catch {
            # Retry without repository specification if it fails
            Install-Module -Name Microsoft.WinGet.Client -Force -SkipPublisherCheck 2>&1 | Out-Null
        }

        # Import the module
        Import-Module Microsoft.WinGet.Client 2>&1 | Out-Null

        # Repair and update winget
        Repair-WinGetPackageManager -Latest -Force 2>&1 | Out-Null

        Write-LogMessage "Winget installed successfully" -Level SUCCESS
    }
    catch {
        Write-LogMessage "Failed to install winget: $_" -Level ERROR
    }
}

function Test-WingetInstallation {
    Write-LogMessage "Verifying winget installation..." -Level INFO

    $result = Invoke-WithRetry -OperationName "winget verification" -ScriptBlock {
        $version = winget --version 2>$null
        if ($version) {
            Write-LogMessage "Winget version: $version" -Level SUCCESS
            return $true
        }

        throw "winget command returned empty"
    }

    if (-not $result) {
        Write-LogMessage "Winget verification failed" -Level ERROR
    }

    return $result
}

function Initialize-Environment {
    # Verify Administrator privileges
    if (-not (Test-Administrator)) {
        Write-LogMessage "ERROR: Script is not running with Administrator privileges!" -Level ERROR
        Read-Host "Press Enter to exit"
        exit 1
    }

    if (-not (Test-DotNetFramework)) {
        Write-LogMessage ".NET Framework not detected." -Level WARNING
    }

    # Check if winget is already available
    $wingetAvailable = $false
    try {
        $version = winget --version 2>$null
        if ($version) {
            Write-LogMessage "Winget is already installed. Version: $version" -Level SUCCESS
            $wingetAvailable = $true
        }
    }
    catch {
        # Winget not available
    }

    if (-not $wingetAvailable) {
        # Install winget
        Install-Winget

        # Refresh environment and verify installation
        Update-EnvironmentPath
        Start-Sleep -Seconds 5

        # Verify the installation
        Test-WingetInstallation

        # Upgrade all packages
        Write-LogMessage "Upgrading all winget packages..." -Level INFO
        winget upgrade --all --accept-package-agreements --accept-source-agreements --force # 2>&1 | Out-Null
        Write-LogMessage "Winget package upgrade completed" -Level SUCCESS
    }
}

# Run installation if executed directly
if ($MyInvocation.InvocationName -ne '.') {
    Initialize-Environment
}
