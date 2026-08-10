@echo off
setlocal
chcp 65001 >nul
title Aponta Horas - Atualizar e subir v2.19.22
cls

echo ==============================================================
echo  APONTA HORAS - v2.19.22
echo  COLABORADOR CONFERE E AJUSTA ANTES DO FECHAMENTO
echo ==============================================================
echo.
echo Este CMD faz tudo:
echo  - valida a v2.19.21 atual;
echo  - cria backup;
echo  - gera a v2.19.22;
echo  - valida;
echo  - git add / commit / push.
echo.
echo A janela nao fecha se houver erro.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ATUALIZAR_E_SUBIR_v2.19.22.ps1"
set "RC=%ERRORLEVEL%"

echo.
echo ==============================================================
if "%RC%"=="0" (
  echo PROCESSO CONCLUIDO.
  echo Confira acima: SUCESSO - v2.19.22 ENVIADA PARA O GITHUB
) else (
  echo OCORREU UM ERRO. Codigo: %RC%
  echo Tire uma foto desta tela e envie no chat.
)
echo ==============================================================
echo.
pause
endlocal
