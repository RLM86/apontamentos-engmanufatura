@echo off
echo ==========================================
echo Atualizador APONTA P3 - Disciplina na Exportacao
echo ==========================================

set "ROOT=%~dp0"

echo.
echo Pasta do projeto:
echo %ROOT%

echo.
echo Procurando arquivos de exportacao...

findstr /s /i /m "xlsx export excel csv" "%ROOT%\*.js" "%ROOT%\*.ts" "%ROOT%\*.tsx" > arquivos_exportacao.txt

if not exist arquivos_exportacao.txt (
    echo Nenhum arquivo de exportacao encontrado.
    echo Coloque este arquivo na raiz do projeto APONTA P3.
    pause
    exit /b 1
)

echo Arquivos encontrados:
type arquivos_exportacao.txt

echo.
echo ATENCAO:
echo Este atualizador identifica os arquivos, mas nao altera automaticamente
echo o codigo sem validar a estrutura da relacao Atividade x Disciplina.
echo.
echo Proximo passo:
echo Envie o arquivo listado acima para aplicar a correcao definitiva.
pause
