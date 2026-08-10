@echo off
chcp 65001 >nul
title Aponta Horas - Revisao Importacao v2.19.20 CORRIGIDA
cls
echo ==============================================================
echo  APONTA HORAS - GERAR REVISAO DE IMPORTACAO v2.19.20
echo ==============================================================
echo.
echo Esta janela NAO vai fechar sozinha.
echo Se o projeto nao for localizado, o script vai pedir a pasta.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0GERAR_REVISAO_IMPORTACAO_v2.19.20_CORRIGIDA.ps1"
set "RC=%ERRORLEVEL%"
echo.
echo ==============================================================
if "%RC%"=="0" (
  echo PROCESSO FINALIZADO. Confira a mensagem acima.
) else (
  echo OCORREU UM ERRO. Codigo de saida: %RC%
  echo A mensagem acima indica exatamente o que precisa ser corrigido.
)
echo ==============================================================
echo.
pause
