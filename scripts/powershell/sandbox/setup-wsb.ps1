[CmdletBinding()]
param()

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

function Write-Log {
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Message = "",

        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"

    $colorMap = @{
        "INFO"    = "Cyan"
        "WARNING" = "Yellow"
        "ERROR"   = "Red"
        "SUCCESS" = "Green"
    }

    Write-Host $logMessage -ForegroundColor $colorMap[$Level]
    Add-Content -Path $Script:Config.LogFile -Value $logMessage -ErrorAction SilentlyContinue
}

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

function Install-Winget {
    Write-Log "Installing winget (Windows Package Manager)..." -Level INFO

    try {
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Log "winget is already installed" -Level SUCCESS
            return $true
        }

        Write-Log "winget not found. Installing..." -Level INFO
        Write-Log "Downloading and executing winget installer from asheroto.com..." -Level INFO

        # Create temporary installation script
        $tempScriptPath = Join-Path $Script:Config.TempFolder "install-winget-temp.ps1"
        $installScriptContent = @'
try {
    $ProgressPreference = 'SilentlyContinue'
    Invoke-RestMethod -Uri 'https://asheroto.com/winget' | Invoke-Expression
    exit 0
} catch {
    Write-Error "Installation failed: $_"
    exit 1
}
'@

        Set-Content -Path $tempScriptPath -Value $installScriptContent -Force
        Write-Log "Created temporary installation script at: $tempScriptPath" -Level INFO

        # Execute installation in separate process
        Write-Log "Launching winget installation in separate process..." -Level INFO
        $process = Start-Process powershell.exe -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$tempScriptPath`"" -Wait -PassThru -NoNewWindow
        Write-Log "Installation process completed with exit code: $($process.ExitCode)" -Level INFO

        # Cleanup
        Remove-Item $tempScriptPath -Force -ErrorAction SilentlyContinue

        # Finalize installation
        Write-Log "Waiting for installation to finalize ($($Script:Config.WingetFinalizeDelay) seconds)..." -Level INFO
        Start-Sleep -Seconds $Script:Config.WingetFinalizeDelay

        Write-Log "Refreshing environment variables..." -Level INFO
        Update-EnvironmentPath

        # Find winget in common paths
        $wingetPaths = @(
            "$env:LOCALAPPDATA\Microsoft\WindowsApps",
            "$env:ProgramFiles\WindowsApps",
            "C:\Program Files\WindowsApps"
        )

        foreach ($path in $wingetPaths) {
            if (Test-Path "$path\winget.exe") {
                Write-Log "Found winget.exe at: $path" -Level SUCCESS
                Add-PathIfMissing -Directory $path
                break
            }
        }

        Write-Log "winget installation process completed" -Level SUCCESS
        return $true
    }
    catch {
        Write-Log "Error during winget installation: $_" -Level ERROR
        Write-Log "Continuing with script execution..." -Level WARNING
        return $false
    }
}

function Test-WingetInstallation {
    Write-Log "Verifying winget installation..." -Level INFO

    $result = Invoke-WithRetry -OperationName "winget verification" -ScriptBlock {
        $version = winget --version 2>$null
        if ($version) {
            Write-Log "winget version: $version" -Level SUCCESS
            return $true
        }
        throw "winget command returned empty"
    }

    if (-not $result) {
        Write-Log "winget verification failed. Some installations may fail." -Level ERROR
    }

    return $result
}

function Install-WingetPackage {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Package
    )

    Write-Log "Installing $($Package.Name) via winget..." -Level INFO

    try {
        $result = winget install --id $($Package.Id) --exact --source winget --silent --disable-interactivity --accept-source-agreements --accept-package-agreements 2>&1

        if ($LASTEXITCODE -eq 0 -or $result -like "*Successfully installed*") {
            Write-Log "$($Package.Name) installation completed successfully" -Level SUCCESS
            return $true
        }
        else {
            Write-Log "$($Package.Name) installation may have encountered issues" -Level WARNING
            Write-Log "Output: $($result -join ' ')" -Level INFO
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

    foreach ($package in $Packages) {
        Install-WingetPackage -Package $package
        Start-Sleep -Seconds $Script:Config.PostInstallDelay
    }
}

function Install-Chocolatey {
    Write-Log "Installing Chocolatey..." -Level INFO

    try {
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            Write-Log "Chocolatey is already installed" -Level SUCCESS
            return $true
        }

        Write-Log "Chocolatey not found. Installing..." -Level INFO
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

        Update-EnvironmentPath
        Write-Log "Chocolatey installation completed" -Level SUCCESS
        return $true
    }
    catch {
        Write-Log "Failed to install Chocolatey: $_" -Level ERROR
        return $false
    }
}

function Test-ChocolateyInstallation {
    Write-Log "Verifying Chocolatey installation..." -Level INFO

    try {
        $version = choco --version
        Write-Log "Chocolatey version: $version" -Level SUCCESS
        return $true
    }
    catch {
        Write-Log "Chocolatey verification failed: $_" -Level ERROR
        return $false
    }
}

function Add-ChocolateySource {
    Write-Log "Adding custom Chocolatey source..." -Level INFO

    $source = $Script:Config.ChocoSource

    try {
        choco source add -n="$($source.Name)" -s="$($source.Url)" --user="$($source.User)" --password="$($source.Password)" --priority=$($source.Priority)
        Write-Log "Chocolatey source '$($source.Name)' added successfully" -Level SUCCESS
        return $true
    }
    catch {
        Write-Log "Failed to add Chocolatey source: $_" -Level ERROR
        return $false
    }
}

function Install-NodeJs {
    param(
        [string]$Version = $Script:Config.NodeVersion
    )

    Write-Log "Installing Node.js version $Version via Chocolatey..." -Level INFO

    try {
        Write-Log "Using Chocolatey to install Node.js $Version (avoiding NVM temp file issues in Sandbox)..." -Level INFO
        choco install nodejs --version=$Version -y --force --no-progress --limit-output

        Write-Log "Node.js installation completed" -Level SUCCESS

        # Refresh environment and wait for installation to settle
        Write-Log "Refreshing environment variables for Node.js..." -Level INFO
        Update-EnvironmentPath
        Start-Sleep -Seconds $Script:Config.EnvironmentSettleDelay

        # Verify installation
        return Test-NodeJsInstallation
    }
    catch {
        Write-Log "Failed to install Node.js: $_" -Level ERROR
        return $false
    }
}

function Test-NodeJsInstallation {
    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue

    if ($nodeCmd) {
        $nodeVersion = & node --version 2>&1
        Write-Log "Node.js version installed: $nodeVersion at $($nodeCmd.Path)" -Level SUCCESS

        $npmCmd = Get-Command npm -ErrorAction SilentlyContinue
        if ($npmCmd) {
            $npmVersion = & npm --version 2>&1
            Write-Log "npm version installed: $npmVersion at $($npmCmd.Path)" -Level SUCCESS
        }
        else {
            Write-Log "npm command not found after Node.js installation" -Level WARNING
        }
        return $true
    }

    # Fallback: search common locations
    Write-Log "Node.js command not found. Searching for installation..." -Level WARNING

    $nodePaths = @(
        "$env:ProgramFiles\nodejs\node.exe",
        "${env:ProgramFiles(x86)}\nodejs\node.exe",
        "$env:ALLUSERSPROFILE\chocolatey\lib\nodejs\tools\node.exe"
    )

    foreach ($path in $nodePaths) {
        if (Test-Path $path) {
            Write-Log "Found node.exe at: $path" -Level SUCCESS
            $nodeDir = Split-Path $path -Parent
            Add-PathIfMissing -Directory $nodeDir
            [System.Environment]::SetEnvironmentVariable("Path", $env:Path, [System.EnvironmentVariableTarget]::Process)

            $nodeVersion = & $path --version 2>&1
            Write-Log "Node.js version: $nodeVersion" -Level SUCCESS
            return $true
        }
    }

    return $false
}

function Find-NpmExecutable {
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
            Write-Log "Found npm at: $npmExe" -Level SUCCESS
            return $npmExe
        }
    }

    return $null
}

function Install-AngularCli {
    param(
        [string]$Version = $Script:Config.AngularVersion
    )

    Write-Log "Installing Angular CLI version $Version..." -Level INFO

    try {
        $npmExe = Find-NpmExecutable
        if (-not $npmExe) {
            throw "npm executable not found. Node.js may not be installed correctly."
        }

        $npmDir = Split-Path $npmExe -Parent
        Write-Log "npm directory: $npmDir" -Level INFO

        # Create installation script for separate process
        $scriptPath = Join-Path $Script:Config.TempFolder "install-angular-temp.ps1"
        $scriptContent = Get-AngularInstallScript -NpmExe $npmExe -NpmDir $npmDir -Version $Version

        Set-Content -Path $scriptPath -Value $scriptContent -Force
        Write-Log "Created temporary Angular CLI installation script" -Level INFO

        # Execute in separate process
        Write-Log "Launching Angular CLI installation in separate process..." -Level INFO
        $process = Start-Process powershell.exe -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$scriptPath`"" -Wait -PassThru -NoNewWindow
        Write-Log "Angular CLI installation process completed with exit code: $($process.ExitCode)" -Level INFO

        # Cleanup
        Remove-Item $scriptPath -Force -ErrorAction SilentlyContinue

        Write-Log "Angular CLI $Version installation completed" -Level SUCCESS

        # Verify installation
        Update-EnvironmentPath
        Start-Sleep -Seconds $Script:Config.PostInstallDelay

        $ngCmd = Get-Command ng -ErrorAction SilentlyContinue
        if ($ngCmd) {
            Write-Log "Angular CLI verified successfully at: $($ngCmd.Path)" -Level SUCCESS
            return $true
        }
        else {
            Write-Log "Angular CLI installed but command not yet available - may require new PowerShell session" -Level WARNING
            return $true
        }
    }
    catch {
        Write-Log "Failed to install Angular CLI: $_" -Level ERROR
        return $false
    }
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
    `$output = & '$NpmExe' install -g @angular/cli@$Version --no-audit --progress=false --prefer-offline 2>&1
    Write-Host `$output

    if (`$LASTEXITCODE -ne 0) {
        Write-Host 'Attempting repair installation...'
        & '$NpmExe' uninstall -g @angular/cli 2>&1 | Out-Null
        Start-Sleep -Seconds 2
        & '$NpmExe' install -g @angular/cli@$Version --force --no-audit 2>&1
    }
} catch {
    Write-Host "Error during installation: `$_"
}

