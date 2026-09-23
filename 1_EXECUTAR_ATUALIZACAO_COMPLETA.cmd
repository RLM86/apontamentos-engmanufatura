@echo off
setlocal
cd /d "%~dp0"
echo ==========================================================
echo APONT MAN P3 - ATUALIZACAO COMPLETA ATIVIDADE MACRO v2.19.25
echo ==========================================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ATUALIZAR_ATIVIDADE_MACRO_v2.19.25.ps1"
if errorlevel 1 (
  echo.
  echo A ATUALIZACAO NAO FOI CONCLUIDA.
  echo Consulte o arquivo de log criado nesta pasta.
  pause
  exit /b 1
)
echo.
echo ATUALIZACAO CONCLUIDA.
pause
