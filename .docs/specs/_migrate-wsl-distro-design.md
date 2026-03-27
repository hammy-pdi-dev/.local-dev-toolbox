# Design: migrate-wsl-distro.ps1

## Overview

A general-purpose PowerShell script to export a WSL distro, re-import it under a versioned name (`<distroName>-<versionTag>`), configure the default user, and optionally unregister the original. Lives at `scripts/powershell/wsl/migrate-wsl-distro.ps1`.

## Parameters

| CLI arg             | Default                              | Required | Description                                                                 |
|---------------------|--------------------------------------|----------|-----------------------------------------------------------------------------|
| `--source-distro`   | —                                    | Yes      | Name of the existing WSL distro (e.g. `Ubuntu`, `Ubuntu-24.04`)             |
| `--version-tag`     | —                                    | Yes      | Version suffix (e.g. `v22-04`, `v24-04`)                                    |
| `--distro-name`     | Derived from `--source-distro`       | No       | Base name for target distro — defaults to source with trailing version stripped (e.g. `Ubuntu-24.04` → `Ubuntu`) |
| `--backup-path`     | `C:\Backups\WSL`                     | No       | Directory for the exported `.tar` file                                      |
| `--install-path`    | `D:\WSL\<targetName>`                | No       | Install directory for the new distro                                        |
| `--default-user`    | `hammayo`                            | No       | Default user set in `/etc/wsl.conf`                                         |
| `--skip-unregister` | `$false`                             | No       | Keep the original distro after import                                       |
| `--skip-export`     | `$false`                             | No       | Skip export step — expects an existing tar at backup path                   |

**Target distro name** is computed as `$DistroName-$VersionTag` (e.g. `Ubuntu-v24-04`).

**Tar file name** is `<targetName>-base.tar` (e.g. `Ubuntu-v24-04-base.tar`).

## Execution Steps

1. **Validate** — Confirm source distro exists via `wsl --list --quiet`. Fail early if not found.
2. **Export** — `wsl --export <source> <backupPath>\<targetName>-base.tar`. Skipped if `--skip-export` is set; in that case, validate the tar file exists.
3. **Import** — `wsl --import <targetName> <installPath> <tarFile>`. Creates the install directory if it doesn't exist.
4. **Configure user** — `wsl -d <targetName> -- bash -c "echo -e '[user]\ndefault=<user>' | tee /etc/wsl.conf"`. Runs as root (fresh import defaults to root).
5. **Unregister original** — `wsl --unregister <source>`. Skipped if `--skip-unregister` is set.
6. **Terminate & verify** — `wsl --terminate <targetName>`, then `wsl --list --verbose` to confirm the new distro is registered.

## Coding Conventions (matching `_update-repos.ps1`)

- `Set-StrictMode -Version Latest`
- UTF-8 output encoding setup
- `$Script:` scoped defaults and config
- Custom `Get-ParsedArguments` for `--kebab-case` CLI args
- `Format-Text` / `Write-Message` helpers with ANSI colour codes and Unicode status symbols
- `Main` function as entry point, called at script end with parsed args
- Each wsl command checks `$LASTEXITCODE`; on failure, prints error via `Write-Message` and exits
- No external dependencies

## Error Handling

- Each `wsl` command checks `$LASTEXITCODE -ne 0`.
- On failure: print the error with a failure symbol and exit immediately.
- No automatic rollback — safer to leave the user in a known state than to auto-clean partial operations.
- Missing required parameters print usage help and exit with code 2.

## Documentation

A corresponding doc file will be created at `.docs/scripts/powershell/wsl/migrate-wsl-distro.md`.
