param(
    [string]$RepoPath = ""
)

$ErrorActionPreference = "Stop"

function Fail([string]$Message) {
    Write-Host ""
    Write-Host "ERRO: $Message" -ForegroundColor Red
    Write-Host ""
    Read-Host "Pressione ENTER para fechar"
    exit 1
}

function Info([string]$Message) {
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Ok([string]$Message) {
    Write-Host "OK: $Message" -ForegroundColor Green
}

function Find-Repo {
    param([string]$ExplicitPath)

    $candidates = @()

    if ($ExplicitPath) {
        $candidates += $ExplicitPath
    }

    $candidates += (Get-Location).Path
    $candidates += "C:\Projetos\apontamentos-engmanufatura"
    $candidates += "C:\Projetos\APONTA_P3"
    $candidates += "C:\Projetos\APONT.MAN"
    $candidates += "$env:USERPROFILE\Documents\apontamentos-engmanufatura"
    $candidates += "$env:USERPROFILE\Desktop\apontamentos-engmanufatura"

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (-not $candidate) { continue }

        $resolved = $candidate
        if (Test-Path $resolved) {
            if (
                (Test-Path (Join-Path $resolved ".git")) -and
                (Test-Path (Join-Path $resolved "app-v2.19.23.js")) -and
                (Test-Path (Join-Path $resolved "index.html")) -and
                (Test-Path (Join-Path $resolved "sw.js"))
            ) {
                return (Resolve-Path $resolved).Path
            }
        }
    }

    return $null
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor DarkCyan
Write-Host " APONTA P3 - CORRECAO AUTOMATICA RELATORIOS > 1000" -ForegroundColor White
Write-Host " Versao alvo: 2.19.24 / build 2214" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor DarkCyan
Write-Host ""

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Fail "Git nao foi encontrado no Windows."
}

$repo = Find-Repo -ExplicitPath $RepoPath
if (-not $repo) {
    Fail "Nao encontrei o repositorio. Execute o BAT dentro do repositorio ou informe o caminho como parametro."
}

Info "Repositorio encontrado: $repo"

$origin = (& git -C $repo remote get-url origin 2>$null)
if ($LASTEXITCODE -ne 0) {
    Fail "O repositorio nao possui remote origin."
}

if ($origin -notmatch "RLM86/apontamentos-engmanufatura") {
    Fail "O origin encontrado nao parece ser RLM86/apontamentos-engmanufatura: $origin"
}
Ok "Repositorio correto."

$currentBranch = (& git -C $repo branch --show-current).Trim()
if ($currentBranch -ne "main") {
    Info "Mudando para a branch main..."
    & git -C $repo checkout main
    if ($LASTEXITCODE -ne 0) {
        Fail "Nao consegui mudar para a branch main."
    }
}

$status = & git -C $repo status --porcelain
if ($status) {
    Write-Host ""
    Write-Host "Existem alteracoes locais no repositorio:" -ForegroundColor Yellow
    $status | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
    Fail "Para sua seguranca, o script nao vai misturar esta correcao com alteracoes locais. Salve/commit suas alteracoes e execute novamente."
}

Info "Atualizando a branch main..."
& git -C $repo pull --ff-only origin main
if ($LASTEXITCODE -ne 0) {
    Fail "git pull falhou."
}
Ok "Branch atualizada."

$sourceApp = Join-Path $repo "app-v2.19.23.js"
$targetApp = Join-Path $repo "app-v2.19.24.js"
$indexFile = Join-Path $repo "index.html"
$swFile = Join-Path $repo "sw.js"

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupDir = Join-Path $repo "_backup_fix_relatorios_$stamp"
New-Item -ItemType Directory -Path $backupDir | Out-Null
Copy-Item $sourceApp (Join-Path $backupDir "app-v2.19.23.js")
Copy-Item $indexFile (Join-Path $backupDir "index.html")
Copy-Item $swFile (Join-Path $backupDir "sw.js")
Ok "Backup local dos 3 arquivos criado em $backupDir"

