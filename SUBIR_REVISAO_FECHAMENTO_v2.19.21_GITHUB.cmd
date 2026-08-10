@echo off
setlocal EnableExtensions
chcp 65001 >nul
title Aponta Horas - Subir fechamento v2.19.21
cls

echo ==============================================================
echo  APONTA HORAS - SUBIR v2.19.21 PARA O GITHUB
echo ==============================================================
echo.

set "SCRIPT_DIR=%~dp0"
set "REPO_DIR="

if exist "%SCRIPT_DIR%.git" set "REPO_DIR=%SCRIPT_DIR%"

if not defined REPO_DIR (
  for %%I in ("%SCRIPT_DIR%..") do set "PARENT_DIR=%%~fI\"
  if exist "%PARENT_DIR%.git" set "REPO_DIR=%PARENT_DIR%"
)

if not defined REPO_DIR (
  echo Cole o caminho da raiz do projeto:
  set /p "REPO_DIR=CAMINHO: "
  if not defined REPO_DIR goto :ERRO
  if not exist "%REPO_DIR%\.git" goto :ERRO
  if not "%REPO_DIR:~-1%"=="\" set "REPO_DIR=%REPO_DIR%\"
)

set "REV_DIR=%REPO_DIR%REVISAO_PRONTA_PARA_SUBIR_v2.19.21"

if not exist "%REV_DIR%" (
  echo.
  echo ERRO: pasta nao encontrada:
  echo %REV_DIR%
  echo Execute primeiro GERAR_REVISAO_FECHAMENTO_v2.19.21.cmd
  goto :ERRO
)

for %%F in (
 "index.html"
 "app-v2.19.21.js"
 "style-v2.19.21.css"
 "sw.js"
) do (
  if not exist "%REV_DIR%\%%~F" (
    echo ERRO: arquivo ausente: %%~F
    goto :ERRO
  )
)

echo Copiando arquivos...
copy /Y "%REV_DIR%\index.html" "%REPO_DIR%index.html" >nul
copy /Y "%REV_DIR%\app-v2.19.21.js" "%REPO_DIR%app-v2.19.21.js" >nul
copy /Y "%REV_DIR%\style-v2.19.21.css" "%REPO_DIR%style-v2.19.21.css" >nul
copy /Y "%REV_DIR%\sw.js" "%REPO_DIR%sw.js" >nul

where git >nul 2>nul
if errorlevel 1 (
  echo Git nao encontrado.
  goto :ERRO
)

cd /d "%REPO_DIR%"

echo.
echo STATUS:
git status --short
echo.

git add index.html app-v2.19.21.js style-v2.19.21.css sw.js
if errorlevel 1 goto :ERRO_GIT

git diff --cached --quiet
if not errorlevel 1 goto :PUSH

git commit -m "v2.19.21 - dias excedentes e ajuste no fechamento"
if errorlevel 1 goto :ERRO_GIT

:PUSH
for /f "delims=" %%B in ('git branch --show-current') do set "BRANCH=%%B"
if not defined BRANCH set "BRANCH=main"

git push origin %BRANCH%
if errorlevel 1 goto :ERRO_GIT

echo.
echo ==============================================================
echo  SUCESSO - v2.19.21 ENVIADA PARA O GITHUB
echo ==============================================================
git log -1 --oneline
echo.
pause
exit /b 0

:ERRO_GIT
echo.
echo ERRO DURANTE O GIT. Confira a mensagem acima.
goto :ERRO

:ERRO
echo.
echo ==============================================================
echo PROCESSO NAO CONCLUIDO
echo ==============================================================
echo.
pause
exit /b 1
