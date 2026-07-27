@echo off
chcp 65001 >nul
set "AGENT=%LOCALAPPDATA%\ApontaP3Backup\Executar_Backup.ps1"
if not exist "%AGENT%" (
  echo O agente nao esta instalado. Execute Configurar_Backup_Diario.bat primeiro.
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%AGENT%" -Force
echo.
pause
