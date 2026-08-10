@echo off
setlocal
chcp 65001 >nul
title APONTA HORAS - EXECUTE ESTE - v2.19.22 FINAL
cls

echo ==============================================================
echo  APONTA HORAS v2.19.22 FINAL
echo  ESTE E O PACOTE CORRETO
echo ==============================================================
echo.
echo IMPORTANTE:
echo Nao execute nenhum ATUALIZAR_E_SUBIR_v2.19.22.cmd antigo.
echo Este CMD chama exclusivamente APLICAR_v2.19.22_FINAL.ps1.
echo.
echo A janela ficara aberta se houver erro.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0APLICAR_v2.19.22_FINAL.ps1"
set "RC=%ERRORLEVEL%"

echo.
echo ==============================================================
if "%RC%"=="0" (
  echo PROCESSO CONCLUIDO.
  echo Procure acima:
  echo SUCESSO - v2.19.22 ENVIADA PARA O GITHUB
) else (
  echo OCORREU UM ERRO. Codigo: %RC%
  echo Tire uma foto DESTA tela e envie no chat.
)
echo ==============================================================
echo.
pause
endlocal
