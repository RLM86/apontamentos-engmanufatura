@echo off
set "DIR=%LOCALAPPDATA%\ApontaP3Backup"
if not exist "%DIR%\ultimo_status.json" (
  echo Ainda nao existe status de backup.
  pause
  exit /b 1
)
start "" notepad.exe "%DIR%\ultimo_status.json"
start "" explorer.exe "%DIR%"
