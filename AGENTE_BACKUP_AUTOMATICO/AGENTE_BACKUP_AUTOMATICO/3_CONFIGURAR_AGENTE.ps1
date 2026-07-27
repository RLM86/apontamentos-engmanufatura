$ErrorActionPreference = "Stop"

$SourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallDir = Join-Path $env:LOCALAPPDATA "ApontaP3Backup"
$TokenFile = Join-Path $SourceDir "NOVO_BACKUP_TOKEN.txt"

$SupabaseUrl = "https://djmtyraadaogqsbogjwp.supabase.co"
$Destination = "Y:\PLANTA 3\GESTÃO (APONTAMENTOS, HORAS...)\Apontamento Horas\2026"
$Time = "18:00"

Write-Host ""
Write-Host "CONFIGURACAO LIMPA DO BACKUP - APONTA P3" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $TokenFile)) {
  throw "NOVO_BACKUP_TOKEN.txt nao encontrado. Execute primeiro 2_GERAR_NOVO_TOKEN.bat."
}

$Token = (Get-Content $TokenFile -Raw -Encoding ASCII).Trim()
if ($Token.Length -lt 32) {
  throw "O token gerado e invalido."
}

Write-Host "URL:" -ForegroundColor Gray
Write-Host $SupabaseUrl -ForegroundColor White
Write-Host "Destino:" -ForegroundColor Gray
Write-Host $Destination -ForegroundColor White
Write-Host "Horario:" -ForegroundColor Gray
Write-Host $Time -ForegroundColor White
Write-Host ""

$confirm = Read-Host "Voce ja colou e salvou este NOVO token no BACKUP_TOKEN do Supabase? [S/n]"
if (-not [string]::IsNullOrWhiteSpace($confirm) -and $confirm.Trim().ToUpper() -ne "S") {
  throw "Configuracao cancelada. Salve primeiro o token no Supabase."
}

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Copy-Item -Path (Join-Path $SourceDir "Executar_Backup.ps1") `
          -Destination (Join-Path $InstallDir "Executar_Backup.ps1") -Force

$config = [ordered]@{
  SupabaseUrl = $SupabaseUrl
  BackupToken = $Token
  DestinationPath = $Destination
  ScheduledTime = $Time
  AnonKey = ""
  InstalledAt = (Get-Date).ToString("o")
}
$config | ConvertTo-Json -Depth 5 |
  Set-Content -Path (Join-Path $InstallDir "config.json") -Encoding UTF8

$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$powershellExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$scriptPath = Join-Path $InstallDir "Executar_Backup.ps1"
$timeSpan = [TimeSpan]::ParseExact($Time, "hh\:mm", $null)

$dailyAction = New-ScheduledTaskAction -Execute $powershellExe `
  -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""
$catchUpAction = New-ScheduledTaskAction -Execute $powershellExe `
  -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`" -CatchUp"

$dailyTrigger = New-ScheduledTaskTrigger -Daily -At ([datetime]::Today.Add($timeSpan))
$logonTrigger = New-ScheduledTaskTrigger -AtLogOn -User $currentUser

$settings = New-ScheduledTaskSettingsSet `
  -StartWhenAvailable `
  -AllowStartIfOnBatteries `
  -DontStopIfGoingOnBatteries `
  -MultipleInstances IgnoreNew `
  -ExecutionTimeLimit (New-TimeSpan -Minutes 15)

$principal = New-ScheduledTaskPrincipal `
  -UserId $currentUser `
  -LogonType Interactive `
  -RunLevel Limited

$dailyTask = New-ScheduledTask `
  -Action $dailyAction `
  -Trigger $dailyTrigger `
  -Settings $settings `
  -Principal $principal `
  -Description "Backup diario do Aponta P3."

$catchUpTask = New-ScheduledTask `
  -Action $catchUpAction `
  -Trigger $logonTrigger `
  -Settings $settings `
  -Principal $principal `
  -Description "Recupera backup perdido quando o computador estava desligado ou sem rede."

Register-ScheduledTask -TaskName "Aponta P3 - Backup Diario" `
  -InputObject $dailyTask -Force | Out-Null

Register-ScheduledTask -TaskName "Aponta P3 - Recuperar Backup Perdido" `
  -InputObject $catchUpTask -Force | Out-Null

Write-Host ""
Write-Host "Configuracao concluida." -ForegroundColor Green
Write-Host "As duas tarefas foram criadas." -ForegroundColor Green
Write-Host ""
Write-Host "Agora execute: 4_TESTAR_BACKUP_AGORA.bat" -ForegroundColor Cyan