`$env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')
Start-Sleep -Seconds 5

`$ngPath = Get-Command ng -ErrorAction SilentlyContinue
if (`$ngPath) {
    Write-Host "Angular CLI found at: `$(`$ngPath.Path)"
}
exit 0
"@
}

function Install-ForcourtService {
    param(
        [string]$Version = $Script:Config.ForcourtVersion
    )

    Write-Log "Installing htec.choco.forecourt.service.x64 version $Version..." -Level INFO

    try {
        choco install htec.choco.forecourt.service.x64 --version=$Version -y --force --force-dependencies --verbose
        Write-Log "htec.choco.forecourt.service.x64 $Version installation completed" -Level SUCCESS
        return $true
    }
    catch {
        Write-Log "Failed to install htec.choco.forecourt.service.x64: $_" -Level ERROR
        return $false
    }
}

function Initialize-Environment {
    Write-Log "========================================" -Level INFO
    Write-Log "Windows Sandbox Setup Script Started" -Level INFO
    Write-Log "========================================" -Level INFO

    # Verify Administrator privileges
    if (-not (Test-Administrator)) {
        Write-Log "ERROR: Script is not running with Administrator privileges!" -Level ERROR
        Write-Log "Please run this script as Administrator." -Level ERROR
        Read-Host "Press Enter to exit"
        exit 1
    }

    Write-Log "Running with Administrator privileges - Confirmed" -Level SUCCESS

    # Create required directories
    if (-not (Test-Path $Script:Config.DownloadsFolder)) {
        Write-Log "Creating Downloads folder: $($Script:Config.DownloadsFolder)" -Level INFO
        New-Item -ItemType Directory -Path $Script:Config.DownloadsFolder -Force | Out-Null
    }

    # Check .NET Framework
    if (-not (Test-DotNetFramework)) {
        Write-Log ".NET Framework 4.6.1 or 4.8 not detected. Adding .NET SDK to install list." -Level WARNING
        $Script:WingetPackages += @{ Name = "Dotnet 8 SDK"; Id = "Microsoft.DotNet.SDK.8" }
    }
}

function Wait-UserConfirmation {
    Write-Log "========================================" -Level INFO
    Write-Log "Ready to begin setup pipeline" -Level INFO
    Write-Log "Press ENTER to continue or ESC to quit..." -Level INFO
    Write-Log "========================================" -Level INFO

    # Wait for user input
    do {
        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        if ($key.VirtualKeyCode -eq 13) {
            # Enter key pressed - continue
            Write-Log "Starting setup pipeline..." -Level INFO
            return $true
        }
        elseif ($key.VirtualKeyCode -eq 27) {
            # Escape key pressed - quit
            Write-Log "Setup cancelled by user." -Level WARNING
            exit 0
        }
    } while ($true)
}

function Invoke-SetupPipeline {
    # Prompt user for confirmation before starting
    Wait-UserConfirmation

    # Phase 1: Package Managers
    Install-Winget
    Test-WingetInstallation

    # Phase 2: Winget Packages
    Install-AllWingetPackages -Packages $Script:WingetPackages

    # Phase 3: Chocolatey Setup
    Install-Chocolatey
    Test-ChocolateyInstallation
    Add-ChocolateySource

    # Phase 4: Development Tools
    Install-NodeJs
    Install-AngularCli
    #Install-Com0Com # i.e download com0com https://sourceforge.net/projects/com0com/files/com0com/3.0.0.0/com0com-3.0.0.0-i386-and-x64-signed.zip/download and extract in C:\TEMP\com0com_x64-signed_v3

    # Phase 5: Enterprise Software
    Install-ForcourtService
}

function Show-CompletionSummary {
    Write-Log "========================================" -Level INFO
    Write-Log "Windows Sandbox Setup Completed!" -Level SUCCESS
    Write-Log "========================================" -Level INFO
    Write-Log "Log file saved to: $($Script:Config.LogFile)" -Level INFO
    Write-Log "" -Level INFO
    Write-Log "Press any key to keep this window open..." -Level INFO

    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# Execute main setup
Initialize-Environment
Invoke-SetupPipeline
Show-CompletionSummary
