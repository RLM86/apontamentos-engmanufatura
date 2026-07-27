@echo off
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp03_CONFIGURAR_AGENTE.ps1"
pause
