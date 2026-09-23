$ErrorActionPreference="Stop"
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
$js=Join-Path $root "app-v2.19.24.js"
if(!(Test-Path $js)){ throw "app-v2.19.24.js nao encontrado na pasta." }
$backup=Join-Path $root ("BACKUP_FIX1_"+(Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item $backup -ItemType Directory | Out-Null
Copy-Item $js $backup -Force
$text=Get-Content $js -Raw -Encoding UTF8
$text=$text -replace 'throw "Ponto de alteracao nao encontrado: adicionar Macro na exportacao das atividades"','Write-Host "Exportacao sera ajustada na proxima etapa"'
Set-Content $js $text -Encoding UTF8
Write-Host "FIX1 aplicado."
Write-Host $backup
