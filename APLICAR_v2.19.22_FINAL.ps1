$ErrorActionPreference = "Stop"

$BaseDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Test-ApontaRoot {
  param([string]$Folder)
  if (-not $Folder) { return $false }
  if (-not (Test-Path $Folder -PathType Container)) { return $false }

  $required = @(
    "index.html",
    "app-v2.19.21.js",
    "style-v2.19.21.css",
    "sw.js"
  )

  foreach($file in $required){
    if(-not (Test-Path (Join-Path $Folder $file) -PathType Leaf)){
      return $false
    }
  }

  if(-not (Test-Path (Join-Path $Folder ".git") -PathType Container)){
    return $false
  }

  return $true
}

$RepoDir = $null

# Pacote extraído diretamente na raiz.
if(Test-ApontaRoot $BaseDir){
  $RepoDir = $BaseDir
}

# Pacote extraído em uma subpasta dentro da raiz.
if(-not $RepoDir){
  $ParentDir = Split-Path -Parent $BaseDir
  if(Test-ApontaRoot $ParentDir){
    $RepoDir = $ParentDir
  }
}

while(-not $RepoDir){
  Write-Host ""
  Write-Host "Nao localizei automaticamente a raiz do projeto." -ForegroundColor Yellow
  Write-Host "Cole a pasta que contem .git, index.html e app-v2.19.21.js." -ForegroundColor White
  $typed = Read-Host "CAMINHO"
  if($typed){ $typed = $typed.Trim().Trim('"') }

  if(Test-ApontaRoot $typed){
    $RepoDir = (Resolve-Path $typed).Path
  }else{
    Write-Host "Pasta invalida ou versao esperada nao encontrada." -ForegroundColor Red
  }
}

Write-Host ""
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host " APONTA HORAS - ATUALIZACAO v2.19.22" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Projeto:" -ForegroundColor Green
Write-Host $RepoDir -ForegroundColor Cyan
Write-Host ""

$indexPath = Join-Path $RepoDir "index.html"
$appPath   = Join-Path $RepoDir "app-v2.19.21.js"
$cssPath   = Join-Path $RepoDir "style-v2.19.21.css"
$swPath    = Join-Path $RepoDir "sw.js"

$index = [System.IO.File]::ReadAllText($indexPath).Replace("`r`n","`n")
$app   = [System.IO.File]::ReadAllText($appPath).Replace("`r`n","`n")
$css   = [System.IO.File]::ReadAllText($cssPath).Replace("`r`n","`n")
$sw    = [System.IO.File]::ReadAllText($swPath).Replace("`r`n","`n")

function Require-Text {
  param(
    [string]$Text,
    [string]$Needle,
    [string]$Label
  )

  if(-not $Text.Contains($Needle)){
    throw "Validacao falhou: $Label"
  }

  Write-Host ("OK - " + $Label) -ForegroundColor DarkGreen
}

function Replace-Once {
  param(
    [string]$Text,
    [string]$Old,
    [string]$New,
    [string]$Label
  )

  $count=[regex]::Matches(
    $Text,
    [regex]::Escape($Old)
  ).Count

  if($count -ne 1){
    throw "Esperava encontrar '$Label' uma vez, mas encontrei $count."
  }

  Write-Host ("OK - " + $Label) -ForegroundColor DarkGreen
  return $Text.Replace($Old,$New)
}

# -------------------------------------------------------------------
# 1. CONFIRMAR BASE ATUAL
# -------------------------------------------------------------------

Require-Text $index 'const BUILD = "2.19.21";' "index na v2.19.21"
Require-Text $index 'app-v2.19.21.js?build=2211' "app v2.19.21 no index"
Require-Text $app 'function buildClosingDailyBreakdown(' "calculo diario ja existente"
Require-Text $app 'function closingExcessSection(row)' "conferencia de excedentes do gestor"
Require-Text $app 'async function loadClosing() {' "fechamento atual"
Require-Text $app '$("submitClosingBtn").onclick=async()=>{' "envio do fechamento"
Require-Text $app 'const editable=isManager()||(x.user_id===me.id&&["rascunho","devolvido"].includes(x.status));' "edicao do proprio colaborador"

