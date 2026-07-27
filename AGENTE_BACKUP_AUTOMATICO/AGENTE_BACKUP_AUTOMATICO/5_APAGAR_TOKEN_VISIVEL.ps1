$tokenFile = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "NOVO_BACKUP_TOKEN.txt"

if (Test-Path $tokenFile) {
  Remove-Item $tokenFile -Force
}

Set-Clipboard -Value ""
Write-Host "Arquivo temporario do token e area de transferencia foram limpos." -ForegroundColor Green
Write-Host "O agente continuara funcionando com a configuracao interna." -ForegroundColor Gray
