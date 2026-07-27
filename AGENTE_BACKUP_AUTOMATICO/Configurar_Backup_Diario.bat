@echo off
chcp 65001 >nul
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Configurar_Backup_Diario.ps1"
if errorlevel 1 (
  echo.
  echo A configuracao falhou.
  echo Clique com o botao direito neste arquivo e escolha Executar como administrador.
)
echo.
pause
