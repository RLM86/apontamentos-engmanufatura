@echo off
setlocal
chcp 65001 >nul
title APONTA P3 - v2.19.23 Importacao Area e Referencia
cls

echo ==============================================================
echo  APONTA P3 v2.19.23
echo  CORRECAO DEFINITIVA DA IMPORTACAO
echo ==============================================================
echo.
echo Esta atualizacao:
echo  - para de forcar todos os apontamentos em ADM;
echo  - le Area, Referencia e Observacao da planilha;
echo  - localiza setor, sala, modulo, parte e tipo de painel;
echo  - valida tudo antes de inserir;
echo  - atualiza registros equivalentes em Rascunho/Devolvido;
echo  - preserva Enviados/Aprovados;
echo  - faz backup, commit e push.
echo.
echo A janela permanece aberta em caso de erro.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0APLICAR_E_SUBIR_v2.19.23.ps1"
set "RC=%ERRORLEVEL%"

echo.
echo ==============================================================
if "%RC%"=="0" (
  echo PROCESSO CONCLUIDO.
  echo Procure acima:
  echo SUCESSO - v2.19.23 ENVIADA PARA O GITHUB
) else (
  echo OCORREU UM ERRO. Codigo: %RC%
  echo Tire uma foto desta tela e envie no chat.
)
echo ==============================================================
echo.
pause
endlocal
