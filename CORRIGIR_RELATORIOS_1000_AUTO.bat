@echo off
chcp 65001 >nul
title APONTA P3 - Corrigir Relatorios acima de 1000

set "SCRIPT=%~dp0FIX_RELATORIOS_1000.ps1"

if not exist "%SCRIPT%" (
  echo.
  echo ERRO: Nao encontrei FIX_RELATORIOS_1000.ps1 ao lado deste BAT.
  echo Extraia os dois arquivos na mesma pasta e tente novamente.
  echo.
  pause
  exit /b 1
)

echo.
echo Iniciando correcao automatica...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*

exit /b %ERRORLEVEL%
