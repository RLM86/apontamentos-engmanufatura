@echo off
title APONTA P3 - PUBLICAR GITHUB E CLOUDFLARE

set REPO=C:\Users\Rmacedo\OneDrive - MODULAR\Aplicativos\Anexos\Área de Trabalho\APP APONT. P3

echo ==========================================
echo APONTA P3 - PUBLICACAO AUTOMATICA
echo ==========================================

cd /d "%REPO%"

if errorlevel 1 (
 echo ERRO: Repositorio nao encontrado.
 pause
 exit /b 1
)

echo.
echo Criando backup...
set BACKUP=BACKUP_PUBLICACAO_%date:~-4%%date:~3,2%%date:~0,2%_%time:~0,2%%time:~3,2%
mkdir "%BACKUP%" >nul 2>&1

copy index.html "%BACKUP%" >nul
copy app-*.js "%BACKUP%" >nul
copy style-*.css "%BACKUP%" >nul
copy sw.js "%BACKUP%" >nul

echo Backup criado.

echo.
echo Atualizando Git...
git add .

git commit -m "Atualiza exportacao apontamentos com disciplina"

echo.
echo Enviando GitHub...
git push origin main

if errorlevel 1 (
 echo ERRO NO PUSH DO GITHUB
 pause
 exit /b 1
)

echo.
echo GitHub atualizado.

echo.
echo Publicando Cloudflare...
wrangler deploy

if errorlevel 1 (
 echo ERRO NO DEPLOY CLOUDFLARE
 pause
 exit /b 1
)

echo.
echo ==========================================
echo PUBLICADO COM SUCESSO
echo ==========================================

pause
