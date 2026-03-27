# fix-timestamps.ps1

A utility script that sets the creation, modification, and access timestamps of files in a folder to a specific date and time.

## Overview

`fix-timestamps.ps1` bulk-updates file timestamps in a target directory. It filters files by extension so that only the file types you care about are touched. This is useful when build outputs or deployment artefacts need consistent timestamps — for example, when comparing builds or preparing a release folder where the file dates should reflect the build time rather than when they were copied.

## Configuration

Edit the variables at the top of the script before running:

| Variable | Default | Description |
|----------|---------|-------------|
| `$folderPath` | `C:\Backups\_Builds\_Forecourt_Service\Local\` | Directory containing the files to update |
| `$extensions` | `.pdb`, `.xml`, `.config`, `.dll`, `.exe` | Only files with these extensions are modified |
| `$timestamp` | `2026-03-30 07:46:50` | The date and time to apply to all matching files |

## Usage

```powershell
# Edit the script to set your folder, extensions, and timestamp, then run:
.\fix-timestamps.ps1
```

## What It Does

1. Scans `$folderPath` for files (non-recursive, immediate children only).
2. Filters to files whose extension matches one of the entries in `$extensions`.
3. Sets three timestamp properties on each matching file:
   - `CreationTime` — when the file was created
   - `LastWriteTime` — when the file was last modified
   - `LastAccessTime` — when the file was last accessed
4. Prints the name of each updated file.

## Notes

- The script does **not** recurse into subdirectories. To process nested folders, change `Get-ChildItem -Path $folderPath -File` to include `-Recurse`.
- A commented-out line at the top (`Get-ChildItem ... | Select-Object Name, Extension`) can be uncommented to preview which files will be affected before running the update.
- Requires write access to the target files. Run as administrator if the folder is in a protected location.
