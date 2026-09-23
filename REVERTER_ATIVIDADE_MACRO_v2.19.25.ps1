$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Backup = Get-ChildItem -Path $Root -Directory -Filter "BACKUP_ANTES_ATIVIDADE_MACRO_v2.19.25_*" |
          Sort-Object Name -Descending |
          Select-Object -First 1

if(-not $Backup){
    throw "Nenhum backup da v2.19.25 foi encontrado."
}

Copy-Item (Join-Path $Backup.FullName "app-v2.19.24.js") (Join-Path $Root "app-v2.19.24.js") -Force
Copy-Item (Join-Path $Backup.FullName "index.html") (Join-Path $Root "index.html") -Force
Copy-Item (Join-Path $Backup.FullName "sw.js") (Join-Path $Root "sw.js") -Force

$NewJs = Join-Path $Root "app-v2.19.25.js"
if(Test-Path $NewJs){ Remove-Item $NewJs -Force }

Write-Host "Reversao concluida usando:" -ForegroundColor Green
Write-Host $Backup.FullName
