[CmdletBinding()]
param()

# Dot-source shared functions first
$sharedFunctionsPath = Join-Path $PSScriptRoot "shared-functions.ps1"
if (Test-Path $sharedFunctionsPath) {
    . $sharedFunctionsPath
}

# Dot-source setup scripts to reuse their specific functions
$setupWingetPath = Join-Path $PSScriptRoot "setup-winget.ps1"
if (Test-Path $setupWingetPath) {
    . $setupWingetPath
}

$setupChocolateyPath = Join-Path $PSScriptRoot "setup-chocolatey.ps1"
if (Test-Path $setupChocolateyPath) {
    . $setupChocolateyPath
}

$setupNodeJsPath = Join-Path $PSScriptRoot "setup-nodejs.ps1"
if (Test-Path $setupNodeJsPath) {
    . $setupNodeJsPath
}

$setupAngularPath = Join-Path $PSScriptRoot "setup-angular.ps1"
if (Test-Path $setupAngularPath) {
    . $setupAngularPath
}

# CONFIGURATION

$Script:Config = @{
    # Paths
    LogFile          = "C:\TEMP\sandbox_setup.log"
    DownloadsFolder  = "C:\TEMP\Downloads"
    TempFolder       = $env:TEMP

    # Retry settings
    MaxRetries       = 3
    RetryDelaySeconds = 5

    # Installation delays
    PostInstallDelay = 3
    EnvironmentSettleDelay = 5
    WingetFinalizeDelay = 5

    # Chocolatey source configuration
    ChocoSource = @{
        Name     = "choco-dev"
        Url      = "https://nexusrepository.dataservices.htec.co.uk/repository/nuget-chocolatey/"
        User     = "dev-deploy"
        Password = "devdeploy1234"
        Priority = 1
    }

    # Version requirements
    NodeVersion      = "14.21.3"
    AngularVersion   = "11.0.6"
    ForcourtVersion  = "2.6.1.1"
}

# Winget packages to install
$Script:WingetPackages = @(
    @{ Name = "Azure CLI";   Id = "Microsoft.AzureCLI" }
    @{ Name = "Chromium";    Id = "Hibbiki.Chromium" }
    @{ Name = "Git";         Id = "Git.Git" }
    @{ Name = "Notepad++";   Id = "Notepad++.Notepad++" }
    @{ Name = "7-Zip";       Id = "7zip.7zip" }
)

$ErrorActionPreference = "Continue"

# Wrapper function for Write-LogMessage with file logging for backward compatibility
function Write-Log {
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Message = "",

        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )

    # Call the shared Write-LogMessage function with file logging
    Write-LogMessage -Message $Message -Level $Level -LogFile $Script:Config.LogFile
}

# Test-Administrator, Update-EnvironmentPath, Add-PathIfMissing, Test-DotNetFramework, and Invoke-WithRetry are now imported from shared-functions.ps1

# Wrapper for Invoke-WithRetry to use with file logging
function Invoke-WithRetry {
    param(
        [scriptblock]$ScriptBlock,
        [string]$OperationName,
        [int]$MaxRetries = $Script:Config.MaxRetries,
        [int]$DelaySeconds = $Script:Config.RetryDelaySeconds
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
            Write-Log "$OperationName attempt $attempt failed: $_" -Level WARNING
            if ($attempt -lt $MaxRetries) {
                Write-Log "Retrying in $DelaySeconds seconds..." -Level INFO
                Start-Sleep -Seconds $DelaySeconds
                Update-EnvironmentPath
            }
        }
    }

    if (-not $success) {
        Write-Log "$OperationName failed after $MaxRetries attempts" -Level ERROR
    }
    return $null
}

# Install-Winget and Test-WingetInstallation are now handled by setup-winget.ps1

