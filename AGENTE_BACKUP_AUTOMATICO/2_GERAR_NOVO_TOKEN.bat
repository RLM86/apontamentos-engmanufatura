@echo off
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp02_GERAR_NOVO_TOKEN.ps1"
pause
