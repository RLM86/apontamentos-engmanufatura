param(
  [switch]$Force,
  [switch]$CatchUp
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$InstallDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $InstallDir "config.json"
$LogDir = Join-Path $InstallDir "Logs"
$StatusPath = Join-Path $InstallDir "ultimo_status.json"
$PendingDir = Join-Path $InstallDir "Pendentes"

New-Item -ItemType Directory -Force -Path $LogDir, $PendingDir | Out-Null
$LogPath = Join-Path $LogDir ("backup_{0}.log" -f (Get-Date -Format "yyyy-MM"))

function Write-Log {
  param([string]$Message, [string]$Level = "INFO")
  $line = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
  Add-Content -Path $LogPath -Value $line -Encoding UTF8
}

function Save-Status {
  param(
    [bool]$Success,
    [string]$Message,
    [string]$FilePath = "",
    [bool]$StoredInFallback = $false
  )

  $status = [ordered]@{
    success = $Success
    checkedAt = (Get-Date).ToString("o")
    message = $Message
    filePath = $FilePath
    storedInFallback = $StoredInFallback
  }

  if ($Success) {
    $status.lastSuccessAt = (Get-Date).ToString("o")
  }
  elseif (Test-Path $StatusPath) {
    try {
      $oldStatus = Get-Content $StatusPath -Raw -Encoding UTF8 | ConvertFrom-Json
      if ($oldStatus.lastSuccessAt) {
        $status.lastSuccessAt = [string]$oldStatus.lastSuccessAt
      }
    } catch {}
  }

  $status | ConvertTo-Json -Depth 10 | Set-Content -Path $StatusPath -Encoding UTF8
}

function Get-LastSuccessDate {
  if (-not (Test-Path $StatusPath)) { return $null }
  try {
    $status = Get-Content $StatusPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($status.lastSuccessAt) {
      return [datetime]::Parse([string]$status.lastSuccessAt)
    }
  } catch {}
  return $null
}

function Test-DestinationWritable {
  param([string]$Path)
  try {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    $probe = Join-Path $Path (".aponta_p3_teste_{0}.tmp" -f ([guid]::NewGuid().ToString("N")))
    Set-Content -Path $probe -Value "teste" -Encoding ASCII
    Remove-Item -Path $probe -Force
    return $true
  } catch {
    Write-Log "Destino indisponivel: $Path. $($_.Exception.Message)" "WARN"
    return $false
  }
}

function Copy-PendingBackups {
  param([string]$DestinationPath)
  if (-not (Test-Path $PendingDir)) { return }
  $pending = @(Get-ChildItem -Path $PendingDir -Filter "Aponta_P3_Backup_*.json" -File -ErrorAction SilentlyContinue)
  if ($pending.Count -eq 0) { return }
  if (-not (Test-DestinationWritable $DestinationPath)) { return }

  foreach ($item in $pending) {
    try {
      $target = Join-Path $DestinationPath $item.Name
      Copy-Item -Path $item.FullName -Destination $target -Force
      Remove-Item -Path $item.FullName -Force
      Write-Log "Backup pendente copiado para o destino principal: $target"
    } catch {
      Write-Log "Falha ao copiar pendente $($item.FullName): $($_.Exception.Message)" "WARN"
    }
  }
}

if (-not (Test-Path $ConfigPath)) {
  $message = "Configuracao nao encontrada. Execute Configurar_Backup_Diario.bat."
  Write-Log $message "ERROR"
  Save-Status -Success $false -Message $message
  throw $message
}

$config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$SupabaseUrl = ([string]$config.SupabaseUrl).Trim().TrimEnd('/')
$BackupToken = ([string]$config.BackupToken).Trim()
$DestinationPath = [string]$config.DestinationPath
$ScheduledTime = if ($config.ScheduledTime) { [string]$config.ScheduledTime } else { "18:00" }

if (-not $SupabaseUrl.StartsWith("https://") -or $BackupToken.Length -lt 32 -or [string]::IsNullOrWhiteSpace($DestinationPath)) {
  $message = "Configuracao invalida. Execute novamente Configurar_Backup_Diario.bat."
  Write-Log $message "ERROR"
  Save-Status -Success $false -Message $message
  throw $message
}

Copy-PendingBackups -DestinationPath $DestinationPath

$lastSuccess = Get-LastSuccessDate
$today = (Get-Date).Date

if (-not $Force) {
  if ($CatchUp) {
    try { $scheduledSpan = [TimeSpan]::Parse($ScheduledTime) } catch { $scheduledSpan = [TimeSpan]::FromHours(18) }
    $targetDate = if ((Get-Date).TimeOfDay -ge $scheduledSpan) { $today } else { $today.AddDays(-1) }
    if ($lastSuccess -and $lastSuccess.Date -ge $targetDate) {
      Write-Log "Recuperacao dispensada: ja existe backup desde $($targetDate.ToString('yyyy-MM-dd'))."
      exit 0
    }
  }
  elseif ($lastSuccess -and $lastSuccess.Date -eq $today) {
    Write-Log "Backup de hoje ja existe. Execucao ignorada para evitar duplicidade."
    exit 0
  }
}

$Uri = "$SupabaseUrl/functions/v1/backup-aponta-p3"
$Headers = @{
  "x-backup-token" = $BackupToken
  "Content-Type" = "application/json"
}
if ($config.AnonKey -and ([string]$config.AnonKey).Trim()) {
  $anon = ([string]$config.AnonKey).Trim()
  $Headers["apikey"] = $anon
  $Headers["Authorization"] = "Bearer $anon"
}
$Body = @{ action = "export" } | ConvertTo-Json -Compress

$response = $null
$lastError = $null
$delays = @(0, 15, 45)

for ($attempt = 1; $attempt -le 3; $attempt++) {
  if ($delays[$attempt - 1] -gt 0) {
    Start-Sleep -Seconds $delays[$attempt - 1]
  }
  try {
    Write-Log "Solicitando backup ao Supabase. Tentativa $attempt de 3."
    $response = Invoke-RestMethod -Uri $Uri -Method Post -Headers $Headers -Body $Body -TimeoutSec 120
    if (-not $response.ok -or -not $response.backup) {
      $serverMessage = if ($response.error) { [string]$response.error } else { "Resposta de backup incompleta." }
      throw $serverMessage
    }
    break
  } catch {
    $lastError = $_.Exception.Message

    # Tenta capturar o corpo JSON retornado pelo Supabase para facilitar o diagnóstico.
    try {
      $httpResponse = $_.Exception.Response
      if ($httpResponse) {
        $stream = $httpResponse.GetResponseStream()
        if ($stream) {
          $reader = New-Object System.IO.StreamReader($stream)
          $responseBody = $reader.ReadToEnd()
          $reader.Dispose()
          if (-not [string]::IsNullOrWhiteSpace($responseBody)) {
            $lastError = "$lastError | Resposta do Supabase: $responseBody"
          }
        }
      }
    } catch {}

    Write-Log "Tentativa $attempt falhou: $lastError" "WARN"
    $response = $null
  }
}

if (-not $response) {
  $message = "O backup nao foi gerado apos 3 tentativas. $lastError"
  Write-Log $message "ERROR"
  Save-Status -Success $false -Message $message
  throw $message
}

$stamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$fileName = "Aponta_P3_Backup_$stamp.json"
$json = $response.backup | ConvertTo-Json -Depth 100

$storedInFallback = $false
if (Test-DestinationWritable $DestinationPath) {
  $finalPath = Join-Path $DestinationPath $fileName
} else {
  $storedInFallback = $true
  $finalPath = Join-Path $PendingDir $fileName
}

$tempPath = "$finalPath.tmp"
$json | Set-Content -Path $tempPath -Encoding UTF8
Move-Item -Path $tempPath -Destination $finalPath -Force

if ($storedInFallback) {
  $message = "Backup gerado, mas a pasta principal estava indisponivel. Arquivo salvo em Pendentes: $finalPath"
  Write-Log $message "WARN"
} else {
  $message = "Backup concluido: $finalPath. Registros: $($response.recordCount)."
  Write-Log $message
}

Save-Status -Success $true -Message $message -FilePath $finalPath -StoredInFallback $storedInFallback
Write-Output $message
exit 0