# -------------------------------------------------------------------
# 2. HTML - CONFERENCIA ANTES DO ENVIO
# -------------------------------------------------------------------

$oldPlan = @'
          <p id="closingPlanDetails" class="closing-plan-details">
            O planejado considera a jornada diária, os dias úteis, os feriados e as ausências aprovadas.
          </p>
'@

$newPlan = @'
          <p id="closingPlanDetails" class="closing-plan-details">
            O planejado considera a jornada diária, os dias úteis, os feriados e as ausências aprovadas.
          </p>

          <section id="currentClosingDailyReview" class="closing-daily-audit closing-daily-audit-ok">
            <div class="closing-daily-audit-heading">
              <div>
                <span>Conferência antes do fechamento</span>
                <strong id="currentClosingDailyReviewTitle">Jornada diária</strong>
                <small id="currentClosingDailyReviewHelp">
                  Consulte o mês para conferir dias com horas acima da jornada.
                </small>
              </div>
              <span id="currentClosingDailyReviewBadge" class="badge closing-daily-badge-ok">OK</span>
            </div>
            <div id="currentClosingDailyReviewList" class="closing-excess-days-list"></div>
          </section>
'@

$index = Replace-Once $index $oldPlan $newPlan "painel de conferencia antes do envio"

# -------------------------------------------------------------------
# 3. JAVASCRIPT - ESTADO + RENDER DO COLABORADOR
# -------------------------------------------------------------------

$insertBeforeLoadClosing = @'
  let currentClosingDailyReviewState={
    excess_days:[],
    total_excess_hours:0,
    user_id:"",
    month:"",
    status:"aberto"
  };

  function renderCurrentClosingDailyReview(
    userId,
    month,
    monthEntries,
    approvedAbsences,
    closingStatus="aberto"
  ){
    const panel=$("currentClosingDailyReview");
    const title=$("currentClosingDailyReviewTitle");
    const help=$("currentClosingDailyReviewHelp");
    const badge=$("currentClosingDailyReviewBadge");
    const list=$("currentClosingDailyReviewList");

    if(!panel||!title||!help||!badge||!list)return;

    const dailyBreakdown=buildClosingDailyBreakdown(
      userId,
      month,
      monthEntries,
      approvedAbsences
    );

    const excessDays=dailyBreakdown.filter(
      day=>day.excess_hours>0.009
    );

    const totalExcess=excessDays.reduce(
      (sum,day)=>sum+Number(day.excess_hours||0),
      0
    );

    currentClosingDailyReviewState={
      excess_days:excessDays,
      total_excess_hours:totalExcess,
      user_id:userId,
      month,
      status:closingStatus||"aberto"
    };

    const editableStatus=
      !["enviado","aprovado"].includes(closingStatus||"aberto");

    const canAdjust=
      editableStatus&&
      (userId===me.id||isManager());

    if(!excessDays.length){
      panel.classList.add("closing-daily-audit-ok");
      title.textContent="Nenhum dia com jornada excedida";
      help.textContent=
        "A conferência diária não encontrou horas acima da jornada planejada.";
      badge.textContent="OK";
      badge.className="badge closing-daily-badge-ok";
      list.innerHTML="";
      return;
    }

    panel.classList.remove("closing-daily-audit-ok");
    title.textContent=
      `${excessDays.length} dia${excessDays.length===1?"":"s"} com jornada excedida`;

    help.textContent=
      `Excedente diário acumulado: +${fmt(totalExcess)} h. `+
      `Confira antes de enviar. Se forem horas extras reais, os lançamentos podem ser mantidos.`;

    badge.textContent=`+${fmt(totalExcess)} h`;
    badge.className="badge closing-daily-badge-excess";

    list.innerHTML=excessDays.map(day=>`
      <article class="closing-excess-day-card current-closing-excess-day">
        <div class="closing-excess-day-date">
          <strong>${dateBR(day.date)}</strong>
          <span>${esc(day.day_type)}</span>
          <small>${esc(day.reason)}</small>
        </div>

        <div class="closing-excess-day-number">
          <span>Planejado</span>
          <strong>${fmt(day.planned_hours)} h</strong>
        </div>

        <div class="closing-excess-day-number">
          <span>Apontado</span>
          <strong>${fmt(day.pointed_hours)} h</strong>
        </div>

        <div class="closing-excess-day-number closing-excess-day-value">
          <span>Excedente</span>
          <strong>+${fmt(day.excess_hours)} h</strong>
        </div>

        <div class="closing-excess-day-number">
          <span>Lançamentos</span>
          <strong>${day.entries.length}</strong>
        </div>

        <div class="closing-excess-day-actions">
          ${
            canAdjust
              ?`<button
                  type="button"
                  class="btn secondary small"
                  data-current-closing-adjust-date="${day.date}"
                  data-current-closing-adjust-user="${userId}">
                  Ajustar apontamentos
                </button>`
              :`<span class="badge">
                  ${closingStatus==="aprovado"?"Aprovado":"Enviado"}
                </span>`
          }
        </div>
      </article>
    `).join("");
  }

  async function openCurrentClosingDayInEntries(userId,date){
    if(!userId||!date)return;

    if(userId!==me.id&&!isManager()){
      toast("Você só pode ajustar seus próprios apontamentos.",true);
      return;
    }

    if(
      ["enviado","aprovado"].includes(
        currentClosingDailyReviewState.status
      )
    ){
      toast(
        "Este fechamento já foi enviado ou aprovado. O período precisa ser devolvido antes do ajuste.",
        true
      );
      return;
    }

    if(isManager()&&$("filterEntryUser")){
      $("filterEntryUser").value=userId;
    }

    $("filterEntryStart").value=date;
    $("filterEntryEnd").value=date;

    const entriesButton=document.querySelector(
      '#mainNav button[data-page="entries"]'
    );

    if(entriesButton){
      entriesButton.click();
    }

    clearEntrySelection();
    await renderEntries();

    $("entriesTable")?.scrollIntoView({
      behavior:"smooth",
      block:"start"
    });

    toast(
      `Apontamentos de ${dateBR(date)} abertos para ajuste.`
    );
  }

