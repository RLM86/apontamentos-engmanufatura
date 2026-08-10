@echo off
setlocal
chcp 65001 >nul
title Aponta Horas - Conferencia antes do fechamento v2.19.21
cls
echo ==============================================================
echo  APONTA HORAS - REVISAO FECHAMENTO v2.19.21
echo ==============================================================
echo.
echo Esta revisao adiciona a conferencia diaria ANTES do envio.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0GERAR_REVISAO_FECHAMENTO_COLABORADOR_v2.19.21.ps1"
set "RC=%ERRORLEVEL%"
echo.
echo ==============================================================
if "%RC%"=="0" (
  echo REVISAO GERADA COM SUCESSO.
  echo Agora execute o CMD de envio ao GitHub.
) else (
  echo OCORREU UM ERRO. Codigo: %RC%
  echo Tire uma foto desta tela e envie no chat.
)
echo ==============================================================
echo.
pause
endlocal
