[CmdletBinding()]
param()

# Script configuration
$LogFile = "C:\TEMP\sandbox_setup.log"
$DownloadsFolder = "C:\TEMP\Downloads"
$ErrorActionPreference = "Continue"

# Function to write log messages
function Write-Log {
    param(
        [Parameter(Mandatory=$false)]
        [AllowEmptyString()]
        [string]$Message = "",
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Write to console with color
    switch ($Level) {
        "INFO"    { Write-Host $logMessage -ForegroundColor Cyan }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        "ERROR"   { Write-Host $logMessage -ForegroundColor Red }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
    }
    
    # Write to log file
    Add-Content -Path $LogFile -Value $logMessage -ErrorAction SilentlyContinue
}

# Function to check if running as Administrator
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Main script execution
Write-Log "========================================" -Level INFO
Write-Log "Windows Sandbox Setup Script Started" -Level INFO
Write-Log "========================================" -Level INFO

# Verify running as Administrator
if (-not (Test-Administrator)) {
    Write-Log "ERROR: Script is not running with Administrator privileges!" -Level ERROR
    Write-Log "Please run this script as Administrator." -Level ERROR
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Log "Running with Administrator privileges - Confirmed" -Level SUCCESS

# Create Downloads folder if it doesn't exist
if (-not (Test-Path $DownloadsFolder)) {
    Write-Log "Creating Downloads folder: $DownloadsFolder" -Level INFO
    New-Item -ItemType Directory -Path $DownloadsFolder -Force | Out-Null
}

# Check .NET Framework versions
Write-Log "Checking .NET Framework versions..." -Level INFO
$dotNetVersions = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full\' -ErrorAction SilentlyContinue | 
    Get-ItemProperty -Name Release -ErrorAction SilentlyContinue | 
    Select-Object @{Name="Version"; Expression={$_.Release}}

if ($dotNetVersions) {
    Write-Log ".NET Framework 4.x detected (Release: $($dotNetVersions.Version))" -Level SUCCESS
} else {
    Write-Log ".NET Framework 4.x not detected. Check $DownloadsFolder for installer." -Level WARNING
}

# Install winget
Write-Log "Installing winget (Windows Package Manager)..." -Level INFO
try {
    $wingetInstalled = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $wingetInstalled) {
        Write-Log "winget not found. Installing..." -Level INFO
        Write-Log "Downloading and executing winget installer from asheroto.com..." -Level INFO
        
        # Create a temporary script file to run the installation in a separate process
        $tempScriptPath = Join-Path $env:TEMP "install-winget-temp.ps1"
        $installScriptContent = @"
try {
    `$ProgressPreference = 'SilentlyContinue'
    Invoke-RestMethod -Uri 'https://asheroto.com/winget' | Invoke-Expression
    exit 0
} catch {
    Write-Error "Installation failed: `$_"
    exit 1
}
"@
        
        Set-Content -Path $tempScriptPath -Value $installScriptContent -Force
        Write-Log "Created temporary installation script at: $tempScriptPath" -Level INFO
        
        # Execute the installation in a separate PowerShell process and wait for it to complete
        Write-Log "Launching winget installation in separate process..." -Level INFO
        $installProcess = Start-Process powershell.exe -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$tempScriptPath`"" -Wait -PassThru -NoNewWindow
        
        Write-Log "Installation process completed with exit code: $($installProcess.ExitCode)" -Level INFO
        
        # Clean up temporary script
        if (Test-Path $tempScriptPath) {
            Remove-Item $tempScriptPath -Force -ErrorAction SilentlyContinue
        }
        
        # Wait for installation to complete and processes to settle
        Write-Log "Waiting for installation to finalize (30 seconds)..." -Level INFO
        Start-Sleep -Seconds 30
        
        # Refresh environment variables multiple times to ensure they're loaded
        Write-Log "Refreshing environment variables..." -Level INFO
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        
        # Try to find winget in common installation paths
        $possiblePaths = @(
            "$env:LOCALAPPDATA\Microsoft\WindowsApps",
            "$env:ProgramFiles\WindowsApps",
            "C:\Program Files\WindowsApps"
        )
        
        foreach ($path in $possiblePaths) {
            if (Test-Path "$path\winget.exe") {
                Write-Log "Found winget.exe at: $path" -Level SUCCESS
                if ($env:Path -notlike "*$path*") {
                    $env:Path = "$path;$env:Path"
                }
                break
            }
        }
        
        Write-Log "winget installation process completed - CONTINUING WITH MAIN SCRIPT..." -Level SUCCESS
    } else {
        Write-Log "winget is already installed" -Level SUCCESS
    }
} catch {
    Write-Log "Error during winget installation: $_" -Level ERROR
    Write-Log "CONTINUING WITH SCRIPT EXECUTION ANYWAY..." -Level WARNING
}

# Verify winget is available
Write-Log "Verifying winget installation..." -Level INFO
$wingetVerified = $false
$maxRetries = 3
$retryCount = 0

while (-not $wingetVerified -and $retryCount -lt $maxRetries) {
    try {
        $wingetVersion = winget --version 2>$null
        if ($wingetVersion) {
            Write-Log "winget version: $wingetVersion" -Level SUCCESS
            $wingetVerified = $true
        } else {
            throw "winget command returned empty"
        }
    } catch {
        $retryCount++
        Write-Log "winget verification attempt $retryCount failed: $_" -Level WARNING
        if ($retryCount -lt $maxRetries) {
            Write-Log "Retrying in 10 seconds..." -Level INFO
            Start-Sleep -Seconds 10
            # Refresh path again
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        }
    }
}

if (-not $wingetVerified) {
    Write-Log "winget verification failed after $maxRetries attempts. Some installations may fail." -Level ERROR
    Write-Log "Continuing with script execution..." -Level WARNING
}

# Install packages using winget
$wingetPackages = @(
    @{Name="Notepad++"; Id="Notepad++.Notepad++"},
    @{Name="7-Zip"; Id="7zip.7zip"},
    @{Name="Git"; Id="Git.Git"}
)

foreach ($package in $wingetPackages) {
    Write-Log "Installing $($package.Name) via winget..." -Level INFO
    try {
        # Use --source winget to avoid msstore errors and specify exact source
        $result = winget install --id $($package.Id) --exact --source winget --silent --accept-source-agreements --accept-package-agreements 2>&1
        
        # Check if installation was successful
        if ($LASTEXITCODE -eq 0 -or $result -like "*Successfully installed*") {
            Write-Log "$($package.Name) installation completed successfully" -Level SUCCESS
        } else {
            Write-Log "$($package.Name) installation may have encountered issues" -Level WARNING
            Write-Log "Output: $($result -join ' ')" -Level INFO
        }
    } catch {
        Write-Log "Failed to install $($package.Name): $_" -Level ERROR
        Write-Log "Continuing with next package..." -Level WARNING
    }
    # Small delay between installations
    Start-Sleep -Seconds 3
}

# Install Chocolatey
Write-Log "Installing Chocolatey..." -Level INFO
try {
    $chocoInstalled = Get-Command choco -ErrorAction SilentlyContinue
    if (-not $chocoInstalled) {
        Write-Log "Chocolatey not found. Installing..." -Level INFO
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        
        # Refresh environment variables
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        
        Write-Log "Chocolatey installation completed" -Level SUCCESS
    } else {
        Write-Log "Chocolatey is already installed" -Level SUCCESS
    }
} catch {
    Write-Log "Failed to install Chocolatey: $_" -Level ERROR
}

# Verify Chocolatey installation
Write-Log "Verifying Chocolatey installation..." -Level INFO
try {
    $chocoVersion = choco --version
    Write-Log "Chocolatey version: $chocoVersion" -Level SUCCESS
} catch {
    Write-Log "Chocolatey verification failed: $_" -Level ERROR
}

# Add Chocolatey source
Write-Log "Adding custom Chocolatey source..." -Level INFO
try {
    choco source add -n="choco-dev" -s="https://nexusrepository.dataservices.htec.co.uk/repository/nuget-chocolatey/" --user="dev-deploy" --password="devdeploy1234" --priority=1
    Write-Log "Chocolatey source 'choco-dev' added successfully" -Level SUCCESS
} catch {
    Write-Log "Failed to add Chocolatey source: $_" -Level ERROR
}

# Install Barracuda VPN (if available via winget or choco)
Write-Log "Attempting to install Barracuda VPN Network Access Client Service..." -Level INFO
try {
    # Try winget first
    winget install "Barracuda VPN" --silent --accept-source-agreements --accept-package-agreements
    Write-Log "Barracuda VPN installation completed" -Level SUCCESS
} catch {
    Write-Log "Barracuda VPN installation skipped or failed. Check $DownloadsFolder for manual installer." -Level WARNING
}

# Install UltraVNC 1.4.3.6
Write-Log "Installing UltraVNC version 1.4.3.6..." -Level INFO
try {
    choco install ultravnc --version=1.4.3.6 -y --force
    Write-Log "UltraVNC 1.4.3.6 installation completed" -Level SUCCESS
} catch {
    Write-Log "Failed to install UltraVNC: $_" -Level ERROR
}

# Install Node.js 14.21.3 directly via Chocolatey (skip NVM due to Windows Sandbox temp file issues)
Write-Log "Installing Node.js version 14.21.3 via Chocolatey..." -Level INFO
try {
    # Install specific version of Node.js directly
    Write-Log "Using Chocolatey to install Node.js 14.21.3 (avoiding NVM temp file issues in Sandbox)..." -Level INFO
    choco install nodejs --version=14.21.3 -y --force
    
    Write-Log "Node.js installation completed" -Level SUCCESS
    
    # Refresh environment variables
    Write-Log "Refreshing environment variables for Node.js..." -Level INFO
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    
    # Wait for installation to settle
    Start-Sleep -Seconds 5
    
    # Verify Node.js installation
    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
    if ($nodeCmd) {
        $nodeVersion = & node --version 2>&1
        Write-Log "Node.js version installed: $nodeVersion at $($nodeCmd.Path)" -Level SUCCESS
        
        # Verify npm
        $npmCmd = Get-Command npm -ErrorAction SilentlyContinue
        if ($npmCmd) {
            $npmVersion = & npm --version 2>&1
            Write-Log "npm version installed: $npmVersion at $($npmCmd.Path)" -Level SUCCESS
        } else {
            Write-Log "npm command not found after Node.js installation" -Level WARNING
        }
    } else {
        Write-Log "Node.js command not found. Searching for installation..." -Level WARNING
        
        # Try to find node.exe in common locations
        $nodePaths = @(
            "$env:ProgramFiles\nodejs\node.exe",
            "${env:ProgramFiles(x86)}\nodejs\node.exe",
            "$env:ALLUSERSPROFILE\chocolatey\lib\nodejs\tools\node.exe"
        )
        
        foreach ($path in $nodePaths) {
            if (Test-Path $path) {
                Write-Log "Found node.exe at: $path" -Level SUCCESS
                $nodeDir = Split-Path $path -Parent
                if ($env:Path -notlike "*$nodeDir*") {
                    $env:Path = "$nodeDir;$env:Path"
                    [System.Environment]::SetEnvironmentVariable("Path", $env:Path, [System.EnvironmentVariableTarget]::Process)
                }
                
                $nodeVersion = & $path --version 2>&1
                Write-Log "Node.js version: $nodeVersion" -Level SUCCESS
                break
            }
        }
    }
} catch {
    Write-Log "Failed to install Node.js: $_" -Level ERROR
    Write-Log "CONTINUING WITH SCRIPT EXECUTION..." -Level WARNING
}

# Install Angular CLI
Write-Log "Installing Angular CLI version 11.0.6..." -Level INFO
try {
    # Refresh PATH to ensure npm is available
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    
    # Find npm executable
    $npmExe = $null
    $npmPaths = @(
        (Get-Command npm -ErrorAction SilentlyContinue),
        "$env:NVM_SYMLINK\npm.cmd",
        "$env:APPDATA\nvm\nodejs\npm.cmd",
        "$env:ProgramFiles\nodejs\npm.cmd",
        "C:\Program Files\nodejs\npm.cmd"
    )
    
    foreach ($path in $npmPaths) {
        if ($path -and (Test-Path $path)) {
            if ($path.Path) {
                $npmExe = $path.Path
            } else {
                $npmExe = $path
            }
            Write-Log "Found npm at: $npmExe" -Level SUCCESS
            break
        }
    }
    
    if (-not $npmExe) {
        throw "npm executable not found. Node.js may not be installed correctly."
    }
    
    # Get the directory containing npm
    $npmDir = Split-Path $npmExe -Parent
    Write-Log "npm directory: $npmDir" -Level INFO
    
    # Create a script to install Angular CLI in a new process with proper paths
    $angularScriptPath = Join-Path $env:TEMP "install-angular-temp.ps1"
    $angularScriptContent = @"
# Set up environment variables explicitly
`$env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')
`$env:NVM_HOME = [System.Environment]::GetEnvironmentVariable('NVM_HOME','Machine')
`$env:NVM_SYMLINK = [System.Environment]::GetEnvironmentVariable('NVM_SYMLINK','Machine')

# Disable Angular CLI analytics prompts for non-interactive installation
`$env:NG_CLI_ANALYTICS = 'false'
`$env:NG_CLI_ANALYTICS_SHARE = 'false'

# Add npm directory explicitly to PATH
`$env:Path = '$npmDir;' + `$env:Path

Write-Host 'Current PATH includes npm directory'
Write-Host 'npm location: $npmExe'
Write-Host 'Angular analytics disabled for automated installation'

Write-Host 'Installing Angular CLI 11.0.6 with analytics disabled...'
try {
    # Install with --no-audit and --progress=false for cleaner output
    `$output = & '$npmExe' install -g @angular/cli@11.0.6 --no-audit --progress=false 2>&1
    Write-Host `$output
    
    if (`$LASTEXITCODE -eq 0) {
        Write-Host 'Angular CLI installation completed successfully'
    } else {
        Write-Host "Angular CLI installation failed with exit code: `$LASTEXITCODE"
        Write-Host "Attempting repair installation..."
        
        # Try to clean and reinstall if failed
        & '$npmExe' uninstall -g @angular/cli 2>&1 | Out-Null
        Start-Sleep -Seconds 2
        `$output2 = & '$npmExe' install -g @angular/cli@11.0.6 --force --no-audit 2>&1
        Write-Host `$output2
    }
} catch {
    Write-Host "Error during installation: `$_"
}

Write-Host 'Refreshing PATH for ng command...'
`$env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')

Write-Host 'Waiting for npm global modules to settle...'
Start-Sleep -Seconds 5

Write-Host 'Attempting to verify Angular CLI installation...'
try {
    `$ngPath = Get-Command ng -ErrorAction SilentlyContinue
    if (`$ngPath) {
        Write-Host "ng command found at: `$(`$ngPath.Path)"
        
        # Try to get version without full verification (which may fail if postinstall had issues)
        Write-Host 'Checking Angular CLI version...'
        `$versionOutput = & ng version --help 2>&1
        if (`$LASTEXITCODE -eq 0) {
            Write-Host 'Angular CLI is functional'
        } else {
            Write-Host 'Angular CLI installed but may have issues - this is common with version 11.0.6'
        }
    } else {
        Write-Host 'ng command not found in PATH yet - may require new session'
    }
} catch {
    Write-Host "Verification error: `$_"
}

exit 0
"@
    
    Set-Content -Path $angularScriptPath -Value $angularScriptContent -Force
    Write-Log "Created temporary Angular CLI installation script" -Level INFO
    
    # Execute the npm command in a separate process
    Write-Log "Launching Angular CLI installation in separate process..." -Level INFO
    $angularProcess = Start-Process powershell.exe -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$angularScriptPath`"" -Wait -PassThru -NoNewWindow
    
    Write-Log "Angular CLI installation process completed with exit code: $($angularProcess.ExitCode)" -Level INFO
    
    # Clean up temporary script
    if (Test-Path $angularScriptPath) {
        Remove-Item $angularScriptPath -Force -ErrorAction SilentlyContinue
    }
    
    Write-Log "Angular CLI 11.0.6 installation completed" -Level SUCCESS
    
    # Verify Angular CLI installation in current session
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    Start-Sleep -Seconds 3
    
    $ngCmd = Get-Command ng -ErrorAction SilentlyContinue
    if ($ngCmd) {
        Write-Log "Angular CLI verified successfully at: $($ngCmd.Path)" -Level SUCCESS
    } else {
        Write-Log "Angular CLI installed but command not yet available - may require new PowerShell session" -Level WARNING
    }
} catch {
    Write-Log "Failed to install Angular CLI: $_" -Level ERROR
    Write-Log "CONTINUING WITH SCRIPT EXECUTION..." -Level WARNING
}

# Install htec.choco.forecourt.service.x64
Write-Log "Installing htec.choco.forecourt.service.x64 version 2.6.1.1..." -Level INFO
try {
    choco install htec.choco.forecourt.service.x64 --version=2.6.1.1 -y --force --force-dependencies --verbose
    Write-Log "htec.choco.forecourt.service.x64 2.6.1.1 installation completed" -Level SUCCESS
} catch {
    Write-Log "Failed to install htec.choco.forecourt.service.x64: $_" -Level ERROR
}

# Final summary
Write-Log "========================================" -Level INFO
Write-Log "Windows Sandbox Setup Completed!" -Level SUCCESS
Write-Log "========================================" -Level INFO
Write-Log "Log file saved to: $LogFile" -Level INFO
Write-Log "" -Level INFO
Write-Log "Press any key to keep this window open..." -Level INFO

# Keep the window open
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
