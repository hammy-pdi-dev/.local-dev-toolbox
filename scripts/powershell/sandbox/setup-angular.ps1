# setup-angular.ps1
# Standalone script for Angular CLI installation and verification

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
    AngularVersion = "11.0.6"
    NodeVersion = "14.21.3"
    LogFile = $null  # Can be set externally
    TempFolder = $env:TEMP
    PostInstallDelay = 3
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

function Get-AngularInstallScript {
    param(
        [string]$NpmExe,
        [string]$NpmDir,
        [string]$Version
    )

    return @"
# Set up environment variables
`$env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')
`$env:NVM_HOME = [System.Environment]::GetEnvironmentVariable('NVM_HOME','Machine')
`$env:NVM_SYMLINK = [System.Environment]::GetEnvironmentVariable('NVM_SYMLINK','Machine')

# Disable Angular CLI analytics for non-interactive installation
`$env:NG_CLI_ANALYTICS = 'false'
`$env:NG_CLI_ANALYTICS_SHARE = 'false'

# Add npm directory to PATH
`$env:Path = '$NpmDir;' + `$env:Path

Write-Host 'Installing Angular CLI $Version with analytics disabled...'
try {
    `$output = & '$NpmExe' install -g @angular/cli@$Version --no-audit --progress=false --prefer-offline --silent 2>&1

    if (`$LASTEXITCODE -ne 0) {
        Write-Host 'Attempting repair installation...'
        & '$NpmExe' uninstall -g @angular/cli 2>&1 | Out-Null
        Start-Sleep -Seconds 2
        `$output = & '$NpmExe' install -g @angular/cli@$Version --force --no-audit --silent 2>&1
    }
} catch {
    Write-Host "Error during installation: `$_"
}

`$env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')
Start-Sleep -Seconds 5

`$ngCmd = Get-Command ng -ErrorAction SilentlyContinue
if (`$ngCmd) {
    Write-Host "Angular CLI installed successfully at: `$(`$ngCmd.Path)"
    `$ngVersion = & ng version 2>&1
    Write-Host `$ngVersion
} else {
    Write-Host 'Angular CLI command not found after installation'
}
"@
}

function Install-AngularCli {
    param(
        [string]$Version = $Script:Config.AngularVersion,
        [string]$LogFile = $Script:Config.LogFile
    )

    Write-LogMessage "Installing Angular CLI version $Version..." -Level INFO -LogFile $LogFile

    try {
        $npmExe = Find-NpmExecutable -LogFile $LogFile
        if (-not $npmExe) {
            throw "npm executable not found. Node.js may not be installed correctly."
        }

        $npmDir = Split-Path $npmExe -Parent
        Write-LogMessage "npm directory: $npmDir" -Level INFO -LogFile $LogFile

        # Create installation script for separate process
        $scriptPath = Join-Path $Script:Config.TempFolder "install-angular-temp.ps1"
        $scriptContent = Get-AngularInstallScript -NpmExe $npmExe -NpmDir $npmDir -Version $Version

        Set-Content -Path $scriptPath -Value $scriptContent -Force
        Write-LogMessage "Created temporary Angular CLI installation script" -Level INFO -LogFile $LogFile

        # Execute in separate process and capture output
        Write-LogMessage "Launching Angular CLI installation..." -Level INFO -LogFile $LogFile

        # Create temporary output files for capturing verbose output
        $tempOutputFile = Join-Path $Script:Config.TempFolder "angular-install-output.txt"
        $tempErrorFile = Join-Path $Script:Config.TempFolder "angular-install-error.txt"

        $process = Start-Process powershell.exe -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$scriptPath`"" -Wait -PassThru -NoNewWindow -RedirectStandardOutput $tempOutputFile -RedirectStandardError $tempErrorFile

        # Append captured output to log file
        if (Test-Path $tempOutputFile) {
            $capturedOutput = Get-Content $tempOutputFile -Raw
            if ($capturedOutput -and $LogFile) {
                Add-Content -Path $LogFile -Value $capturedOutput -ErrorAction SilentlyContinue
            }
            Remove-Item $tempOutputFile -Force -ErrorAction SilentlyContinue
        }

        if (Test-Path $tempErrorFile) {
            $capturedError = Get-Content $tempErrorFile -Raw
            if ($capturedError -and $LogFile) {
                Add-Content -Path $LogFile -Value $capturedError -ErrorAction SilentlyContinue
            }
            Remove-Item $tempErrorFile -Force -ErrorAction SilentlyContinue
        }

        Write-LogMessage "Angular CLI installation process completed with exit code: $($process.ExitCode)" -Level INFO -LogFile $LogFile

        # Cleanup
        Remove-Item $scriptPath -Force -ErrorAction SilentlyContinue

        Write-LogMessage "Angular CLI installation completed" -Level SUCCESS -LogFile $LogFile

        # Verify installation
        Update-EnvironmentPath
        Start-Sleep -Seconds $Script:Config.PostInstallDelay

        $ngCmd = Get-Command ng -ErrorAction SilentlyContinue
        if ($ngCmd) {
            Write-LogMessage "Angular CLI verified at: $($ngCmd.Path)" -Level SUCCESS -LogFile $LogFile
            return $true
        }
        else {
            Write-LogMessage "Angular CLI installed but command not yet available - may require new PowerShell session" -Level WARNING -LogFile $LogFile
            return $true
        }
    }
    catch {
        Write-LogMessage "Failed to install Angular CLI: $_" -Level ERROR -LogFile $LogFile
        return $false
    }
}