'@

$app = Replace-Once `
  $app `
  '  async function loadClosing() {' `
  ($insertBeforeLoadClosing + '  async function loadClosing() {') `
  "funcoes da conferencia do colaborador"

# Render after monthly_closings current status is loaded.
$oldCurrent = @'
      currentClosing=data;
      $("closingStatus").textContent=statusLabel(data?.status||"aberto");
      $("closingNote").value=data?.review_note||"";
'@

$newCurrent = @'
      currentClosing=data;
      $("closingStatus").textContent=statusLabel(data?.status||"aberto");
      $("closingNote").value=data?.review_note||"";

      renderCurrentClosingDailyReview(
        userId,
        month,
        rows,
        approvedAbsences,
        data?.status||"aberto"
      );
'@

$app = Replace-Once $app $oldCurrent $newCurrent "render da conferencia no fechamento do mes"

# Click on adjustment shortcut.
$oldLoadBindings = @'
  $("loadClosingBtn").onclick=loadClosing;
  $("closingUser").onchange=loadClosing;
  $("closingMonth").onchange=loadClosing;
'@

$newLoadBindings = @'
  $("loadClosingBtn").onclick=loadClosing;
  $("closingUser").onchange=loadClosing;
  $("closingMonth").onchange=loadClosing;

  if($("currentClosingDailyReview")){
    $("currentClosingDailyReview").onclick=async event=>{
      const button=event.target.closest(
        "[data-current-closing-adjust-date]"
      );
      if(!button)return;

      await openCurrentClosingDayInEntries(
        button.dataset.currentClosingAdjustUser,
        button.dataset.currentClosingAdjustDate
      );
    };
  }
'@

$app = Replace-Once $app $oldLoadBindings $newLoadBindings "atalho Ajustar apontamentos"

