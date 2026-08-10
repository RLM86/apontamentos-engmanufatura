$ErrorActionPreference = "Stop"

$BaseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Required = @(
  "index.html",
  "app-v2.19.20.js",
  "style-v2.19.20.css",
  "sw.js"
)

function Test-ApontaFolder {
  param([string]$Folder)
  if (-not $Folder) { return $false }
  if (-not (Test-Path $Folder -PathType Container)) { return $false }
  foreach ($file in $Required) {
    if (-not (Test-Path (Join-Path $Folder $file) -PathType Leaf)) {
      return $false
    }
  }
  return $true
}

$RepoDir = $null
if (Test-ApontaFolder $BaseDir) {
  $RepoDir = $BaseDir
}
if (-not $RepoDir) {
  $ParentDir = Split-Path -Parent $BaseDir
  if (Test-ApontaFolder $ParentDir) {
    $RepoDir = $ParentDir
  }
}
while (-not $RepoDir) {
  Write-Host ""
  Write-Host "Cole o caminho da raiz do projeto APONTA P3:" -ForegroundColor Yellow
  $typed = Read-Host "CAMINHO"
  if ($typed) { $typed = $typed.Trim().Trim('"') }
  if (Test-ApontaFolder $typed) {
    $RepoDir = (Resolve-Path $typed).Path
  } else {
    Write-Host "Pasta invalida. Ela precisa conter index.html, app-v2.19.20.js, style-v2.19.20.css e sw.js." -ForegroundColor Red
  }
}

Write-Host ""
Write-Host "Projeto localizado em:" -ForegroundColor Green
Write-Host $RepoDir -ForegroundColor Cyan
Write-Host ""

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$indexPath = Join-Path $RepoDir "index.html"
$appPath   = Join-Path $RepoDir "app-v2.19.20.js"
$cssPath   = Join-Path $RepoDir "style-v2.19.20.css"
$swPath    = Join-Path $RepoDir "sw.js"

$index = [System.IO.File]::ReadAllText($indexPath).Replace("`r`n","`n")
$app   = [System.IO.File]::ReadAllText($appPath).Replace("`r`n","`n")
$css   = [System.IO.File]::ReadAllText($cssPath).Replace("`r`n","`n")
$sw    = [System.IO.File]::ReadAllText($swPath).Replace("`r`n","`n")

