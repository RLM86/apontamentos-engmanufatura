$ErrorActionPreference = "Stop"

$bytes = New-Object byte[] 48
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$rng.GetBytes($bytes)
$rng.Dispose()

$token = [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+','-').Replace('/','_')
$tokenFile = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "NOVO_BACKUP_TOKEN.txt"

$token | Set-Content -Path $tokenFile -Encoding ASCII
Set-Clipboard -Value $token

Write-Host ""
Write-Host "NOVO BACKUP_TOKEN GERADO." -ForegroundColor Green
Write-Host ""
Write-Host "O token foi:" -ForegroundColor Cyan
Write-Host "- copiado para a area de transferencia;" -ForegroundColor White
Write-Host "- salvo temporariamente em NOVO_BACKUP_TOKEN.txt." -ForegroundColor White
Write-Host ""
Write-Host "Agora, no Supabase:" -ForegroundColor Yellow
Write-Host "1. Edge Functions > Secrets."
Write-Host "2. Edite BACKUP_TOKEN."
Write-Host "3. No campo Valor, pressione Ctrl+V."
Write-Host "4. Salve."
Write-Host ""
Write-Host "NAO use o DIGEST SHA256." -ForegroundColor Red
Write-Host "Depois de salvar no Supabase, execute 3_CONFIGURAR_AGENTE.bat." -ForegroundColor Cyan
