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
        
        Write-Host $Message -ForegroundColor $colors[$Level]
    }
}

# CONFIGURATION
$Script:Config = @{
    MaxRetries       = 3
    RetryDelaySeconds = 5

    # Chocolatey source configuration (can be overridden by passing parameters)
    ChocoSource = @{
        Name     = $null
        Url      = $null
        User     = $null
        Password = $null
        Priority = 1
    }
}

function Install-Chocolatey {
    Write-LogMessage "Installing Chocolatey..." -Level INFO

    try {
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            Write-LogMessage "Chocolatey is already installed" -Level SUCCESS
            return $true
        }

        Write-LogMessage "Chocolatey not found. Installing..." -Level INFO
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

        Update-EnvironmentPath
        Write-LogMessage "Chocolatey installation completed" -Level SUCCESS
        return $true
    }
    catch {
        Write-LogMessage "Failed to install Chocolatey: $_" -Level ERROR
        return $false
    }
}

function Test-ChocolateyInstallation {
    Write-LogMessage "Verifying Chocolatey installation..." -Level INFO

    try {
        $version = choco --version
        Write-LogMessage "Chocolatey version: $version" -Level SUCCESS
        return $true
    }
    catch {
        Write-LogMessage "Chocolatey verification failed: $_" -Level ERROR
        return $false
    }
}

function Add-ChocolateySource {
    param(
        [string]$Name,
        [string]$Url,
        [string]$User,
        [string]$Password,
        [int]$Priority = 1
    )

    if (-not $Name -or -not $Url) {
        Write-LogMessage "Chocolatey source name and URL are required" -Level WARNING
        return $false
    }

    Write-LogMessage "Adding custom Chocolatey source '$Name'..." -Level INFO

    try {
        $chocoArgs = @(
            "source", "add",
            "-n=`"$Name`"",
            "-s=`"$Url`"",
            "--priority=$Priority"
        )

        if ($User -and $Password) {
            $chocoArgs += "--user=`"$User`""
            $chocoArgs += "--password=`"$Password`""
        }

        & choco @chocoArgs

        Write-LogMessage "Chocolatey source '$Name' added successfully" -Level SUCCESS
        return $true
    }
    catch {
        Write-LogMessage "Failed to add Chocolatey source: $_" -Level ERROR
        return $false
    }
}

function Initialize-Environment {
    param(
        [string]$SourceName,
        [string]$SourceUrl,
        [string]$SourceUser,
        [string]$SourcePassword,
        [int]$SourcePriority = 1
    )

    # Verify Administrator privileges
    if (-not (Test-Administrator)) {
        Write-LogMessage "ERROR: Script is not running with Administrator privileges!" -Level ERROR
        Read-Host "Press Enter to exit"
        exit 1
    }

    # Check if chocolatey is already available
    $chocoAvailable = $false
    try {
        $version = choco --version 2>$null
        if ($version) {
            Write-LogMessage "Chocolatey is already installed. Version: $version" -Level SUCCESS
            $chocoAvailable = $true
        }
    }
    catch {
        # Chocolatey not available
    }

    if (-not $chocoAvailable) {
        # Install chocolatey
        Install-Chocolatey
        
        # Refresh environment and verify installation
        Update-EnvironmentPath
        Start-Sleep -Seconds 3
        
        # Verify the installation
        Test-ChocolateyInstallation
    }

    # Add custom source if provided
    if ($SourceName -and $SourceUrl) {
        Add-ChocolateySource -Name $SourceName -Url $SourceUrl -User $SourceUser -Password $SourcePassword -Priority $SourcePriority
    }
}

# Run installation if executed directly (not dot-sourced)
if ($MyInvocation.InvocationName -ne '.') {
    # Check if parameters were passed via environment variables or directly
    $sourceName = $env:CHOCO_SOURCE_NAME
    $sourceUrl = $env:CHOCO_SOURCE_URL
    $sourceUser = $env:CHOCO_SOURCE_USER
    $sourcePassword = $env:CHOCO_SOURCE_PASSWORD
    $sourcePriority = if ($env:CHOCO_SOURCE_PRIORITY) { [int]$env:CHOCO_SOURCE_PRIORITY } else { 1 }

    Initialize-Environment -SourceName $sourceName -SourceUrl $sourceUrl -SourceUser $sourceUser -SourcePassword $sourcePassword -SourcePriority $sourcePriority
}

