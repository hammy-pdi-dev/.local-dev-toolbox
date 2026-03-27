# migrate-wsl-distro.ps1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a general-purpose PowerShell script to export, re-import, and configure WSL distros under versioned names.

**Architecture:** Single self-contained script following `_update-repos.ps1` conventions — custom arg parser, `$Script:` defaults, ANSI output helpers, `Main` entry point. No external dependencies.

**Tech Stack:** PowerShell, WSL CLI (`wsl.exe`)

**Spec:** `docs/superpowers/specs/2026-03-27-migrate-wsl-distro-design.md`

---

### Task 1: Script skeleton with output helpers and argument parser

**Files:**
- Create: `scripts/powershell/wsl/migrate-wsl-distro.ps1`

- [ ] **Step 1: Create the script with strict mode, encoding, defaults, and output helpers**

```powershell
Set-StrictMode -Version Latest 2>$null

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# -------------------------------------------------------------------------
# Defaults
$Script:DefaultBackupPath  = 'C:\Backups\WSL'
$Script:DefaultInstallRoot = 'D:\WSL'
$Script:DefaultUser        = 'hammayo'
# -------------------------------------------------------------------------

$Script:ColorCodes = @{
    'Red' = 31; 'Green' = 32; 'Yellow' = 33; 'Cyan' = 36; 'White' = 37
    'BrightGreen' = 92; 'BrightRed' = 91; 'BrightCyan' = 96
}
$Script:ValidColors = @($Script:ColorCodes.Keys)

// TODO: Show Unicode as char in comment for each
$Script:Symbols = @{
    Success = "$([char]0x2705)"                        # 
    Failed  = "$([char]::ConvertFromUtf32(0x1F534))"   # 
    Info    = "$([char]0x2139)$([char]0xFE0F)"         # 
    Warning = "$([char]0x26A0)$([char]0xFE0F)"         # 
    Step    = "$([char]0x25B6)$([char]0xFE0F)"         # 
}

function Format-Text ([string]$text,
                      [ValidateScript({ $_ -in $Script:ValidColors })]
                      [string]$color = 'White')
{
    $code = $Script:ColorCodes[$color]
    if (-not $code) { $code = 37 }
    return "$([char]27)[$code`m$text$([char]27)[0m"
}

function Write-Message ([string]$text,
                       [ValidateScript({ $_ -in $Script:ValidColors })]
                       [string]$color = 'White',
                       [bool]$newLine = $true)
{
    $formatted = Format-Text -text $text -color $color
    Write-Host $formatted -NoNewline:(-not $newLine)
}

function Write-Step ([string]$text)
{
    Write-Message "$($Script:Symbols.Step) $text" 'Cyan'
}

function Write-Success ([string]$text)
{
    Write-Message "$($Script:Symbols.Success) $text" 'Green'
}

function Write-Failure ([string]$text)
{
    Write-Message "$($Script:Symbols.Failed) $text" 'Red'
}

function Exit-WithError ([string]$message)
{
    Write-Failure $message
    $global:LASTEXITCODE = 1
    return
}
```

- [ ] **Step 2: Add the argument parser**

Append below the helpers:

```powershell
$Script:RegexArgumentPattern = '^(--?[^=]+)=(.+)$'

