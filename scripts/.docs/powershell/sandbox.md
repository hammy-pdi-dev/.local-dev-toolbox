# Windows Sandbox Setup

An automated provisioning toolkit that configures a Windows Sandbox instance with package managers, runtimes, and enterprise software — ready for development and testing in minutes.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Files](#files)
  - [_sandbox-config.wsb](#_sandbox-configwsb)
  - [_start.bat](#_startbat)
  - [setup-wsb.ps1](#setup-wsbps1)
  - [shared-functions.ps1](#shared-functionsps1)
  - [setup-winget.ps1](#setup-wingetps1)
  - [setup-chocolatey.ps1](#setup-chocolateyps1)
  - [setup-nodejs.ps1](#setup-nodejsps1)
  - [setup-angular.ps1](#setup-angularps1)
- [Setup Pipeline](#setup-pipeline)
- [Configuration](#configuration)
- [Shared Functions](#shared-functions)
- [Standalone Usage](#standalone-usage)
- [Logging](#logging)
- [Downloads Folder](#downloads-folder)

## Overview

Windows Sandbox provides a lightweight, disposable desktop environment for testing. This toolkit automates the entire setup so that each new sandbox instance comes pre-configured with the tools needed for Forecourt Service development:

- **winget** for Microsoft Store packages
- **Chocolatey** for enterprise/internal packages (with a custom NuGet source)
- **Node.js** (pinned version) and **Angular CLI** (pinned version)
- **Azure CLI**
- **Forecourt Service** via Chocolatey

Everything is destroyed when the sandbox closes, so the setup runs from scratch each time.

## Architecture

```
Host machine                          Windows Sandbox
─────────────────                     ─────────────────
scripts/powershell/sandbox/    ──►    C:\TEMP\
  _sandbox-config.wsb                   setup-wsb.ps1  (entry point)
  _start.bat                            shared-functions.ps1
  setup-wsb.ps1                         setup-winget.ps1
  shared-functions.ps1                  setup-chocolatey.ps1
  setup-nodejs.ps1                      setup-nodejs.ps1
  setup-angular.ps1                     setup-angular.ps1
  Downloads/                            Downloads/
```

The `.wsb` config maps the sandbox folder from the host into `C:\TEMP` inside the sandbox, then runs `setup-wsb.ps1` with elevated privileges on logon.

## Quick Start

1. Enable Windows Sandbox in Windows Features (if not already enabled).
2. Double-click `_sandbox-config.wsb` to launch a new sandbox.
3. The setup script starts automatically and prompts **"Press ENTER to continue or ESC to quit"**.
4. Press Enter — the pipeline installs everything in sequence.
5. Monitor progress in the console. Logs are written to `C:\TEMP\sandbox_setup.log`.

Alternatively, use `_start.bat` to launch the setup script manually inside an already-running sandbox.

## Files

### _sandbox-config.wsb

XML configuration for Windows Sandbox. Defines:

| Setting | Value | Purpose |
|---------|-------|---------|
| Networking | Enabled | Required for downloading packages |
| Clipboard | Enabled | Copy/paste between host and sandbox |
| Memory | 8192 MB | Sufficient for Node.js builds |
| vGPU | Disabled | Not needed for CLI tooling |
| MappedFolder | Host sandbox dir to `C:\TEMP` | Makes all scripts available inside the sandbox |
| LogonCommand | `setup-wsb.ps1` (elevated) | Auto-runs the setup pipeline on sandbox start |

### _start.bat

A batch file that launches `setup-wsb.ps1` with `-ExecutionPolicy Bypass`. Use this as a manual alternative if the logon command doesn't trigger, or to re-run setup inside an existing sandbox.

### setup-wsb.ps1

The main orchestrator. It dot-sources all other setup scripts, defines the master configuration, and runs the five-phase pipeline. This is the only script you need to modify for high-level changes (which packages to install, version pins, Chocolatey source credentials).

### shared-functions.ps1

Common helper functions used by all setup scripts. See [Shared Functions](#shared-functions) for details.

### setup-winget.ps1

Installs the Windows Package Manager (winget) via the `Microsoft.WinGet.Client` PowerShell module. Handles NuGet provider installation, module import, and `Repair-WinGetPackageManager`. Can run standalone or be dot-sourced by `setup-wsb.ps1`.

### setup-chocolatey.ps1

Installs Chocolatey and optionally adds a custom NuGet source (e.g. an internal Nexus repository). Source credentials can be passed via environment variables (`CHOCO_SOURCE_NAME`, `CHOCO_SOURCE_URL`, etc.) or directly via parameters. Can run standalone.

### setup-nodejs.ps1

Installs a pinned version of Node.js via Chocolatey. Verifies the installation by checking `node --version` and `npm --version`. Falls back to searching common installation paths if the command isn't immediately on PATH. Can run standalone.

### setup-angular.ps1

Installs a pinned version of Angular CLI globally via npm. Creates a temporary PowerShell script that runs in a separate process to avoid environment variable contamination. Disables Angular analytics for non-interactive use. Depends on Node.js being installed first. Can run standalone.

## Setup Pipeline

`setup-wsb.ps1` runs five phases in sequence:

| Phase | Script | What It Does |
|-------|--------|-------------|
| 1 | `setup-winget.ps1` | Install winget package manager |
| 2 | (inline) | Install winget packages (Azure CLI, etc.) |
| 3 | `setup-chocolatey.ps1` | Install Chocolatey + add custom NuGet source |
| 4 | `setup-nodejs.ps1` + `setup-angular.ps1` | Install Node.js and Angular CLI (pinned versions) |
| 5 | (inline) | Install Forecourt Service via Chocolatey |

Each phase checks whether the tool is already installed before attempting installation. The pipeline uses `$ErrorActionPreference = "Continue"` so that a failure in one phase doesn't abort the rest.

## Configuration

All configuration is centralised in `setup-wsb.ps1`'s `$Script:Config` hashtable:

| Key | Default | Description |
|-----|---------|-------------|
| `LogFile` | `C:\TEMP\sandbox_setup.log` | Path to the log file |
| `DownloadsFolder` | `C:\TEMP\Downloads` | Working directory for downloaded installers |
| `MaxRetries` | 3 | Retry count for transient failures |
| `RetryDelaySeconds` | 5 | Seconds between retries |
| `PostInstallDelay` | 3 | Seconds to wait after each package install |
| `EnvironmentSettleDelay` | 5 | Seconds to wait after PATH refresh |
| `NodeVersion` | `14.21.3` | Pinned Node.js version |
| `AngularVersion` | `11.0.6` | Pinned Angular CLI version |
| `ForcourtVersion` | `2.6.1.1` | Pinned Forecourt Service version |
| `ChocoSource` | (hashtable) | Custom Chocolatey NuGet source (name, URL, credentials, priority) |

The `$Script:WingetPackages` array controls which winget packages are installed. Uncomment entries to add Git, Chromium, Notepad++, or 7-Zip.

## Shared Functions

`shared-functions.ps1` provides utilities used by all setup scripts:

| Function | Description |
|----------|-------------|
| `Test-Administrator` | Check if the session has elevated privileges |
| `Update-EnvironmentPath` | Reload PATH from Machine + User registry keys |
| `Add-PathIfMissing` | Add a directory to PATH if not already present |
| `Test-DotNetFramework` | Check if .NET Framework 4.x is installed |
| `Write-LogMessage` | Coloured console output with optional file logging and timestamps |
| `Invoke-WithRetry` | Execute a scriptblock with configurable retry count and delay |

Each setup script includes inline fallback definitions of these functions in case `shared-functions.ps1` is not found (e.g. when running standalone from a different directory). The fallbacks are functionally identical.

## Standalone Usage

Each setup script can run independently outside the sandbox:

```powershell
# Install just winget
.\setup-winget.ps1

# Install just Chocolatey with a custom source
$env:CHOCO_SOURCE_NAME = "my-feed"
$env:CHOCO_SOURCE_URL = "https://nexus.example.com/repository/nuget/"
.\setup-chocolatey.ps1

# Install just Node.js (specific version)
$env:NODE_VERSION = "18.19.0"
.\setup-nodejs.ps1

# Install just Angular CLI
$env:ANGULAR_VERSION = "17.0.0"
.\setup-angular.ps1
```

When dot-sourced (`. .\setup-winget.ps1`), the scripts export their functions without running the installation — useful for calling individual functions from `setup-wsb.ps1`.

## Logging

All scripts use `Write-LogMessage` for console output. When `setup-wsb.ps1` orchestrates the pipeline, it wraps this in `Write-Log` which also writes timestamped entries to `C:\TEMP\sandbox_setup.log`.

Log levels and their colours:

| Level | Colour | Usage |
|-------|--------|-------|
| `INFO` | Cyan | Progress messages |
| `SUCCESS` | Green | Completed steps |
| `WARNING` | Yellow | Non-fatal issues |
| `ERROR` | Red | Failures |

## Downloads Folder

The `Downloads/` subdirectory contains pre-downloaded installers and tools that are mapped into the sandbox:

| Item | Description |
|------|-------------|
| `Forecourt.Service/` | com0com serial port emulator installer |
| `Simulators/OPT Simulator/` | OPT hardware simulator binaries |
| `Simulators/PumpHead Simulator/` | PumpHead hardware simulator binaries |
| `Simulators/Tools/` | Supporting tools (ClearSale, DBManager, POS simulator, TMS Lite, Invenco config) |
| `Windows/` | `_download-prerequisites.bat` for fetching additional prerequisites |

These are binary dependencies that cannot be installed via package managers, so they are included directly in the mapped folder.
