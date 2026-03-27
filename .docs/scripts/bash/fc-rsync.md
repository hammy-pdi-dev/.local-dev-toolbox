# fc-rsync.sh

A one-shot rsync script for backing up a local Git repository to another drive, respecting `.gitignore` rules.

## Overview

`fc-rsync.sh` mirrors a source repository to a backup destination using `rsync`. It honours the repository's `.gitignore` so that build artefacts, logs, and dependency folders are excluded automatically. The `--delete` flag keeps the backup in sync by removing files from the destination that no longer exist in the source.

## Usage

```bash
chmod +x scripts/bash/fc-rsync.sh
./scripts/bash/fc-rsync.sh
```

The script has no parameters -- source and destination paths are defined as variables at the top of the file.

## Configuration

Edit these variables before running:

| Variable | Default | Description |
|----------|---------|-------------|
| `SOURCE` | `/mnt/d/Repos/Hydra.OPT.Service` | Path to the repository to back up |
| `DEST` | `/mnt/c/Backups/Repos/Hydra.OPT.Service` | Backup destination path |

## What It Does

1. Runs `rsync -av --delete --progress` from source to destination.
2. Uses `--filter=':- .gitignore'` to read and apply `.gitignore` rules from the source repo.
3. Explicitly excludes `node_modules/`, `*.log`, `*.tmp`, and `*.cache` as an extra safety net.
4. Prints progress during the transfer and a confirmation message on completion.

## Notes

- The `--delete` flag means files removed from source will also be removed from the backup. This keeps the backup a true mirror but means it is **not** a versioned backup -- if you delete something from source, it's gone from the backup too after the next run.
- For timestamped snapshots (keeping multiple backup versions), uncomment the alternative `DEST` line that appends a date suffix.