function Get-ParsedArguments ([string[]]$argList)
{
    $result = [ordered]@{
        SourceDistro   = $null
        VersionTag     = $null
        DistroName     = $null
        BackupPath     = $Script:DefaultBackupPath
        InstallPath    = $null
        DefaultUser    = $Script:DefaultUser
        SkipUnregister = $false
        SkipExport     = $false
        Invalid        = @()
    }

    for ($i = 0; $i -lt $argList.Count; $i++) {
        $raw = $argList[$i]
        if (-not $raw) { continue }

        $namePart = $null; $valuePart = $null
        if ($raw -match $Script:RegexArgumentPattern) {
            $namePart = $Matches[1]; $valuePart = $Matches[2]
        }
        else {
            $namePart = $raw
        }

        $normalized = $namePart.TrimStart('-').ToLowerInvariant()
        switch ($normalized)
        {
            'source-distro'   { if (-not $valuePart) { if ($i + 1 -lt $argList.Count) { $valuePart = $argList[++$i] } else { $result.Invalid += $raw; break } }; $result.SourceDistro = $valuePart; continue }
            'version-tag'     { if (-not $valuePart) { if ($i + 1 -lt $argList.Count) { $valuePart = $argList[++$i] } else { $result.Invalid += $raw; break } }; $result.VersionTag = $valuePart; continue }
            'distro-name'     { if (-not $valuePart) { if ($i + 1 -lt $argList.Count) { $valuePart = $argList[++$i] } else { $result.Invalid += $raw; break } }; $result.DistroName = $valuePart; continue }
            'backup-path'     { if (-not $valuePart) { if ($i + 1 -lt $argList.Count) { $valuePart = $argList[++$i] } else { $result.Invalid += $raw; break } }; $result.BackupPath = $valuePart; continue }
            'install-path'    { if (-not $valuePart) { if ($i + 1 -lt $argList.Count) { $valuePart = $argList[++$i] } else { $result.Invalid += $raw; break } }; $result.InstallPath = $valuePart; continue }
            'default-user'    { if (-not $valuePart) { if ($i + 1 -lt $argList.Count) { $valuePart = $argList[++$i] } else { $result.Invalid += $raw; break } }; $result.DefaultUser = $valuePart; continue }
            'skip-unregister' { $result.SkipUnregister = $true; continue }
            'skip-export'     { $result.SkipExport = $true; continue }
            'help'            { Write-Usage; exit 0 }
            'h'               { Write-Usage; exit 0 }
            default           { $result.Invalid += $raw; continue }
        }
    }

    return $result
}

