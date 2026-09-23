@echo off
setlocal
cd /d "%~dp0"
PowerShell -NoProfile -ExecutionPolicy Bypass -File "%~dp01_EXECUTAR_ATUALIZACAO_ATIVIDADE_MACRO_v2.19.25.ps1"
if errorlevel 1 (
 echo.
 echo ERRO NA ATUALIZACAO. Nenhuma etapa adicional deve ser executada.
 pause
 exit /b 1
)
