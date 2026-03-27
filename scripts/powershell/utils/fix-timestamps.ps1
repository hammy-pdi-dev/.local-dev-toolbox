# fix-timestamps.ps1

Set-StrictMode -Version Latest 2>$null

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# -------------------------------------------------------------------------
# Configuration
$Script:Config = @{
    FolderPath  = 'C:\Backups\_Builds\_Forecourt_Service\Local\'
    Extensions  = @('.pdb', '.xml', '.config', '.dll', '.exe')
    Timestamp   = Get-Date '2026-03-30 07:46:50'
}
# -------------------------------------------------------------------------

function Set-FileTimestamps ([string]$folderPath, [string[]]$extensions, [datetime]$timestamp)
{
    Get-ChildItem -Path $folderPath -File |
    Where-Object { $extensions -contains $_.Extension.ToLower() } |
    ForEach-Object {
        $_.CreationTime   = $timestamp
        $_.LastWriteTime  = $timestamp
        $_.LastAccessTime = $timestamp
        Write-Host "Updated: $($_.Name)"
    }
}

function Main ([string]$folderPath, [string[]]$extensions, [datetime]$timestamp)
{
    if (-not (Test-Path -Path $folderPath -PathType Container))
    {
        Write-Error "FolderPath '$folderPath' does not exist or is not a directory."
        $global:LASTEXITCODE = 1
        return
    }

    Set-FileTimestamps -folderPath $folderPath -extensions $extensions -timestamp $timestamp
    Write-Host 'Done.'
}

Main -folderPath $Script:Config.FolderPath `
     -extensions $Script:Config.Extensions `
     -timestamp $Script:Config.Timestamp
