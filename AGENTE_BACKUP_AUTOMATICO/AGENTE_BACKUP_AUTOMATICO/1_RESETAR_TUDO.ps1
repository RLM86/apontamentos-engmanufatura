$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "RESET DA CONFIGURACAO DO BACKUP - APONTA P3" -ForegroundColor Cyan
Write-Host ""

$taskNames = @(
  "Aponta P3 - Backup Diario",
  "Aponta P3 - Recuperar Backup Perdido"
)

foreach ($taskName in $taskNames) {
  try {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
    Write-Host "Tarefa removida: $taskName" -ForegroundColor Green
  } catch {
    Write-Host "Tarefa nao encontrada: $taskName" -ForegroundColor DarkGray
  }
}

$installDir = Join-Path $env:LOCALAPPDATA "ApontaP3Backup"
if (Test-Path $installDir) {
  $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
  $oldDir = Join-Path $env:LOCALAPPDATA "ApontaP3Backup_ANTIGO_$stamp"
  Move-Item -Path $installDir -Destination $oldDir -Force
  Write-Host "Configuracao antiga preservada em:" -ForegroundColor Yellow
  Write-Host $oldDir
} else {
  Write-Host "Nenhuma pasta antiga encontrada." -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "Reset concluido." -ForegroundColor Green
Write-Host "Agora execute: 2_GERAR_NOVO_TOKEN.bat" -ForegroundColor Cyan
