# fix-timestamps.ps1

# Config
$folderPath = "C:\Backups\_Builds\_Forecourt_Service\Local\"
$extensions = @(".pdb", ".xml", ".config", ".dll", ".exe") 
$timestamp  = Get-Date "2026-03-30 07:46:50"

# Verify filtered files
# Get-ChildItem -Path $folderPath -File | Select-Object Name, Extension

# Apply timestamps
Get-ChildItem -Path $folderPath -File |
Where-Object { $extensions -contains $_.Extension.ToLower() } |
ForEach-Object {
    $_.CreationTime   = $timestamp
    $_.LastWriteTime  = $timestamp
    $_.LastAccessTime = $timestamp
    Write-Host "Updated: $($_.Name)"
}

Write-Host "Done."