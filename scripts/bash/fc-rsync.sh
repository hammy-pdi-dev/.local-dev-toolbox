#!/bin/bash

SOURCE="/mnt/d/Repos/Hydra.OPT.Service"
DEST="/mnt/c/Backups/Repos/Hydra.OPT.Service"
# DEST="/mnt/c/backups/repos/Hydra.OPT.Service_$(date +%Y%m%d_%H%M%S)"

echo "📦 Copying files..."
rsync -av --delete --progress \
  --filter=':- .gitignore' \
  --exclude='node_modules/' \
  --exclude='*.log' \
  --exclude='*.tmp' \
  --exclude='*.cache' \
  "$SOURCE/" "$DEST/"

echo "✅ Sync complete → $DEST"

# Save as fc-rsync.sh, then:
# chmod +x fc-rsync.sh
# ./fc-rsync.sh.sh



# xcopy "D:\Repos\Hydra.OPT.Service" "C:\Backups\Repos\Hydra.OPT.Service" /E /H /C /I /Y /EXCLUDE:C:\Backups\.exclude.txt