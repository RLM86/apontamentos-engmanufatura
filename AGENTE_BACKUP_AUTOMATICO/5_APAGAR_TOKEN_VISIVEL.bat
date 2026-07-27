@echo off
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp05_APAGAR_TOKEN_VISIVEL.ps1"
pause
