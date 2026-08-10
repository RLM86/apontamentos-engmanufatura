@echo off
setlocal
chcp 65001 >nul
title APONTA P3 - v2.19.23 FIX2
cls

echo ======================================================================
echo  APONTA P3 v2.19.23 FIX2
echo  IMPORTACAO POR AREA E REFERENCIA REAL
echo ======================================================================
echo.
echo Esta versao corrige o erro do instalador anterior.
echo.
echo O FIX2:
echo  - nao usa a busca Regex que falhou;
echo  - le Area, Referencia e Observacao;
echo  - para de forcar ADM;
echo  - resolve setor, sala, modulo, parte e tipo de painel;
echo  - substitui Rascunho/Devolvido equivalentes;
echo  - preserva Enviado/Aprovado;
echo  - cria backup;
echo  - valida JavaScript antes do Git;
echo  - faz commit e push somente depois das validacoes.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0APLICAR_E_SUBIR_v2.19.23_FIX2.ps1"
set "RC=%ERRORLEVEL%"

echo.
echo ======================================================================
if "%RC%"=="0" (
  echo PROCESSO CONCLUIDO.
  echo Procure acima:
  echo SUCESSO - v2.19.23 FIX2 ENVIADA PARA O GITHUB
) else (
  echo OCORREU UM ERRO. Codigo: %RC%
  echo Tire uma foto desta tela e envie no chat.
)
echo ======================================================================
echo.
pause
endlocal
