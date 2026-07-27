@echo off
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp04_TESTAR_BACKUP_AGORA.ps1"
pause
