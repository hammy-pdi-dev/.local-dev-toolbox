@ECHO OFF
:: starting setup-wsb.ps1 bypasses the execution policy restriction

ECHO Starting setup-wsb.ps1 with elevated permissions...
powershell.exe -ExecutionPolicy Bypass -NoExit -File "%~dp0setup-wsb.ps1"
