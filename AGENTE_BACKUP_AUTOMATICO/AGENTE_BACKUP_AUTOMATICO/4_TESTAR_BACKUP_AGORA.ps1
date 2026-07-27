$ErrorActionPreference = "Stop"
$script = Join-Path $env:LOCALAPPDATA "ApontaP3Backup\Executar_Backup.ps1"

if (-not (Test-Path $script)) {
  throw "Agente nao configurado. Execute 3_CONFIGURAR_AGENTE.bat."
}

& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
  -NoProfile -ExecutionPolicy Bypass -File $script -Force

Write-Host ""
Write-Host "Se apareceu 'Backup concluido', confira o arquivo JSON na pasta Y:." -ForegroundColor Green
