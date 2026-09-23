@echo off
chcp 65001 >nul
echo ==========================================
echo CORRECAO APONTA P3 - COLUNA DISCIPLINA
echo ==========================================

set "ARQ=app-v2.19.24.js"

if not exist "%ARQ%" (
    echo ERRO: %ARQ% nao encontrado.
    echo Execute este arquivo dentro da pasta APP APONT. P3.
    pause
    exit /b 1
)

echo Criando backup...
copy "%ARQ%" "app-v2.19.24_BACKUP_ANTES_DISCIPLINA.js" >nul

echo Aplicando ajuste...

powershell -Command "(Get-Content '%ARQ%' -Raw) -replace '<td>\$\{activityName\(x\.activity_id\)\}</td><td>\$\{fmt\(x\.hours\)\}</td>', '<td>${activityName(x.activity_id)}</td><td>${activityDiscipline(x.activity_id)}</td><td>${fmt(x.hours)}</td>' | Set-Content '%ARQ%' -Encoding UTF8"

echo.
echo ==========================================
echo CONCLUIDO
echo Backup criado:
echo app-v2.19.24_BACKUP_ANTES_DISCIPLINA.js
echo ==========================================
echo.
echo Agora teste a exportacao novamente.
pause
