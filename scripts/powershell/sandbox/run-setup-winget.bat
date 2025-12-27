@echo off
REM Helper script to run setup-winget.ps1 with proper execution policy
REM This bypasses the execution policy restriction

echo Starting setup-winget.ps1 with elevated permissions...
powershell.exe -ExecutionPolicy Bypass -NoExit -File "%~dp0setup-winget.ps1"