function Initialize-WingetSetup {
    Write-Log "[PHASE 1] Setting up winget package manager..." -Level INFO

    # Check if winget is already installed
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Log "Winget not found - installing via setup-winget.ps1" -Level INFO
        $setupWingetScriptPath = Join-Path $PSScriptRoot "setup-winget.ps1"
        if (Test-Path $setupWingetScriptPath) {
            try {
                # Create temporary output files for capturing verbose output
                $tempOutputFile = Join-Path $env:TEMP "winget-setup-output.txt"
                $tempErrorFile = Join-Path $env:TEMP "winget-setup-error.txt"

                # Execute setup-winget.ps1 and redirect output to temp files
                $process = Start-Process powershell.exe -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$setupWingetScriptPath`"" -Wait -PassThru -NoNewWindow -RedirectStandardOutput $tempOutputFile -RedirectStandardError $tempErrorFile

                # Append captured output to log file
                if (Test-Path $tempOutputFile) {
                    $capturedOutput = Get-Content $tempOutputFile -Raw
                    if ($capturedOutput) {
                        Add-Content -Path $Script:Config.LogFile -Value $capturedOutput -ErrorAction SilentlyContinue
                    }
                    Remove-Item $tempOutputFile -Force -ErrorAction SilentlyContinue
                }

                if (Test-Path $tempErrorFile) {
                    $capturedError = Get-Content $tempErrorFile -Raw
                    if ($capturedError) {
                        Add-Content -Path $Script:Config.LogFile -Value $capturedError -ErrorAction SilentlyContinue
                    }
                    Remove-Item $tempErrorFile -Force -ErrorAction SilentlyContinue
                }

                if ($process.ExitCode -eq 0) {
                    Write-Log "Winget setup completed successfully" -Level SUCCESS
                    # Refresh environment after installation
                    Update-EnvironmentPath
                    Start-Sleep -Seconds $Script:Config.WingetFinalizeDelay
                } else {
                    Write-Log "Winget setup exited with code: $($process.ExitCode)" -Level WARNING
                }
            }
            catch {
                Write-Log "Error running setup-winget.ps1: $_" -Level ERROR
                Write-Log "Attempting to continue" -Level WARNING
            }
        } else {
            Write-Log "setup-winget.ps1 not found at: $setupWingetScriptPath" -Level ERROR
            Write-Log "Attempting to continue without winget setup" -Level WARNING
        }
    } else {
        Write-Log "Winget is already installed" -Level SUCCESS
    }
}

function Install-WingetPackage {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Package
    )

    Write-Log "Installing $($Package.Name)..." -Level INFO

    try {
        # Run winget directly without piping to preserve inline progress updates
        & winget install --id $($Package.Id) --exact --source winget --disable-interactivity --accept-source-agreements --accept-package-agreements

        if ($LASTEXITCODE -eq 0) {
            Write-Log "$($Package.Name) installed successfully" -Level SUCCESS
            return $true
        }
        else {
            Write-Log "$($Package.Name) installation may have encountered issues" -Level WARNING
            return $false
        }
    }
    catch {
        Write-Log "Failed to install $($Package.Name): $_" -Level ERROR
        return $false
    }
}

function Install-AllWingetPackages {
    param([array]$Packages)

    Write-Log "[PHASE 2] Installing winget packages..." -Level INFO

    foreach ($package in $Packages) {
        $null = Install-WingetPackage -Package $package
        Start-Sleep -Seconds $Script:Config.PostInstallDelay
    }
}

function Initialize-ChocolateySetup {
    Write-Log "[PHASE 3] Setting up Chocolatey package manager..." -Level INFO

    # Check if chocolatey is already installed
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Log "Chocolatey not found - installing via setup-chocolatey.ps1" -Level INFO
        $setupChocolateyScriptPath = Join-Path $PSScriptRoot "setup-chocolatey.ps1"
        if (Test-Path $setupChocolateyScriptPath) {
            try {
                # Set environment variables for chocolatey source configuration
                $env:CHOCO_SOURCE_NAME = $Script:Config.ChocoSource.Name
                $env:CHOCO_SOURCE_URL = $Script:Config.ChocoSource.Url
                $env:CHOCO_SOURCE_USER = $Script:Config.ChocoSource.User
                $env:CHOCO_SOURCE_PASSWORD = $Script:Config.ChocoSource.Password
                $env:CHOCO_SOURCE_PRIORITY = $Script:Config.ChocoSource.Priority

                # Create temporary output files for capturing verbose output
                $tempOutputFile = Join-Path $env:TEMP "chocolatey-setup-output.txt"
                $tempErrorFile = Join-Path $env:TEMP "chocolatey-setup-error.txt"

                # Execute setup-chocolatey.ps1 and redirect output to temp files
                $process = Start-Process powershell.exe -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$setupChocolateyScriptPath`"" -Wait -PassThru -NoNewWindow -RedirectStandardOutput $tempOutputFile -RedirectStandardError $tempErrorFile

                # Append captured output to log file
                if (Test-Path $tempOutputFile) {
                    $capturedOutput = Get-Content $tempOutputFile -Raw
                    if ($capturedOutput) {
                        Add-Content -Path $Script:Config.LogFile -Value $capturedOutput -ErrorAction SilentlyContinue
                    }
                    Remove-Item $tempOutputFile -Force -ErrorAction SilentlyContinue
                }

                if (Test-Path $tempErrorFile) {
                    $capturedError = Get-Content $tempErrorFile -Raw
                    if ($capturedError) {
                        Add-Content -Path $Script:Config.LogFile -Value $capturedError -ErrorAction SilentlyContinue
                    }
                    Remove-Item $tempErrorFile -Force -ErrorAction SilentlyContinue
                }

                # Clean up environment variables
                Remove-Item Env:\CHOCO_SOURCE_NAME -ErrorAction SilentlyContinue
                Remove-Item Env:\CHOCO_SOURCE_URL -ErrorAction SilentlyContinue
                Remove-Item Env:\CHOCO_SOURCE_USER -ErrorAction SilentlyContinue
                Remove-Item Env:\CHOCO_SOURCE_PASSWORD -ErrorAction SilentlyContinue
                Remove-Item Env:\CHOCO_SOURCE_PRIORITY -ErrorAction SilentlyContinue

                if ($process.ExitCode -eq 0) {
                    Write-Log "Chocolatey setup completed successfully" -Level SUCCESS
                    # Refresh environment after installation
                    Update-EnvironmentPath
                    Start-Sleep -Seconds 3
                } else {
                    Write-Log "Chocolatey setup exited with code: $($process.ExitCode)" -Level WARNING
                }
            }
            catch {
                Write-Log "Error running setup-chocolatey.ps1: $_" -Level ERROR
                Write-Log "Attempting to continue" -Level WARNING
            }
        } else {
            Write-Log "setup-chocolatey.ps1 not found at: $setupChocolateyScriptPath" -Level ERROR
            Write-Log "Attempting to continue without Chocolatey setup" -Level WARNING
        }
    } else {
        Write-Log "Chocolatey is already installed" -Level SUCCESS

        # Add custom source if chocolatey is already installed
        $source = $Script:Config.ChocoSource
        if ($source.Name -and $source.Url) {
            Write-Log "Adding custom Chocolatey source '$($source.Name)'" -Level INFO
            try {
                $output = choco source add -n="$($source.Name)" -s="$($source.Url)" --user="$($source.User)" --password="$($source.Password)" --priority=$($source.Priority) 2>&1
                Add-Content -Path $Script:Config.LogFile -Value $output -ErrorAction SilentlyContinue
                Write-Log "Chocolatey source added successfully" -Level SUCCESS
            }
            catch {
                Write-Log "Failed to add Chocolatey source: $_" -Level WARNING
            }
        }
    }
}