function Initialize-Environment {
    param(
        [string]$Version,
        [string]$LogFile = $null,
        [switch]$InstallNodeJs
    )

    # Set log file if provided
    if ($LogFile) {
        $Script:Config.LogFile = $LogFile
    }

    # Use default version if not specified
    if (-not $Version) {
        $Version = $Script:Config.AngularVersion
    }

    # Verify Administrator privileges
    if (-not (Test-Administrator)) {
        Write-LogMessage "ERROR: Script is not running with Administrator privileges!" -Level ERROR -LogFile $Script:Config.LogFile
        Read-Host "Press Enter to exit"
        exit 1
    }

    # Check if Node.js is installed
    $nodeAvailable = $false
    try {
        $nodeVersion = node --version 2>$null
        if ($nodeVersion) {
            Write-LogMessage "Node.js is installed. Version: $nodeVersion" -Level SUCCESS -LogFile $Script:Config.LogFile
            $nodeAvailable = $true
        }
    }
    catch {
        # Node.js not available
    }

    if (-not $nodeAvailable) {
        Write-LogMessage "Node.js is not installed. Installing Node.js first..." -Level WARNING -LogFile $Script:Config.LogFile

        # Try to load and use setup-nodejs.ps1
        $setupNodeJsPath = Join-Path $PSScriptRoot "setup-nodejs.ps1"
        if (Test-Path $setupNodeJsPath) {
            . $setupNodeJsPath
            $success = Install-NodeJs -Version $Script:Config.NodeVersion -LogFile $Script:Config.LogFile
            if (-not $success) {
                Write-LogMessage "Failed to install Node.js. Cannot proceed with Angular CLI installation." -Level ERROR -LogFile $Script:Config.LogFile
                exit 1
            }
        } else {
            Write-LogMessage "setup-nodejs.ps1 not found. Please install Node.js manually first." -Level ERROR -LogFile $Script:Config.LogFile
            exit 1
        }
    }

    # Check if Angular CLI is already installed
    $ngAvailable = $false
    try {
        $ngVersion = ng version 2>$null
        if ($ngVersion) {
            Write-LogMessage "Angular CLI is already installed." -Level SUCCESS -LogFile $Script:Config.LogFile
            $ngAvailable = $true
        }
    }
    catch {
        # Angular CLI not available
    }

    if (-not $ngAvailable) {
        # Install Angular CLI
        $success = Install-AngularCli -Version $Version -LogFile $Script:Config.LogFile

        if (-not $success) {
            Write-LogMessage "Angular CLI installation failed" -Level ERROR -LogFile $Script:Config.LogFile
            exit 1
        }
    }

    Write-LogMessage "Angular CLI setup completed successfully" -Level SUCCESS -LogFile $Script:Config.LogFile
}

# Run installation if executed directly (not dot-sourced)
if ($MyInvocation.InvocationName -ne '.') {
    # Check if parameters were passed via environment variables
    $version = $env:ANGULAR_VERSION
    $logFile = $env:ANGULAR_LOGFILE

    Initialize-Environment -Version $version -LogFile $logFile
}