function Write-Usage
{
    Write-Message 'Usage: migrate-wsl-distro.ps1 --source-distro <name> --version-tag <tag> [options]' 'Cyan'
    Write-Host ''
    Write-Host '  --source-distro   Source WSL distro name (required)'
    Write-Host '  --version-tag     Version suffix e.g. v22-04 (required)'
    Write-Host '  --distro-name     Base name for target (default: derived from source)'
    Write-Host '  --backup-path     Export directory (default: C:\Backups\WSL)'
    Write-Host '  --install-path    Install directory (default: D:\WSL\<targetName>)'
    Write-Host '  --default-user    Default user (default: hammayo)'
    Write-Host '  --skip-unregister Keep the original distro'
    Write-Host '  --skip-export     Skip export, use existing tar'
    Write-Host '  --help            Show this help'
}
```

- [ ] **Step 3: Commit skeleton**

```bash
git add scripts/powershell/wsl/migrate-wsl-distro.ps1
git commit -m "Added migrate-wsl-distro.ps1 skeleton with arg parser and output helpers"
```

---

### Task 2: Core migration logic and Main entry point

**Files:**
- Modify: `scripts/powershell/wsl/migrate-wsl-distro.ps1`

- [ ] **Step 1: Add distro validation helper**

Append below `Write-Usage`:

```powershell
function Test-DistroExists ([string]$distroName)
{
    $distros = wsl --list --quiet 2>$null
    if (-not $distros) { return $false }

    # wsl --list outputs UTF-16LE with possible null chars — clean up
    $cleaned = $distros | ForEach-Object { $_.Trim("`0", ' ', "`r", "`n") } | Where-Object { $_ -ne '' }
    return $cleaned -contains $distroName
}
```

- [ ] **Step 2: Add the Main function**

```powershell
function Main ([string]$sourceDistro, [string]$versionTag, [string]$distroName,
               [string]$backupPath, [string]$installPath, [string]$defaultUser,
               [switch]$skipUnregister, [switch]$skipExport)
{
    # Derive distro name if not provided — strip trailing version pattern (e.g. -24.04, -22.04)
    if (-not $distroName) {
        $distroName = $sourceDistro -replace '-?\d+\.\d+$', ''
    }

    $targetName = "$distroName-$versionTag"
    $tarFile    = Join-Path $backupPath "$targetName-base.tar"

    if (-not $installPath) {
        $installPath = Join-Path $Script:DefaultInstallRoot $targetName
    }

    Write-Host ''
    Write-Message "Migration: $sourceDistro -> $targetName" 'BrightCyan'
    Write-Message "  Backup:  $tarFile" 'White'
    Write-Message "  Install: $installPath" 'White'
    Write-Message "  User:    $defaultUser" 'White'
    Write-Host ''

    # 1. Validate source distro
    Write-Step "Validating source distro '$sourceDistro'..."
    if (-not (Test-DistroExists $sourceDistro)) {
        Exit-WithError "Source distro '$sourceDistro' not found. Run 'wsl --list' to see available distros."
        return
    }
    Write-Success "Source distro '$sourceDistro' found"

    # 2. Export
    if (-not $skipExport) {
        Write-Step "Exporting '$sourceDistro' to '$tarFile'..."
        if (-not (Test-Path $backupPath)) {
            New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
        }
        wsl --export $sourceDistro $tarFile
        if ($LASTEXITCODE -ne 0) {
            Exit-WithError "Export failed (exit code: $LASTEXITCODE)"
            return
        }
        Write-Success "Export complete"
    }
    else {
        Write-Step "Skipping export (--skip-export)"
        if (-not (Test-Path $tarFile)) {
            Exit-WithError "Tar file not found at '$tarFile'. Cannot import without export."
            return
        }
        Write-Success "Using existing tar: $tarFile"
    }

    # 3. Import
    Write-Step "Importing '$targetName' to '$installPath'..."
    if (Test-DistroExists $targetName) {
        Exit-WithError "Target distro '$targetName' already exists. Unregister it first or choose a different version tag."
        return
    }
    wsl --import $targetName $installPath $tarFile
    if ($LASTEXITCODE -ne 0) {
        Exit-WithError "Import failed (exit code: $LASTEXITCODE)"
        return
    }
    Write-Success "Import complete"

    # 4. Configure default user
    Write-Step "Setting default user to '$defaultUser'..."
    wsl -d $targetName -- bash -c "echo -e '[user]\ndefault=$defaultUser' | tee /etc/wsl.conf"
    if ($LASTEXITCODE -ne 0) {
        Exit-WithError "Failed to configure default user (exit code: $LASTEXITCODE)"
        return
    }
    Write-Success "Default user configured"

    # 5. Unregister original
    if (-not $skipUnregister) {
        Write-Step "Unregistering original distro '$sourceDistro'..."
        wsl --unregister $sourceDistro
        if ($LASTEXITCODE -ne 0) {
            Exit-WithError "Unregister failed (exit code: $LASTEXITCODE)"
            return
        }
        Write-Success "Original distro '$sourceDistro' unregistered"
    }
    else {
        Write-Step "Skipping unregister (--skip-unregister)"
    }

    # 6. Terminate and verify
    Write-Step "Terminating '$targetName' to apply config..."
    wsl --terminate $targetName 2>$null
    Write-Success "Terminated"

    Write-Host ''
    Write-Message "$($Script:Symbols.Success) Migration complete: $targetName" 'BrightGreen'
    Write-Host ''
    Write-Step 'Current WSL distros:'
    wsl --list --verbose
}
```

- [ ] **Step 3: Add the script entry point (bottom of file)**

```powershell
# -------------------------------------------------------------------------
# Entry point
# -------------------------------------------------------------------------
$parsedArgs = Get-ParsedArguments -argList $args