function Install-ForcourtService {
    param(
        [string]$Version = $Script:Config.ForcourtVersion
    )

    Write-Log "Installing htec.choco.forecourt.service.x64 version $Version..." -Level INFO

    try {
        # Run chocolatey directly without piping to preserve inline progress updates
        & choco install htec.choco.forecourt.service.x64 --version=$Version -y --force --force-dependencies

        Write-Log "Forecourt service installation completed" -Level SUCCESS
        return $true
    }
    catch {
        Write-Log "Failed to install forecourt service: $_" -Level ERROR
        return $false
    }
}

function Initialize-Environment {
    Write-Log "========================================" -Level INFO
    Write-Log "Windows Sandbox Setup Script" -Level INFO
    Write-Log "========================================" -Level INFO

    # Verify Administrator privileges
    if (-not (Test-Administrator)) {
        Write-Log "ERROR: Script is not running with Administrator privileges!" -Level ERROR
        Write-Log "Please run this script as Administrator" -Level ERROR
        Read-Host "Press Enter to exit"
        exit 1
    }

    Write-Log "Administrator privileges confirmed" -Level SUCCESS

    # Create required directories
    if (-not (Test-Path $Script:Config.DownloadsFolder)) {
        Write-Log "Creating downloads folder: $($Script:Config.DownloadsFolder)" -Level INFO
        New-Item -ItemType Directory -Path $Script:Config.DownloadsFolder -Force | Out-Null
    }

    # Check .NET Framework
    if (-not (Test-DotNetFramework)) {
        Write-Log ".NET Framework 4.6.1 or 4.8 not detected - adding .NET SDK to install list" -Level WARNING
        $Script:WingetPackages += @{ Name = "Dotnet 8 SDK"; Id = "Microsoft.DotNet.SDK.8" }
    }
}