Info "Criando app-v2.19.24.js..."
$app = Get-Content $sourceApp -Raw -Encoding UTF8

$startMarker = '  async function selectEntries(start, end, userId = "", projectId = "") {'
$endMarker = '  async function selectAbsencesForReport(start, end, userId = "", typeFilter = "") {'

$startIndex = $app.IndexOf($startMarker)
if ($startIndex -lt 0) {
    Fail "Nao encontrei o inicio da funcao selectEntries no app-v2.19.23.js."
}

$endIndex = $app.IndexOf($endMarker, $startIndex)
if ($endIndex -lt 0) {
    Fail "Nao encontrei o fim da funcao selectEntries."
}

$newFunction = @'
  async function selectEntries(start, end, userId = "", projectId = "") {
    const allRows = [];
    const pageSize = 1000;
    let from = 0;

    while (true) {
      const {data,error}=await sb.rpc(
        "aponta_select_time_entries_v2187",
        {
          p_start_date:start,
          p_end_date:end,
          p_user_id:userId||null,
          p_project_id:projectId||null
        }
      ).range(from, from + pageSize - 1);

      if(error){
        const message=String(error.message||"");
        if(
          message.includes("aponta_select_time_entries_v2187")||
          message.includes("Could not find the function")||
          message.includes("function public.aponta_select_time_entries_v2187")
        ){
          throw new Error(
            "Consulta geral de apontamentos não instalada. " +
            "Execute o SQL obrigatório da versão 2.18.7 no Supabase."
          );
        }

        throw error;
      }

      const page=data||[];
      allRows.push(...page);

      if(page.length < pageSize)break;
      from += pageSize;
    }

    return allRows.sort((a,b)=>{
      const dateComparison=String(b.entry_date||"").localeCompare(
        String(a.entry_date||"")
      );

      if(dateComparison)return dateComparison;

      const createdComparison=String(b.created_at||"").localeCompare(
        String(a.created_at||"")
      );

      if(createdComparison)return createdComparison;

      return String(b.id||"").localeCompare(String(a.id||""));
    });
  }
'@

$app = $app.Substring(0, $startIndex) + $newFunction + "`r`n" + $app.Substring($endIndex)

# Atualiza o service worker registrado dentro do JS e a versao exposta do app.
$app = $app.Replace('register("sw.js?v=2.19.14", {updateViaCache:"none"})', 'register("sw.js?v=2.19.24", {updateViaCache:"none"})')
$app = $app.Replace('window.APONTA_P3_VERSION = "2.19.19";', 'window.APONTA_P3_VERSION = "2.19.24";')

Set-Content -Path $targetApp -Value $app -Encoding UTF8
Ok "app-v2.19.24.js criado com paginacao."

Info "Atualizando index.html para versao 2.19.24 / build 2214..."
$index = Get-Content $indexFile -Raw -Encoding UTF8

$requiredIndexTokens = @(
    'const BUILD = "2.19.23";',
    'const ASSET_BUILD = "2213";',
    'app-v2.19.23.js?build=2213',
    'sw.js?v=2.19.23'
)
foreach ($token in $requiredIndexTokens) {
    if (-not $index.Contains($token)) {
        Fail "index.html mudou e nao contem o trecho esperado: $token"
    }
}

$index = $index.Replace('manifest.webmanifest?v=2.19.23', 'manifest.webmanifest?v=2.19.24')
$index = $index.Replace('const BUILD = "2.19.23";', 'const BUILD = "2.19.24";')
$index = $index.Replace('const ASSET_BUILD = "2213";', 'const ASSET_BUILD = "2214";')
$index = $index.Replace('app-v2.19.23.js?build=2213', 'app-v2.19.24.js?build=2214')
$index = $index.Replace('sw.js?v=2.19.23', 'sw.js?v=2.19.24')

Set-Content -Path $indexFile -Value $index -Encoding UTF8
Ok "index.html atualizado."