function Require-Contains {
  param([string]$Text,[string]$Needle,[string]$Label)
  if (-not $Text.Contains($Needle)) {
    throw "Nao encontrei: $Label"
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
  $count = [regex]::Matches($Text,[regex]::Escape($Old)).Count
  if ($count -ne 1) {
    throw "Esperava encontrar 1 vez '$Label', mas encontrei $count."
  }
  Write-Host ("OK - " + $Label) -ForegroundColor DarkGreen
  return $Text.Replace($Old,$New)
}

Require-Contains $index 'const BUILD = "2.19.20";' "versao 2.19.20"
Require-Contains $app 'async function loadClosing() {' "loadClosing"
Require-Contains $app '$("submitClosingBtn").onclick=async()=>{' "envio de fechamento"
Require-Contains $app 'const editable=isManager()||(x.user_id===me.id&&["rascunho","devolvido"].includes(x.status));' "edicao do colaborador em apontamentos"

# ==============================================================
# INDEX — painel de conferencia antes do envio
# ==============================================================

$oldClosingPlan = @'
          <p id="closingPlanDetails" class="closing-plan-details">
            O planejado considera a jornada diária, os dias úteis, os feriados e as ausências aprovadas.
          </p>
'@

$newClosingPlan = @'
          <p id="closingPlanDetails" class="closing-plan-details">
            O planejado considera a jornada diária, os dias úteis, os feriados e as ausências aprovadas.
          </p>

          <section id="closingDailyReview" class="closing-daily-review">
            <div class="closing-daily-review-heading">
              <div>
                <span class="eyebrow">Conferência antes do fechamento</span>
                <h3>Dias com diferença de jornada</h3>
                <p id="closingDailyReviewHelp">
                  Confira os dias com horas acima da jornada antes de enviar o mês.
                </p>
              </div>
              <span id="closingDailyReviewBadge" class="badge">Analisando...</span>
            </div>
            <div id="closingDailyReviewList" class="closing-daily-review-list"></div>
          </section>
'@

$index = Replace-Once $index $oldClosingPlan $newClosingPlan "painel de conferencia no fechamento"

# ==============================================================
# APP — conferencia diaria + atalho para ajustar
# ==============================================================

$dailyFunctions = @'
  /* APONTA P3 v2.19.21 — conferencia do colaborador antes do fechamento */
  let currentClosingDailyReview={
    excess_days:[],
    total_excess_hours:0
  };

  function closingDailyPlanForDate(userId,date,approvedAbsences=[]){
    const cursor=new Date(`${date}T12:00:00Z`);
    const dayOfWeek=cursor.getUTCDay();
    const dailyHours=profileDailyHours(userId);

    const holiday=holidays.find(
      row=>String(row.holiday_date||"").slice(0,10)===date
    );

    const absence=approvedAbsences.find(row=>
      row.user_id===userId&&
      row.start_date<=date&&
      row.end_date>=date
    );

    if(dayOfWeek===0){
      return {planned_hours:0,label:"Domingo"};
    }
    if(dayOfWeek===6){
      return {planned_hours:0,label:"Sábado"};
    }
    if(holiday){
      return {planned_hours:0,label:holiday.name||"Feriado"};
    }
    if(absence){
      return {
        planned_hours:0,
        label:absenceTypeLabel(absence.absence_type)
      };
    }

    return {
      planned_hours:dailyHours,
      label:"Dia útil"
    };
  }

  function buildClosingDailyReview(userId,month,rows,approvedAbsences=[]){
    const byDate=new Map();

    rows.forEach(entry=>{
      const date=String(entry.entry_date||"").slice(0,10);
      if(!date)return;
      if(!byDate.has(date))byDate.set(date,[]);
      byDate.get(date).push(entry);
    });

    const days=[...byDate.entries()]
      .map(([date,entries])=>{
        const pointed=entries.reduce(
          (sum,entry)=>sum+Number(entry.hours||0),
          0
        );
        const plan=closingDailyPlanForDate(
          userId,
          date,
          approvedAbsences
        );
        const difference=
          pointed-Number(plan.planned_hours||0);

        return {
          date,
          entries,
          pointed_hours:pointed,
          planned_hours:Number(plan.planned_hours||0),
          difference_hours:difference,
          excess_hours:difference>0.009?difference:0,
          label:plan.label
        };
      })
      .sort((a,b)=>a.date.localeCompare(b.date));

    const excessDays=days.filter(
      day=>day.excess_hours>0.009
    );

    return {
      days,
      excess_days:excessDays,
      total_excess_hours:excessDays.reduce(
        (sum,day)=>sum+Number(day.excess_hours||0),
        0
      )
    };
  }

  function renderClosingDailyReview(
    userId,
    month,
    rows,
    approvedAbsences=[],
    closingStatus="aberto"
  ){
    const panel=$("closingDailyReview");
    const list=$("closingDailyReviewList");
    const badge=$("closingDailyReviewBadge");
    const help=$("closingDailyReviewHelp");

    if(!panel||!list||!badge)return;

    const review=buildClosingDailyReview(
      userId,
      month,
      rows,
      approvedAbsences
    );
    currentClosingDailyReview=review;

    const ownPeriod=
      userId===me.id;
    const editableStatus=
      !["enviado","aprovado"].includes(closingStatus);
    const canAdjust=
      editableStatus&&(ownPeriod||isManager());

    if(!review.excess_days.length){
      badge.textContent="Sem excedentes";
      badge.className="badge closing-daily-review-badge success";
      help.textContent=
        "Nenhum dia com horas acima da jornada foi encontrado.";
      list.innerHTML=`
        <div class="closing-daily-review-empty">
          <strong>Jornada diária conferida</strong>
          <span>Você pode seguir para o envio do fechamento.</span>
        </div>
      `;
      return;
    }

    badge.textContent=
      `+${fmt(review.total_excess_hours)} h`;
    badge.className="badge closing-daily-review-badge danger";

    help.textContent=
      `${review.excess_days.length} dia${review.excess_days.length===1?"":"s"} com jornada excedida. `+
      `Confira antes de enviar; horas extras reais podem ser mantidas.`;

    list.innerHTML=review.excess_days.map(day=>`
      <article class="closing-daily-review-row">
        <div class="closing-daily-review-date">
          <strong>${dateBR(day.date)}</strong>
          <span>${esc(day.label)}</span>
        </div>
        <div>
          <span>Planejado</span>
          <strong>${fmt(day.planned_hours)} h</strong>
        </div>
        <div>
          <span>Apontado</span>
          <strong>${fmt(day.pointed_hours)} h</strong>
        </div>
        <div class="closing-daily-review-excess">
          <span>Excedente</span>
          <strong>+${fmt(day.excess_hours)} h</strong>
        </div>
        <div>
          <span>Lançamentos</span>
          <strong>${day.entries.length}</strong>
        </div>
        <div class="closing-daily-review-actions">
          ${
            canAdjust
              ?`<button
                  type="button"
                  class="btn secondary small"
                  data-closing-adjust-date="${day.date}"
                  data-closing-adjust-user="${userId}">
                  Ajustar apontamentos
                </button>`
              :`<span class="badge">
                  ${closingStatus==="enviado"?"Enviado":"Bloqueado"}
                </span>`
          }
        </div>
      </article>
    `).join("");
  }

  async function openClosingDayForAdjustment(userId,date){
    if(!userId||!date)return;

    if(userId!==me.id&&!isManager()){
      toast("Você só pode ajustar seus próprios apontamentos.",true);
      return;
    }

    if(isManager()&&$("filterEntryUser")){
      $("filterEntryUser").value=userId;
    }

    $("filterEntryStart").value=date;
    $("filterEntryEnd").value=date;

    const navButton=document.querySelector(
      '#mainNav button[data-page="entries"]'
    );

    if(navButton){
      navButton.click();
    }

    clearEntrySelection();
    await renderEntries();

    $("entriesTable")?.scrollIntoView({
      behavior:"smooth",
      block:"start"
    });

    toast(
      `Apontamentos de ${dateBR(date)} abertos para conferência.`
    );
  }

'@

$app = Replace-Once `
  $app `
  '  async function loadClosing() {' `
  ($dailyFunctions + '  async function loadClosing() {') `
  "funcoes de conferencia antes do loadClosing"

# Inserir renderização após currentClosing/data serem conhecidos.
$oldClosingState = @'
      currentClosing=data;
      $("closingStatus").textContent=statusLabel(data?.status||"aberto");
      $("closingNote").value=data?.review_note||"";
'@

$newClosingState = @'
      currentClosing=data;
      $("closingStatus").textContent=statusLabel(data?.status||"aberto");
      $("closingNote").value=data?.review_note||"";

      renderClosingDailyReview(
        userId,
        month,
        rows,
        approvedAbsences,
        data?.status||"aberto"
      );
'@

$app = Replace-Once $app $oldClosingState $newClosingState "renderizacao diaria no fechamento"

# Clique no botão Ajustar apontamentos.
$clickHandlers = @'
  if($("closingDailyReview")){
    $("closingDailyReview").onclick=async event=>{
      const button=event.target.closest(
        "[data-closing-adjust-date]"
      );
      if(!button)return;

      await openClosingDayForAdjustment(
        button.dataset.closingAdjustUser,
        button.dataset.closingAdjustDate
      );
    };
  }

'@

$app = Replace-Once `
  $app `
  '  $("loadClosingBtn").onclick=loadClosing;' `
  ($clickHandlers + '  $("loadClosingBtn").onclick=loadClosing;') `
  "acao Ajustar apontamentos"

# Aviso antes do envio: não bloqueia hora extra real.
$oldSubmitStart = @'
  $("submitClosingBtn").onclick=async()=>{
    const userId=isManager()?$("closingUser").value:me.id;
'@

$newSubmitStart = @'
  $("submitClosingBtn").onclick=async()=>{
    const userId=isManager()?$("closingUser").value:me.id;

    if(currentClosingDailyReview.excess_days.length){
      const confirmed=window.confirm(
        `CONFERÊNCIA ANTES DO FECHAMENTO\n\n`+
        `${currentClosingDailyReview.excess_days.length} dia${currentClosingDailyReview.excess_days.length===1?"":"s"} `+
        `possui${currentClosingDailyReview.excess_days.length===1?"":"em"} horas acima da jornada.\n`+
        `Excedente diário acumulado: +${fmt(currentClosingDailyReview.total_excess_hours)} h.\n\n`+
        `Se forem horas extras reais, você pode manter e enviar.\n`+
        `Se houver erro de apontamento, cancele e use "Ajustar apontamentos".\n\n`+
        `Deseja enviar mesmo assim?`
      );
      if(!confirmed)return;
    }
'@

$app = Replace-Once $app $oldSubmitStart $newSubmitStart "aviso antes de enviar fechamento"

# ==============================================================
# CSS
# ==============================================================

$css += @'

/* ==========================================================
   v2.19.21 — conferência do colaborador antes do fechamento
   ========================================================== */
.closing-daily-review{
  margin:14px 0;
  padding:14px;
  border:1px solid #d6e2dd;
  border-radius:12px;
  background:#f8fbfa;
}
.closing-daily-review-heading{
  display:flex;
  justify-content:space-between;
  gap:12px;
  align-items:flex-start;
  margin-bottom:10px;
}
.closing-daily-review-heading h3{
  margin:3px 0;
  color:#052630;
  font-size:15px;
}
.closing-daily-review-heading p{
  margin:0;
  color:#667085;
  font-size:12px;
}
.closing-daily-review-badge.success{
  background:#e8f5e2;
  border:1px solid #b7d8aa;
  color:#35691f;
}
.closing-daily-review-badge.danger{
  background:#fee4e2;
  border:1px solid #f1aaa3;
  color:#b42318;
}
.closing-daily-review-list{
  display:grid;
  gap:8px;
}
.closing-daily-review-row{
  display:grid;
  grid-template-columns:minmax(135px,1.1fr) repeat(4,minmax(90px,.7fr)) auto;
  align-items:center;
  gap:9px;
  padding:10px 11px;
  border:1px solid #e0e8e4;
  border-radius:10px;
  background:#fff;
}
.closing-daily-review-row>div>span{
  display:block;
  color:#667085;
  font-size:10px;
}
.closing-daily-review-row>div>strong{
  display:block;
  margin-top:3px;
  color:#052630;
  font-size:13px;
}
.closing-daily-review-date strong{
  font-size:14px!important;
}
.closing-daily-review-date span{
  margin-top:2px;
}
.closing-daily-review-excess strong{
  color:#b42318!important;
}
.closing-daily-review-actions{
  text-align:right;
}
.closing-daily-review-empty{
  padding:12px;
  border:1px solid #c9dfbf;
  border-radius:9px;
  background:#f7fcf5;
}
.closing-daily-review-empty strong,
.closing-daily-review-empty span{
  display:block;
}
.closing-daily-review-empty strong{
  color:#35691f;
}
.closing-daily-review-empty span{
  margin-top:2px;
  color:#667085;
  font-size:11px;
}

@media(max-width:1000px){
  .closing-daily-review-row{
    grid-template-columns:1fr 1fr 1fr;
  }
  .closing-daily-review-actions{
    text-align:left;
  }
}
@media(max-width:650px){
  .closing-daily-review-heading{
    flex-direction:column;
  }
  .closing-daily-review-row{
    grid-template-columns:1fr 1fr;
  }
  .closing-daily-review-date,
  .closing-daily-review-actions{
    grid-column:1/-1;
  }
}
'@

# ==============================================================
# VERSAO / CACHE
# ==============================================================

$index = Replace-Once $index 'manifest.webmanifest?v=2.19.20' 'manifest.webmanifest?v=2.19.21' "manifest 2.19.21"
$index = Replace-Once $index 'style-v2.19.20.css?build=2210' 'style-v2.19.21.css?build=2211' "css 2211"
$index = Replace-Once $index 'const BUILD = "2.19.20";' 'const BUILD = "2.19.21";' "BUILD 2.19.21"
$index = Replace-Once $index 'const ASSET_BUILD = "2210";' 'const ASSET_BUILD = "2211";' "ASSET_BUILD 2211"
$index = Replace-Once $index 'app-v2.19.20.js?build=2210' 'app-v2.19.21.js?build=2211' "app 2211"
$index = Replace-Once $index 'navigator.serviceWorker.register("./sw.js?v=2.19.20"' 'navigator.serviceWorker.register("./sw.js?v=2.19.21"' "sw 2.19.21"

$sw = Replace-Once $sw 'const CACHE = "aponta-horas-v2.19.20-prevalidacao-importacao";' 'const CACHE = "aponta-horas-v2.19.21-conferencia-pre-fechamento";' "cache 2.19.21"
$sw = Replace-Once $sw '"./app-v2.19.20.js?build=2210",' '"./app-v2.19.21.js?build=2211",' "app cache"
$sw = Replace-Once $sw '"./style-v2.19.20.css?build=2210",' '"./style-v2.19.21.css?build=2211",' "css cache"
$sw = Replace-Once $sw '"./manifest.webmanifest?v=2.19.20",' '"./manifest.webmanifest?v=2.19.21",' "manifest cache"

# ==============================================================
# VALIDACOES FINAIS
# ==============================================================

$Checks = @(
  @{Name="painel no HTML"; Ok=$index.Contains('id="closingDailyReview"')},
  @{Name="funcao buildClosingDailyReview"; Ok=$app.Contains("function buildClosingDailyReview(")},
  @{Name="botao Ajustar apontamentos"; Ok=$app.Contains("data-closing-adjust-date")},
  @{Name="alerta pre envio"; Ok=$app.Contains("CONFERÊNCIA ANTES DO FECHAMENTO")},
  @{Name="reuso da pagina Apontamentos"; Ok=$app.Contains("openClosingDayForAdjustment(")},
  @{Name="versao 2.19.21"; Ok=$index.Contains('const BUILD = "2.19.21";')}
)

foreach($check in $Checks){
  if(-not $check.Ok){
    throw ("Validacao final falhou: " + $check.Name)
  }
  Write-Host ("VALIDADO - " + $check.Name) -ForegroundColor Green
}

$outDir = Join-Path $RepoDir "REVISAO_PRONTA_PARA_SUBIR_v2.19.21"
if(Test-Path $outDir){
  Remove-Item -Recurse -Force $outDir
}
New-Item -ItemType Directory -Path $outDir | Out-Null

[System.IO.File]::WriteAllText((Join-Path $outDir "index.html"),$index,$utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $outDir "app-v2.19.21.js"),$app,$utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $outDir "style-v2.19.21.css"),$css,$utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $outDir "sw.js"),$sw,$utf8NoBom)