# Confirmation before submit, but no hard block.
$oldSubmit = @'
  $("submitClosingBtn").onclick=async()=>{
    const userId=isManager()?$("closingUser").value:me.id;
    const targetProfile=profiles.find(profile=>profile.id===userId);
'@

$newSubmit = @'
  $("submitClosingBtn").onclick=async()=>{
    const userId=isManager()?$("closingUser").value:me.id;

    if(
      currentClosingDailyReviewState.user_id===userId&&
      currentClosingDailyReviewState.excess_days.length
    ){
      const review=currentClosingDailyReviewState;
      const confirmed=window.confirm(
        `CONFERÊNCIA ANTES DO FECHAMENTO\n\n`+
        `${review.excess_days.length} dia${review.excess_days.length===1?"":"s"} `+
        `possui${review.excess_days.length===1?"":"em"} horas acima da jornada.\n`+
        `Excedente diário acumulado: +${fmt(review.total_excess_hours)} h.\n\n`+
        `Se forem horas extras reais, você pode manter os lançamentos e enviar.\n`+
        `Se houver erro de apontamento, clique em Cancelar e use "Ajustar apontamentos".\n\n`+
        `Deseja enviar mesmo assim?`
      );

      if(!confirmed)return;
    }

    const targetProfile=profiles.find(profile=>profile.id===userId);
'@

$app = Replace-Once $app $oldSubmit $newSubmit "confirmacao antes do envio"

# -------------------------------------------------------------------
# 4. CSS - PEQUENOS AJUSTES DO PAINEL ATUAL
# -------------------------------------------------------------------

$css += @'

/* ==========================================================
   v2.19.22 — conferência do colaborador antes do fechamento
   ========================================================== */
#currentClosingDailyReview{
  margin:14px 0 18px;
}
#currentClosingDailyReview .closing-excess-days-list{
  margin-top:10px;
}
.current-closing-excess-day{
  border-color:#ead7d5;
}
#currentClosingDailyReview .closing-excess-day-actions .badge{
  display:inline-block;
}
@media(max-width:700px){
  #currentClosingDailyReview{
    padding:11px;
  }
}
'@

# -------------------------------------------------------------------
# 5. VERSAO 2.19.22 / BUILD 2212
# -------------------------------------------------------------------

$index = Replace-Once $index 'manifest.webmanifest?v=2.19.21' 'manifest.webmanifest?v=2.19.22' "manifest v2.19.22"
$index = Replace-Once $index 'style-v2.19.21.css?build=2211' 'style-v2.19.22.css?build=2212' "style build 2212"
$index = Replace-Once $index 'const BUILD = "2.19.21";' 'const BUILD = "2.19.22";' "BUILD v2.19.22"
$index = Replace-Once $index 'const ASSET_BUILD = "2211";' 'const ASSET_BUILD = "2212";' "ASSET_BUILD 2212"
$index = Replace-Once $index 'app-v2.19.21.js?build=2211' 'app-v2.19.22.js?build=2212' "app build 2212"
$index = Replace-Once $index 'navigator.serviceWorker.register("./sw.js?v=2.19.21"' 'navigator.serviceWorker.register("./sw.js?v=2.19.22"' "service worker v2.19.22"

# O service worker atual ja esta na v2.19.21. Atualizar para v2.19.22.
$sw = Replace-Once $sw 'const CACHE = "aponta-horas-v2.19.21-excedentes-fechamento";' 'const CACHE = "aponta-horas-v2.19.22-colaborador-fechamento";' "cache novo"
$sw = Replace-Once $sw '"./app-v2.19.21.js?build=2211",' '"./app-v2.19.22.js?build=2212",' "app no cache"
$sw = Replace-Once $sw '"./style-v2.19.21.css?build=2211",' '"./style-v2.19.22.css?build=2212",' "style no cache"
$sw = Replace-Once $sw '"./manifest.webmanifest?v=2.19.21",' '"./manifest.webmanifest?v=2.19.22",' "manifest no cache"

# -------------------------------------------------------------------
# 6. VALIDAR ANTES DE ALTERAR A RAIZ
# -------------------------------------------------------------------

$checks=@(
  @{Label="painel HTML"; Ok=$index.Contains('id="currentClosingDailyReview"')},
  @{Label="render diario"; Ok=$app.Contains("function renderCurrentClosingDailyReview(")},
  @{Label="atalho de ajuste"; Ok=$app.Contains("function openCurrentClosingDayInEntries(")},
  @{Label="confirmacao de excedente"; Ok=$app.Contains("CONFERÊNCIA ANTES DO FECHAMENTO")},
  @{Label="reuso do calculo diario"; Ok=$app.Contains("buildClosingDailyBreakdown(")},
  @{Label="v2.19.22 no index"; Ok=$index.Contains('const BUILD = "2.19.22";')},
  @{Label="cache 2.19.22"; Ok=$sw.Contains("aponta-horas-v2.19.22-colaborador-fechamento")}
)

