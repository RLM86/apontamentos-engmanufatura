$ErrorActionPreference = "Stop"

$SourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallDir = Join-Path $env:LOCALAPPDATA "ApontaP3Backup"
$DefaultUrl = "https://djmtyraadaoggsbogjwp.supabase.co"
$DefaultDestination = "Y:\PLANTA 3\GESTÃO (APONTAMENTOS, HORAS...)\Apontamento Horas\2026"
$DefaultTime = "18:00"

Write-Host "" 
Write-Host "CONFIGURADOR DO BACKUP AUTOMATICO - APONTA P3" -ForegroundColor Cyan
Write-Host "O backup sera tentado diariamente e recuperado no proximo login se o computador estiver desligado." -ForegroundColor Gray
Write-Host ""

$url = Read-Host "URL do projeto Supabase [$DefaultUrl]"
if ([string]::IsNullOrWhiteSpace($url)) { $url = $DefaultUrl }
$url = $url.Trim().TrimEnd('/')
if (-not $url.StartsWith("https://") -or -not $url.Contains(".supabase.co")) {
  throw "URL do Supabase invalida."
}

Write-Host "Cole o BACKUP_TOKEN criado em Supabase > Edge Functions > Secrets." -ForegroundColor Yellow
$secureToken = Read-Host "BACKUP_TOKEN (minimo 32 caracteres)" -AsSecureString
$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
try {
  $token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
} finally {
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
}
if ($token.Length -lt 32) { throw "O BACKUP_TOKEN precisa ter pelo menos 32 caracteres." }

$destination = Read-Host "Pasta de destino [$DefaultDestination]"
if ([string]::IsNullOrWhiteSpace($destination)) { $destination = $DefaultDestination }

$time = Read-Host "Horario diario no formato HH:mm [$DefaultTime]"
if ([string]::IsNullOrWhiteSpace($time)) { $time = $DefaultTime }
try { $timeSpan = [TimeSpan]::ParseExact($time, "hh\:mm", $null) } catch { throw "Horario invalido. Use, por exemplo, 18:00." }

$anonKey = Read-Host "Chave publica/anon do Supabase (opcional; pressione Enter para deixar vazio)"

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Copy-Item -Path (Join-Path $SourceDir "Executar_Backup.ps1") -Destination (Join-Path $InstallDir "Executar_Backup.ps1") -Force

$config = [ordered]@{
  SupabaseUrl = $url
  BackupToken = $token
  DestinationPath = $destination
  ScheduledTime = $time
  AnonKey = $anonKey.Trim()
  InstalledAt = (Get-Date).ToString("o")
}
$config | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $InstallDir "config.json") -Encoding UTF8

$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$powershellExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$scriptPath = Join-Path $InstallDir "Executar_Backup.ps1"

$dailyAction = New-ScheduledTaskAction -Execute $powershellExe -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""
$catchUpAction = New-ScheduledTaskAction -Execute $powershellExe -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`" -CatchUp"
$dailyTrigger = New-ScheduledTaskTrigger -Daily -At ([datetime]::Today.Add($timeSpan))
$logonTrigger = New-ScheduledTaskTrigger -AtLogOn -User $currentUser
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 15)
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited

$dailyTask = New-ScheduledTask -Action $dailyAction -Trigger $dailyTrigger -Settings $settings -Principal $principal -Description "Backup diario do Aponta P3."
$catchUpTask = New-ScheduledTask -Action $catchUpAction -Trigger $logonTrigger -Settings $settings -Principal $principal -Description "Recupera backup perdido quando o computador estava desligado ou sem rede."

Register-ScheduledTask -TaskName "Aponta P3 - Backup Diario" -InputObject $dailyTask -Force | Out-Null
Register-ScheduledTask -TaskName "Aponta P3 - Recuperar Backup Perdido" -InputObject $catchUpTask -Force | Out-Null

Write-Host ""
Write-Host "Tarefas criadas com sucesso:" -ForegroundColor Green
Write-Host "- Aponta P3 - Backup Diario, todos os dias as $time"
Write-Host "- Aponta P3 - Recuperar Backup Perdido, no proximo login"
Write-Host "Pasta do agente: $InstallDir"
Write-Host ""

$test = Read-Host "Deseja testar e gerar um backup agora? [S/n]"
if ([string]::IsNullOrWhiteSpace($test) -or $test.Trim().ToUpper() -eq "S") {
  & $powershellExe -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Force
  Write-Host "Confira o resultado acima e o arquivo ultimo_status.json em $InstallDir" -ForegroundColor Cyan
}
