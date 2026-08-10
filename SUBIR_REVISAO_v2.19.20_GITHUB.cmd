@echo off
setlocal EnableExtensions
chcp 65001 >nul
title APONTA HORAS - Subir revisao v2.19.20 para GitHub
cls

echo ==============================================================
echo  APONTA HORAS - SUBIR REVISAO v2.19.20 PARA O GITHUB
echo ==============================================================
echo.
echo Este script vai:
echo  1. localizar a pasta do projeto;
echo  2. copiar os 4 arquivos revisados para a raiz;
echo  3. executar git add;
echo  4. criar o commit;
echo  5. executar git push.
echo.

set "SCRIPT_DIR=%~dp0"
set "REPO_DIR="
set "REV_DIR="

REM Tenta a propria pasta do CMD como raiz do repositorio.
if exist "%SCRIPT_DIR%.git" (
    set "REPO_DIR=%SCRIPT_DIR%"
)

REM Tenta a pasta pai, caso o CMD esteja dentro de uma subpasta.
if not defined REPO_DIR (
    for %%I in ("%SCRIPT_DIR%..") do set "PARENT_DIR=%%~fI\"
    if exist "%PARENT_DIR%.git" (
        set "REPO_DIR=%PARENT_DIR%"
    )
)

REM Se ainda nao achou, pede o caminho da raiz do projeto.
if not defined REPO_DIR (
    echo Nao localizei automaticamente a pasta .git.
    echo.
    echo Cole o caminho da pasta raiz do projeto APONTA P3.
    echo Exemplo: C:\Users\SeuUsuario\...\APP APONT. P3
    echo.
    set /p "REPO_DIR=CAMINHO: "
    if not defined REPO_DIR goto :ERRO_REPO
    if not exist "%REPO_DIR%\.git" goto :ERRO_REPO
    if not "%REPO_DIR:~-1%"=="\" set "REPO_DIR=%REPO_DIR%\"
)

set "REV_DIR=%REPO_DIR%REVISAO_PRONTA_PARA_SUBIR_v2.19.20"

echo.
echo Projeto localizado:
echo %REPO_DIR%
echo.

if not exist "%REV_DIR%" (
    echo ERRO: pasta de revisao nao encontrada:
    echo %REV_DIR%
    echo.
    goto :ERRO
)

for %%F in (
    "index.html"
    "app-v2.19.20.js"
    "style-v2.19.20.css"
    "sw.js"
) do (
    if not exist "%REV_DIR%\%%~F" (
        echo ERRO: arquivo nao encontrado:
        echo %REV_DIR%\%%~F
        goto :ERRO
    )
)

echo Copiando arquivos revisados para a raiz...
copy /Y "%REV_DIR%\index.html" "%REPO_DIR%index.html" >nul
if errorlevel 1 goto :ERRO

copy /Y "%REV_DIR%\app-v2.19.20.js" "%REPO_DIR%app-v2.19.20.js" >nul
if errorlevel 1 goto :ERRO

copy /Y "%REV_DIR%\style-v2.19.20.css" "%REPO_DIR%style-v2.19.20.css" >nul
if errorlevel 1 goto :ERRO

copy /Y "%REV_DIR%\sw.js" "%REPO_DIR%sw.js" >nul
if errorlevel 1 goto :ERRO

echo OK - arquivos copiados.
echo.

where git >nul 2>nul
if errorlevel 1 (
    echo ERRO: Git nao foi encontrado no Windows.
    echo Instale/ative o Git e execute novamente.
    goto :ERRO
)

cd /d "%REPO_DIR%"

echo ==============================================================
echo STATUS ANTES DO COMMIT
echo ==============================================================
git status --short
echo.

echo Adicionando arquivos ao Git...
git add index.html app-v2.19.20.js style-v2.19.20.css sw.js
if errorlevel 1 goto :ERRO_GIT

echo.
echo Arquivos preparados:
git diff --cached --name-status
echo.

git diff --cached --quiet
if not errorlevel 1 (
    echo Nenhuma alteracao nova para commitar.
    echo Vou verificar se existe algo para enviar ao remoto...
    goto :PUSH
)

echo Criando commit...
git commit -m "v2.19.20 - prevalidacao da importacao"
if errorlevel 1 goto :ERRO_GIT

:PUSH
for /f "delims=" %%B in ('git branch --show-current') do set "BRANCH=%%B"
if not defined BRANCH set "BRANCH=main"

echo.
echo Enviando para GitHub...
echo Branch: %BRANCH%
git push origin %BRANCH%
if errorlevel 1 goto :ERRO_GIT

echo.
echo ==============================================================
echo  SUCESSO - REVISAO ENVIADA PARA O GITHUB
echo ==============================================================
echo.
echo Commit/branch atual:
git log -1 --oneline
echo.
echo Agora aguarde o deploy do Cloudflare/Pages e atualize o sistema.
echo.
pause
exit /b 0

:ERRO_REPO
echo.
echo ERRO: a pasta informada nao possui a pasta .git.
echo Execute este CMD dentro da raiz do repositorio ou informe a pasta correta.
goto :ERRO

:ERRO_GIT
echo.
echo ==============================================================
echo ERRO DURANTE O GIT
echo ==============================================================
echo.
echo Confira a mensagem exibida acima.
echo Se pedir login/autorizacao do GitHub, conclua e execute novamente.
goto :ERRO

:ERRO
echo.
echo ==============================================================
echo PROCESSO NAO CONCLUIDO
echo ==============================================================
echo.
echo A janela ficara aberta para voce fotografar/copiar o erro.
echo.
pause
exit /b 1