if ($parsedArgs.Invalid.Count -gt 0) {
    Write-Message 'Unrecognised option(s):' 'Red'
    $parsedArgs.Invalid | ForEach-Object { Write-Message "  $_" 'Red' }
    Write-Host ''
    Write-Usage
    $global:LASTEXITCODE = 2
    return
}

if (-not $parsedArgs.SourceDistro -or -not $parsedArgs.VersionTag) {
    Write-Message 'Missing required parameters.' 'Red'
    Write-Host ''
    Write-Usage
    $global:LASTEXITCODE = 2
    return
}

Main -sourceDistro $parsedArgs.SourceDistro `
     -versionTag $parsedArgs.VersionTag `
     -distroName $parsedArgs.DistroName `
     -backupPath $parsedArgs.BackupPath `
     -installPath $parsedArgs.InstallPath `
     -defaultUser $parsedArgs.DefaultUser `
     -skipUnregister:$parsedArgs.SkipUnregister `
     -skipExport:$parsedArgs.SkipExport
```

- [ ] **Step 4: Validate syntax**

```powershell
pwsh -NoProfile -Command "& { $null = [scriptblock]::Create((Get-Content 'scripts/powershell/wsl/migrate-wsl-distro.ps1' -Raw)) ; Write-Host 'Syntax OK' }"
```

- [ ] **Step 5: Commit**

```bash
git add scripts/powershell/wsl/migrate-wsl-distro.ps1
git commit -m "Added core migration logic and Main entry point"
```

---

### Task 3: Documentation

**Files:**
- Create: `.docs/scripts/powershell/wsl/migrate-wsl-distro.md`

- [ ] **Step 1: Create the doc file**

```markdown
# migrate-wsl-distro.ps1

Export a WSL distro, re-import it under a versioned name, configure the default user, and optionally unregister the original.

## Usage

```powershell
pwsh scripts/powershell/wsl/migrate-wsl-distro.ps1 --source-distro Ubuntu --version-tag v22-04
```

## Parameters

| Parameter           | Default           | Description                                      |
|---------------------|-------------------|--------------------------------------------------|
| `--source-distro`   | *(required)*      | Existing WSL distro name                         |
| `--version-tag`     | *(required)*      | Version suffix (e.g. `v22-04`)                   |
| `--distro-name`     | Derived from source | Base name for target distro                    |
| `--backup-path`     | `C:\Backups\WSL`  | Directory for exported tar                       |
| `--install-path`    | `D:\WSL\<target>` | Install directory for new distro                 |
| `--default-user`    | `hammayo`         | Default user in `/etc/wsl.conf`                  |
| `--skip-unregister` | off               | Keep the original distro                         |
| `--skip-export`     | off               | Use existing tar file                            |
| `--help`            |                   | Show usage                                       |

## Examples

Migrate Ubuntu to Ubuntu-v22-04:

```powershell
pwsh scripts/powershell/wsl/migrate-wsl-distro.ps1 --source-distro Ubuntu --version-tag v22-04
```

Migrate Ubuntu-24.04, keep original, custom install path:

```powershell
pwsh scripts/powershell/wsl/migrate-wsl-distro.ps1 --source-distro Ubuntu-24.04 --version-tag v24-04 --skip-unregister --install-path "E:\WSL\Ubuntu-v24-04"
```

Re-import from existing backup (skip export):

```powershell
pwsh scripts/powershell/wsl/migrate-wsl-distro.ps1 --source-distro Ubuntu --version-tag v22-04 --skip-export --skip-unregister
```

## What it does

1. Validates the source distro exists
2. Exports it to `<backupPath>\<targetName>-base.tar`
3. Imports under the new name to `<installPath>`
4. Writes `/etc/wsl.conf` with the default user
5. Unregisters the original (unless `--skip-unregister`)
6. Terminates the new distro to apply config
```

- [ ] **Step 2: Commit**

```bash
git add .docs/scripts/powershell/wsl/migrate-wsl-distro.md
git commit -m "Added migrate-wsl-distro doc"
```