$notes = @"
APONTA HORAS v2.19.21 — CONFERENCIA ANTES DO FECHAMENTO

HOJE (v2.19.20)
- Colaborador consegue editar em Apontamentos se status for Rascunho ou Devolvido.
- Fechamento do mes nao mostra dias excedentes antes do envio.

NESTA REVISAO
- Fechamento do mes mostra os dias com jornada excedida.
- Mostra data, planejado, apontado, excedente e quantidade de lancamentos.
- Colaborador clica Ajustar apontamentos.
- Sistema abre Apontamentos filtrado exatamente no dia.
- Colaborador edita normalmente seus lancamentos Rascunho/Devolvido.
- Antes de enviar, se ainda houver excedentes, aparece confirmacao.
- Hora extra real NAO bloqueia envio.
- Depois de Enviado/Aprovado o ajuste fica bloqueado conforme regra atual.
- Nao exige SQL novo.

ARQUIVOS PARA SUBIR
- index.html
- app-v2.19.21.js
- style-v2.19.21.css
- sw.js
"@

[System.IO.File]::WriteAllText((Join-Path $outDir "LEIA-ME.txt"),$notes,$utf8NoBom)

Write-Host ""
Write-Host "==============================================================" -ForegroundColor Green
Write-Host " REVISAO GERADA COM SUCESSO - v2.19.21" -ForegroundColor Green
Write-Host "==============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Pasta pronta:" -ForegroundColor Cyan
Write-Host $outDir -ForegroundColor Yellow
Write-Host ""
Read-Host "Pressione ENTER para finalizar"
