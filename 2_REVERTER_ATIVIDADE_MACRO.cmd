@echo off
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0REVERTER_ATIVIDADE_MACRO_v2.19.25.ps1"
pause
