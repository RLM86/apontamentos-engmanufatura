@echo off
setlocal
chcp 65001 >nul
title Aponta Horas - Revisao Importacao v2.19.20 UTF8
cls

echo ==============================================================
echo  APONTA HORAS - REVISAO IMPORTACAO v2.19.20 - UTF8
echo ==============================================================
echo.
echo Correcao: leitura forcada em UTF-8 para evitar erro de codificacao.
echo Esta janela permanecera aberta.
echo.

set "APONT_PATCH_DIR=%~dp0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
 "$ErrorActionPreference='Stop'; $p=Join-Path $env:APONT_PATCH_DIR 'GERAR_REVISAO_IMPORTACAO_v2.19.20_UTF8.ps1'; try { $t=Get-Content -LiteralPath $p -Raw -Encoding UTF8; & ([ScriptBlock]::Create($t)); exit 0 } catch { Write-Host ''; Write-Host 'ERRO AO EXECUTAR:' -ForegroundColor Red; Write-Host $_.Exception.Message -ForegroundColor Red; Write-Host ''; Write-Host $_.InvocationInfo.PositionMessage -ForegroundColor Yellow; exit 1 }"

set "RC=%ERRORLEVEL%"
echo.
echo ==============================================================
if "%RC%"=="0" (
  echo PROCESSO FINALIZADO.
  echo Se apareceu REVISAO GERADA COM SUCESSO, use a pasta criada.
) else (
  echo OCORREU UM ERRO. Codigo: %RC%
  echo Tire uma foto desta tela e me envie.
)
echo ==============================================================
echo.
pause
endlocal
