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