foreach($check in $checks){
  if(-not $check.Ok){
    throw ("Validacao final falhou: " + $check.Label)
  }
  Write-Host ("VALIDADO - " + $check.Label) -ForegroundColor Green
}

# -------------------------------------------------------------------
# 7. BACKUP + GRAVAR ARQUIVOS NOVOS
# -------------------------------------------------------------------

$stamp=Get-Date -Format "yyyyMMdd-HHmmss"
$backup=Join-Path $RepoDir ("BACKUP_ANTES_v2.19.22_" + $stamp)
New-Item -ItemType Directory -Path $backup | Out-Null

Copy-Item $indexPath (Join-Path $backup "index.html") -Force
Copy-Item $appPath (Join-Path $backup "app-v2.19.21.js") -Force
Copy-Item $cssPath (Join-Path $backup "style-v2.19.21.css") -Force
Copy-Item $swPath (Join-Path $backup "sw.js") -Force

$utf8NoBom=New-Object System.Text.UTF8Encoding($false)

[System.IO.File]::WriteAllText(
  $indexPath,
  $index,
  $utf8NoBom
)

[System.IO.File]::WriteAllText(
  (Join-Path $RepoDir "app-v2.19.22.js"),
  $app,
  $utf8NoBom
)

[System.IO.File]::WriteAllText(
  (Join-Path $RepoDir "style-v2.19.22.css"),
  $css,
  $utf8NoBom
)

[System.IO.File]::WriteAllText(
  $swPath,
  $sw,
  $utf8NoBom
)

Write-Host ""
Write-Host "Backup criado:" -ForegroundColor Cyan
Write-Host $backup -ForegroundColor Yellow

# Node check if available.
$node=Get-Command node -ErrorAction SilentlyContinue
if($node){
  Write-Host ""
  Write-Host "Validando sintaxe JavaScript com Node..." -ForegroundColor Cyan
  & node --check (Join-Path $RepoDir "app-v2.19.22.js")
  if($LASTEXITCODE -ne 0){
    throw "O Node encontrou erro de sintaxe no JavaScript. Nada sera enviado ao GitHub."
  }
  Write-Host "OK - JavaScript sem erro de sintaxe." -ForegroundColor Green
}else{
  Write-Host ""
  Write-Host "Node nao instalado. Validacao estrutural concluida; teste de sintaxe Node foi ignorado." -ForegroundColor Yellow
}

# -------------------------------------------------------------------
# 8. GIT COMMIT + PUSH
# -------------------------------------------------------------------

Set-Location $RepoDir

$git=Get-Command git -ErrorAction SilentlyContinue
if(-not $git){
  throw "Git nao encontrado no Windows."
}

Write-Host ""
Write-Host "Arquivos alterados:" -ForegroundColor Cyan
& git status --short

& git add index.html app-v2.19.22.js style-v2.19.22.css sw.js
if($LASTEXITCODE -ne 0){
  throw "Falha no git add."
}

& git diff --cached --quiet
$hasChanges=($LASTEXITCODE -ne 0)

if($hasChanges){
  & git commit -m "v2.19.22 - colaborador confere e ajusta antes do fechamento"
  if($LASTEXITCODE -ne 0){
    throw "Falha no git commit."
  }
}else{
  Write-Host "Nenhuma alteracao nova para commit." -ForegroundColor Yellow
}

$branch=(& git branch --show-current).Trim()
if(-not $branch){ $branch="main" }

Write-Host ""
Write-Host ("Enviando para origin/" + $branch + "...") -ForegroundColor Cyan

& git push origin $branch
if($LASTEXITCODE -ne 0){
  throw "Falha no git push."
}

Write-Host ""
Write-Host "==============================================================" -ForegroundColor Green
Write-Host " SUCESSO - v2.19.22 ENVIADA PARA O GITHUB" -ForegroundColor Green
Write-Host "==============================================================" -ForegroundColor Green
Write-Host ""
& git log -1 --oneline
Write-Host ""
Write-Host "Depois do deploy, abra o app e atualize a pagina." -ForegroundColor White
