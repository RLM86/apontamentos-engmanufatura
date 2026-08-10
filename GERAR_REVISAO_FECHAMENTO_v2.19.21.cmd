@echo off
setlocal
chcp 65001 >nul
title Aponta Horas - Gerar revisao fechamento v2.19.21
cls
echo ==============================================================
echo  APONTA HORAS - GERAR REVISAO FECHAMENTO v2.19.21
echo ==============================================================
echo.
echo A janela permanecera aberta.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0GERAR_REVISAO_FECHAMENTO_v2.19.21.ps1"
set "RC=%ERRORLEVEL%"
echo.
echo ==============================================================
if "%RC%"=="0" (
  echo PROCESSO FINALIZADO.
  echo Confira se apareceu REVISAO GERADA COM SUCESSO.
) else (
  echo OCORREU UM ERRO. Codigo: %RC%
  echo Tire uma foto desta tela e envie no chat.
)
echo ==============================================================
echo.
pause
endlocal
