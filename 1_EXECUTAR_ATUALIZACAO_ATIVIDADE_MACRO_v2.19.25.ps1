$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$payload = Join-Path $root "payload"
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backup = Join-Path $root ("BACKUP_ANTES_v2.19.25_" + $stamp)
$log = Join-Path $root ("ATUALIZACAO_v2.19.25_" + $stamp + ".log")
function Log($m){ $m | Tee-Object -FilePath $log -Append }
Log "APONTA P3 v2.19.25 - Atividade Macro"
$required=@("index.html","sw.js","app-v2.19.24.js")
foreach($f in $required){ if(-not (Test-Path (Join-Path $root $f))){ throw "Execute este atualizador dentro da pasta raiz do APONT MAN P3. Arquivo ausente: $f" } }
New-Item -ItemType Directory -Path $backup | Out-Null
foreach($f in @("index.html","sw.js","app-v2.19.24.js")){ Copy-Item (Join-Path $root $f) (Join-Path $backup $f) -Force }
Log "Backup criado em: $backup"
Copy-Item (Join-Path $payload "app-v2.19.25.js") (Join-Path $root "app-v2.19.25.js") -Force
Copy-Item (Join-Path $payload "index.html") (Join-Path $root "index.html") -Force
Copy-Item (Join-Path $payload "sw.js") (Join-Path $root "sw.js") -Force
Log "Arquivos locais atualizados para v2.19.25."
Log "IMPORTANTE: execute ATUALIZAR_BANCO_v2.19.25_ATIVIDADE_MACRO.sql no Supabase SQL Editor antes de usar o sistema."
Write-Host ""
Write-Host "ATUALIZACAO LOCAL CONCLUIDA." -ForegroundColor Green
Write-Host "Agora execute o SQL ATUALIZAR_BANCO_v2.19.25_ATIVIDADE_MACRO.sql no Supabase." -ForegroundColor Yellow
Write-Host "Depois publique/suba a revisao como voce ja faz normalmente." -ForegroundColor Cyan
Pause
