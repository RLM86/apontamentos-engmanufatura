@echo off
title APONTA P3 - INCLUIR DISCIPLINA NA EXPORTACAO

set REPO=C:\Users\Rmacedo\OneDrive - MODULAR\Aplicativos\Anexos\Área de Trabalho\APP APONT. P3

echo ==========================================
echo APONTA P3 - EXPORTACAO COM DISCIPLINA
echo ==========================================

cd /d "%REPO%"

if not exist ".git" (
 echo ERRO: Repositorio nao encontrado.
 pause
 exit /b 1
)

echo.
echo Criando backup...
set BACKUP=BACKUP_DISCIPLINA_%date:~-4%%date:~3,2%%date:~0,2%_%time:~0,2%%time:~3,2%
mkdir "%BACKUP%"

copy app-*.js "%BACKUP%" >nul
copy style-*.css "%BACKUP%" >nul
copy index.html "%BACKUP%" >nul
copy sw.js "%BACKUP%" >nul

echo Backup criado.

echo.
echo ATENCAO:
echo Este instalador prepara a publicacao.
echo A inclusao da coluna DISCIPLINA deve estar aplicada
echo no arquivo app-v*.js antes do commit.
echo.

echo Verificando alteracoes...
git status

echo.
echo Adicionando arquivos...
git add .

echo.
echo Commit...
git commit -m "Inclui disciplina na exportacao de apontamentos"

echo.
echo Enviando GitHub...
git push origin main

if errorlevel 1 (
 echo ERRO NO GITHUB
 pause
 exit /b 1
)

echo.
echo Publicando Cloudflare...
where wrangler >nul 2>nul

if errorlevel 1 (
 echo Wrangler nao encontrado.
 echo Instale: npm install -g wrangler
 pause
 exit /b 1
)

wrangler deploy

if errorlevel 1 (
 echo ERRO NO CLOUDFLARE
 pause
 exit /b 1
)

echo.
echo PUBLICACAO FINALIZADA
pause