Info "Atualizando sw.js e cache da PWA..."
$sw = Get-Content $swFile -Raw -Encoding UTF8

if (-not $sw.Contains('app-v2.19.23.js?build=2213')) {
    Fail "sw.js mudou e nao contem app-v2.19.23.js?build=2213."
}

$sw = [regex]::Replace(
    $sw,
    'const CACHE = "[^"]+";',
    'const CACHE = "aponta-horas-v2.19.24-relatorios-paginados";',
    1
)
$sw = $sw.Replace('app-v2.19.23.js?build=2213', 'app-v2.19.24.js?build=2214')
$sw = $sw.Replace('manifest.webmanifest?v=2.19.23', 'manifest.webmanifest?v=2.19.24')

Set-Content -Path $swFile -Value $sw -Encoding UTF8
Ok "sw.js atualizado."

Info "Validando a correcao..."

$appCheck = Get-Content $targetApp -Raw -Encoding UTF8
if (-not $appCheck.Contains('.range(from, from + pageSize - 1)')) {
    Fail "A paginacao nao foi encontrada no novo JS."
}
if (-not $appCheck.Contains('from += pageSize;')) {
    Fail "O incremento da paginacao nao foi encontrado."
}

$indexCheck = Get-Content $indexFile -Raw -Encoding UTF8
if (-not $indexCheck.Contains('app-v2.19.24.js?build=2214')) {
    Fail "index.html nao aponta para o novo JS."
}

$swCheck = Get-Content $swFile -Raw -Encoding UTF8
if (-not $swCheck.Contains('aponta-horas-v2.19.24-relatorios-paginados')) {
    Fail "O novo cache do service worker nao foi aplicado."
}

if (Get-Command node -ErrorAction SilentlyContinue) {
    & node --check $targetApp
    if ($LASTEXITCODE -ne 0) {
        Fail "O Node encontrou erro de sintaxe em app-v2.19.24.js."
    }
    Ok "JavaScript validado com node --check."
} else {
    Write-Host "AVISO: Node nao encontrado. A verificacao textual passou, mas node --check foi ignorado." -ForegroundColor Yellow
}

& git -C $repo diff --check
if ($LASTEXITCODE -ne 0) {
    Fail "git diff --check encontrou problema."
}
Ok "git diff --check passou."

Write-Host ""
Info "Arquivos que serao publicados:"
& git -C $repo status --short
Write-Host ""

Info "Criando commit..."
& git -C $repo add -- "app-v2.19.24.js" "index.html" "sw.js"
if ($LASTEXITCODE -ne 0) {
    Fail "git add falhou."
}

& git -C $repo commit -m "fix: paginate reports beyond 1000 entries"
if ($LASTEXITCODE -ne 0) {
    Fail "git commit falhou."
}
Ok "Commit criado."

Info "Enviando para GitHub..."
& git -C $repo push origin main
if ($LASTEXITCODE -ne 0) {
    Fail "git push falhou. O commit ficou salvo localmente."
}
Ok "Push concluido."

$head = (& git -C $repo rev-parse --short HEAD).Trim()

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " CORRECAO PUBLICADA COM SUCESSO" -ForegroundColor Green
Write-Host " Commit: $head" -ForegroundColor White
Write-Host " Versao: 2.19.24" -ForegroundColor White
Write-Host " Build: 2214" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Aguarde a publicacao automatica do site e depois:" -ForegroundColor White
Write-Host "1. Feche/abra o app ou use Ctrl+F5." -ForegroundColor White
Write-Host "2. Va em Relatorios." -ForegroundColor White
Write-Host "3. Gere novamente 01/04/2026 a 31/08/2026." -ForegroundColor White
Write-Host "4. O total nao deve mais parar em 1000." -ForegroundColor White
Write-Host ""

try {
    Start-Process "https://apontamentos-engmanufatura.modulardtc.workers.dev/?build=2214"
} catch {}

Read-Host "Pressione ENTER para fechar"
