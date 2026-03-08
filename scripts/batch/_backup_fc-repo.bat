@echo off
rem SET LOGFILE=C:\Backups\_backup_fc-repo_%DATE:~-4,4%%DATE:~-7,2%%DATE:~-10,2%_%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%.log
rem _backup_fc-repo.bat
rem _backup-repo.bat .local-dev-toolbox
rem _backup-repo.bat Hydra.OPT.Service

:: ℹ️ Config 📄
set REPONAME=%~1
if "%~1"=="" (
    set REPONAME=Hydra.OPT.Service
) ELSE (
    set REPONAME=%~1
)

set SOURCE=D:\Repos\%REPONAME%
set DEST=C:\Backups\Repos\%REPONAME%
set EXCLUDEFILE=C:\Backups\.exclude.txt

:: 🗑️ Wipe destination
echo Clearing destination...
rd /s /q "%DEST%" 2>nul
mkdir "%DEST%"

:: 📁/📦 Copy files  
echo Copying files...
xcopy "%SOURCE%" "%DEST%" /e /h /c /i /y /EXCLUDE:%EXCLUDEFILE%

:: ✅ Done
echo.
if %ERRORLEVEL% NEQ 0 (
	echo Backup failed. Check your source, destination and exclude file paths. → LOGFILE
) else (
	echo Backup complete!
)

pause