function Wait-UserConfirmation {
    Write-Log "" -Level INFO
    Write-Log "Ready to begin setup pipeline?" -Level INFO
    Write-Log "Press ENTER to continue or ESC to quit" -Level INFO

    # Wait for user input
    do {
        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        if ($key.VirtualKeyCode -eq 13) {
            # Enter key pressed - continue
            Write-Log "" -Level INFO
            Write-Log "Starting setup pipeline..." -Level INFO
            Write-Log "" -Level INFO
            return
        }
        elseif ($key.VirtualKeyCode -eq 27) {
            # Escape key pressed - quit
            Write-Log "Setup cancelled by user" -Level WARNING
            exit 0
        }
    } while ($true)
}

function Invoke-SetupPipeline {
    # Prompt user for confirmation before starting
    Wait-UserConfirmation

    # Phase 1: Package Managers - Setup Winget
    Initialize-WingetSetup

    # Phase 2: Winget Packages
    Install-AllWingetPackages -Packages $Script:WingetPackages

    # Phase 3: Chocolatey Setup
    Initialize-ChocolateySetup

    # Phase 4: Prerequisite libs and Tools
    Write-Log "[PHASE 4] Installing prerequisite..." -Level INFO

    $null = Install-NodeJs -Version $Script:Config.NodeVersion -LogFile $Script:Config.LogFile
    $null = Install-AngularCli -Version $Script:Config.AngularVersion -LogFile $Script:Config.LogFile
    
    #Install-Com0Com # i.e download com0com https://sourceforge.net/projects/com0com/files/com0com/3.0.0.0/com0com-3.0.0.0-i386-and-x64-signed.zip/download and extract in C:\TEMP\com0com_x64-signed_v3

    # Phase 5: Enterprise Software
    Write-Log "[PHASE 5] Installing Forecourt service..." -Level INFO
    $null = Install-ForcourtService
}

function Show-CompletionSummary {
    Write-Log "========================================" -Level INFO
    Write-Log "Setup Completed Successfully!" -Level SUCCESS
    Write-Log "========================================" -Level INFO
    Write-Log "Log file: $($Script:Config.LogFile)" -Level INFO
    Write-Log "" -Level INFO
    Write-Log "Press any key to exit..." -Level INFO

    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# Execute main setup
Initialize-Environment
Invoke-SetupPipeline
Show-CompletionSummary
