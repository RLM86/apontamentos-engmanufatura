@echo off
chcp 65001 >nul
schtasks /Delete /TN "Aponta P3 - Backup Diario" /F >nul 2>&1
schtasks /Delete /TN "Aponta P3 - Recuperar Backup Perdido" /F >nul 2>&1
echo As tarefas agendadas foram removidas.
echo Os arquivos e logs continuam em: %LOCALAPPDATA%\ApontaP3Backup
echo Exclua essa pasta manualmente apenas se nao precisar dos backups pendentes.
pause
