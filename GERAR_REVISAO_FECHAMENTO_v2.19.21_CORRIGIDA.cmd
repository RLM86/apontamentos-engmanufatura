@echo off
setlocal
chcp 65001 >nul
title Aponta Horas - Gerar revisao fechamento v2.19.21 CORRIGIDA
cls
echo ==============================================================
echo  APONTA HORAS - FECHAMENTO v2.19.21 - CORRIGIDA
echo ==============================================================
echo.
echo Esta versao corrige a falha de CRLF/LF do pacote anterior.
echo A janela permanecera aberta em caso de erro.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0GERAR_REVISAO_FECHAMENTO_v2.19.21_CORRIGIDA.ps1"
set "RC=%ERRORLEVEL%"
echo.
echo ==============================================================
if "%RC%"=="0" (
  echo REVISAO GERADA COM SUCESSO.
  echo Agora execute SUBIR_REVISAO_FECHAMENTO_v2.19.21_GITHUB.cmd
) else (
  echo OCORREU UM ERRO. Codigo: %RC%
  echo Tire uma foto da mensagem acima e envie no chat.
)
echo ==============================================================
echo.
pause
endlocal
