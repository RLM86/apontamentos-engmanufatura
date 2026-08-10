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
  Write-Host "PASTA DO PROJETO NAO LOCALIZADA AUTOMATICAMENTE." -ForegroundColor Yellow
  Write-Host "Cole o caminho da raiz do projeto que contem:" -ForegroundColor White
  $Required | ForEach-Object { Write-Host " - $_" -ForegroundColor Cyan }
  Write-Host ""
  $typed = Read-Host "CAMINHO DA PASTA DO PROJETO"
  if ($typed) {
    $typed = $typed.Trim().Trim('"')
  }

  if (Test-ApontaFolder $typed) {
    $RepoDir = (Resolve-Path $typed).Path
  } else {
    Write-Host "Pasta invalida. Tente novamente." -ForegroundColor Red
  }
}

Write-Host ""
Write-Host "Projeto localizado em:" -ForegroundColor Green
Write-Host $RepoDir -ForegroundColor Cyan
Write-Host ""

function Replace-Required {
  param(
    [string]$Text,
    [string]$Old,
    [string]$New,
    [string]$Label
  )

  # Normaliza CRLF/LF para evitar falha de comparacao no Windows.
  $TextNorm = $Text.Replace("`r`n", "`n")
  $OldNorm  = $Old.Replace("`r`n", "`n")
  $NewNorm  = $New.Replace("`r`n", "`n")

  $Count = [regex]::Matches(
    $TextNorm,
    [regex]::Escape($OldNorm)
  ).Count

  if ($Count -eq 0) {
    throw "Trecho obrigatorio nao encontrado: $Label. A versao local pode estar diferente da v2.19.20 publicada."
  }

  if ($Count -gt 1) {
    throw "Trecho encontrado $Count vezes: $Label. Processo interrompido para evitar alterar local errado."
  }

  Write-Host ("OK - " + $Label) -ForegroundColor DarkGreen
  return $TextNorm.Replace($OldNorm, $NewNorm)
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$indexPath = Join-Path $RepoDir "index.html"
$appPath   = Join-Path $RepoDir "app-v2.19.20.js"
$cssPath   = Join-Path $RepoDir "style-v2.19.20.css"
$swPath    = Join-Path $RepoDir "sw.js"

$index = [System.IO.File]::ReadAllText($indexPath)
$app   = [System.IO.File]::ReadAllText($appPath)
$css   = [System.IO.File]::ReadAllText($cssPath)
$sw    = [System.IO.File]::ReadAllText($swPath)

Write-Host "Validando versao local..." -ForegroundColor Cyan

if (-not $index.Contains('const BUILD = "2.19.20";')) {
  throw "index.html nao esta na versao 2.19.20 esperada."
}
if (-not $index.Contains('app-v2.19.20.js?build=2210')) {
  throw "index.html nao referencia app-v2.19.20.js build 2210."
}
if (-not $app.Contains('async function renderClosingHistory()')) {
  throw "app-v2.19.20.js nao contem renderClosingHistory()."
}
if (-not $app.Contains('const conference=closingConference(balance);')) {
  throw "app-v2.19.20.js nao contem o calculo de conferencia esperado."
}

Write-Host "OK - versao v2.19.20 confirmada." -ForegroundColor Green
Write-Host ""

# -------------------------------------------------------------------
# JAVASCRIPT — conferencia diaria e ajuste de excedentes
# -------------------------------------------------------------------

$closingBalanceMarker = @'
  function closingBalance(pointedHours,plannedHours){
'@

$dailyFunctions = @'
  /* APONTA P3 v2.19.21 — conferencia diaria dos fechamentos */
  function closingDayPlan(userId,date,approvedAbsences=[]){
    const cursor=new Date(`${date}T12:00:00Z`);
    const dayOfWeek=cursor.getUTCDay();
    const dailyHours=profileDailyHours(userId);
    const holiday=holidays.find(
      row=>String(row.holiday_date||"").slice(0,10)===date
    )||null;
    const absence=approvedAbsences.find(row=>
      row.user_id===userId&&
      row.start_date<=date&&
      row.end_date>=date
    )||null;

    if(dayOfWeek===0){
      return {planned_hours:0,day_type:"Domingo",reason:"Fim de semana"};
    }
    if(dayOfWeek===6){
      return {planned_hours:0,day_type:"Sábado",reason:"Fim de semana"};
    }
    if(holiday){
      return {
        planned_hours:0,
        day_type:"Feriado",
        reason:holiday.name||"Feriado cadastrado"
      };
    }
    if(absence){
      return {
        planned_hours:0,
        day_type:"Ausência aprovada",
        reason:absenceTypeLabel(absence.absence_type)
      };
    }

    return {
      planned_hours:dailyHours,
      day_type:"Dia útil",
      reason:`Jornada prevista de ${fmt(dailyHours)} h`
    };
  }

  function buildClosingDailyBreakdown(
    userId,
    monthRef,
    monthEntries=[],
    approvedAbsences=[]
  ){
    const month=String(monthRef||"").slice(0,7);
    const start=firstDay(month);
    const end=lastDay(month);
    const entriesByDate=new Map();

    monthEntries.forEach(entry=>{
      const date=String(entry.entry_date||"").slice(0,10);
      if(!date)return;
      if(!entriesByDate.has(date))entriesByDate.set(date,[]);
      entriesByDate.get(date).push(entry);
    });

    const rows=[];
    const cursor=new Date(`${start}T12:00:00Z`);
    const finalDate=new Date(`${end}T12:00:00Z`);

    while(cursor<=finalDate){
      const date=cursor.toISOString().slice(0,10);
      const dayEntries=entriesByDate.get(date)||[];
      const pointedHours=dayEntries.reduce(
        (sum,entry)=>sum+Number(entry.hours||0),
        0
      );
      const plan=closingDayPlan(
        userId,
        date,
        approvedAbsences
      );
      const difference=
        Number(pointedHours||0)-
        Number(plan.planned_hours||0);

      if(pointedHours>0||plan.planned_hours>0){
        rows.push({
          date,
          entries:dayEntries,
          pointed_hours:pointedHours,
          planned_hours:Number(plan.planned_hours||0),
          difference_hours:difference,
          excess_hours:difference>0.009?difference:0,
          missing_hours:difference<-0.009?Math.abs(difference):0,
          day_type:plan.day_type,
          reason:plan.reason
        });
      }

      cursor.setUTCDate(cursor.getUTCDate()+1);
    }

    return rows;
  }

  function closingExcessSection(row){
    const excessDays=row.excess_days||[];
    const totalExcess=Number(row.daily_excess_hours||0);

    if(!excessDays.length){
      return `
        <section class="closing-daily-audit closing-daily-audit-ok">
          <div class="closing-daily-audit-heading">
            <div>
              <span>Conferência diária</span>
              <strong>Nenhum dia com jornada excedida</strong>
            </div>
            <span class="badge closing-daily-badge-ok">OK</span>
          </div>
        </section>
      `;
    }

    const canAdjust=
      isManager()&&
      ["enviado","devolvido"].includes(row.status);

    const approvedMessage=
      row.status==="aprovado"
        ?`<p class="closing-daily-lock-note">
            Período aprovado. Devolva o fechamento antes de alterar horas.
          </p>`
        :"";

    return `
      <section class="closing-daily-audit">
        <div class="closing-daily-audit-heading">
          <div>
            <span>Conferência diária</span>
            <strong>
              ${excessDays.length} dia${excessDays.length===1?"":"s"} com jornada excedida
            </strong>
            <small>
              Excedente diário acumulado: +${fmt(totalExcess)} h.
              O saldo mensal pode ser diferente porque dias abaixo da jornada compensam parte do total.
            </small>
          </div>
          <span class="badge closing-daily-badge-excess">
            +${fmt(totalExcess)} h
          </span>
        </div>

        ${approvedMessage}

        <div class="closing-excess-days-list">
          ${excessDays.map(day=>`
            <article class="closing-excess-day-card">
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
                        class="btn secondary small"
                        type="button"
                        data-adjust-closing-day="${row.id}"
                        data-adjust-closing-date="${day.date}">
                        Ajustar horas
                      </button>`
                    :isManager()
                      ?`<button
                          class="btn secondary small"
                          type="button"
                          disabled
                          title="Devolva o período antes de ajustar">
                          Ajuste bloqueado
                        </button>`
                      :""
                }
              </div>
            </article>
          `).join("")}
        </div>
      </section>
    `;
  }

  function ensureClosingDayAdjustmentDialog(){
    let dialog=$("closingDayAdjustmentDialog");
    if(dialog)return dialog;

    dialog=document.createElement("dialog");
    dialog.id="closingDayAdjustmentDialog";
    dialog.className="closing-day-adjust-dialog";
    dialog.innerHTML=`
      <form method="dialog" class="dialog-card closing-day-adjust-card">
        <div class="closing-day-adjust-heading">
          <div>
            <span class="eyebrow">Ajuste de jornada</span>
            <h3 id="closingDayAdjustTitle">Ajustar horas do dia</h3>
            <p id="closingDayAdjustSubtitle"></p>
          </div>
          <button
            class="btn secondary small"
            value="cancel"
            type="submit"
            aria-label="Fechar">
            Fechar
          </button>
        </div>

        <div class="closing-day-adjust-summary">
          <article>
            <span>Planejado</span>
            <strong id="closingDayAdjustPlanned">0,00 h</strong>
          </article>
          <article>
            <span>Atual</span>
            <strong id="closingDayAdjustCurrent">0,00 h</strong>
          </article>
          <article>
            <span>Novo total</span>
            <strong id="closingDayAdjustNewTotal">0,00 h</strong>
          </article>
          <article>
            <span>Novo saldo</span>
            <strong id="closingDayAdjustNewBalance">0,00 h</strong>
          </article>
        </div>

        <p class="closing-day-adjust-help">
          Ajuste somente as horas necessárias. Projeto, atividade e observação permanecem inalterados.
          Para excluir um lançamento ou alterar outros campos, abra o dia em Apontamentos.
        </p>

        <div class="table-wrap closing-day-adjust-table-wrap">
          <table class="closing-day-adjust-table">
            <thead>
              <tr>
                <th>Projeto</th>
                <th>Atividade</th>
                <th>Status</th>
                <th>Horas</th>
              </tr>
            </thead>
            <tbody id="closingDayAdjustRows"></tbody>
          </table>
        </div>

        <div class="closing-day-adjust-actions">
          <button
            id="closingDayOpenEntriesBtn"
            class="btn secondary"
            type="button">
            Abrir dia em Apontamentos
          </button>
          <button
            id="closingDaySaveAdjustBtn"
            class="btn primary"
            type="button">
            Salvar ajustes
          </button>
        </div>
      </form>
    `;

    document.body.appendChild(dialog);

    dialog.addEventListener("input",event=>{
      if(event.target.matches("[data-closing-day-hours]")){
        updateClosingDayAdjustmentPreview();
      }
    });

    $("closingDaySaveAdjustBtn").onclick=saveClosingDayAdjustment;
    $("closingDayOpenEntriesBtn").onclick=openAdjustedDayInEntries;

    return dialog;
  }

  function currentClosingDayAdjustment(){
    const dialog=$("closingDayAdjustmentDialog");
    if(!dialog)return null;

    const closingId=dialog.dataset.closingId||"";
    const date=dialog.dataset.date||"";
    const row=closingHistoryRows.find(item=>item.id===closingId);
    const day=row?.daily_breakdown?.find(item=>item.date===date);

    if(!row||!day)return null;
    return {dialog,row,day};
  }

  function updateClosingDayAdjustmentPreview(){
    const context=currentClosingDayAdjustment();
    if(!context)return;

    const {day}=context;
    const inputs=[
      ...$("closingDayAdjustRows").querySelectorAll(
        "[data-closing-day-hours]"
      )
    ];
    const newTotal=inputs.reduce(
      (sum,input)=>sum+Number(input.value||0),
      0
    );
    const balance=
      newTotal-
      Number(day.planned_hours||0);

    $("closingDayAdjustNewTotal").textContent=
      `${fmt(newTotal)} h`;
    $("closingDayAdjustNewBalance").textContent=
      `${signedHours(balance)} h`;

    $("closingDayAdjustNewBalance").className=
      balance>0.009
        ?"closing-balance-excess"
        :balance<-0.009
          ?"closing-balance-missing"
          :"closing-balance-complete";
  }

  function openClosingDayAdjustment(closingId,date){
    const row=closingHistoryRows.find(
      item=>item.id===closingId
    );
    if(!row)return;

    if(!isManager()){
      toast("Somente Gestor ou Administrador pode ajustar horas nesta tela.",true);
      return;
    }

    if(!["enviado","devolvido"].includes(row.status)){
      toast(
        "Este fechamento está aprovado. Devolva o período antes de ajustar os apontamentos.",
        true
      );
      return;
    }

    const day=row.daily_breakdown?.find(
      item=>item.date===date
    );
    if(!day)return;

    if(!day.entries.length){
      toast("Nenhum lançamento encontrado neste dia.",true);
      return;
    }

    const dialog=ensureClosingDayAdjustmentDialog();
    dialog.dataset.closingId=row.id;
    dialog.dataset.date=day.date;

    $("closingDayAdjustTitle").textContent=
      `${profileName(row.user_id)} — ${dateBR(day.date)}`;
    $("closingDayAdjustSubtitle").textContent=
      `${day.day_type} · ${day.reason}`;

    $("closingDayAdjustPlanned").textContent=
      `${fmt(day.planned_hours)} h`;
    $("closingDayAdjustCurrent").textContent=
      `${fmt(day.pointed_hours)} h`;

    $("closingDayAdjustRows").innerHTML=
      [...day.entries]
        .sort((a,b)=>
          String(a.created_at||"").localeCompare(
            String(b.created_at||"")
          )
        )
        .map(entry=>`
          <tr>
            <td>${esc(projectName(entry.project_id))}</td>
            <td>${esc(activityName(entry.activity_id))}</td>
            <td>
              <span class="badge status-${esc(entry.status)}">
                ${esc(statusLabel(entry.status))}
              </span>
            </td>
            <td>
              <input
                type="number"
                min="0.25"
                max="24"
                step="0.25"
                value="${Number(entry.hours||0)}"
                data-closing-day-hours="${entry.id}">
            </td>
          </tr>
        `).join("");

    updateClosingDayAdjustmentPreview();
    dialog.showModal();
  }

  async function saveClosingDayAdjustment(){
    const context=currentClosingDayAdjustment();
    if(!context)return;

    const {dialog,row,day}=context;

    if(!isManager()||!["enviado","devolvido"].includes(row.status)){
      toast("Este período não está liberado para ajuste.",true);
      return;
    }

    const inputs=[
      ...$("closingDayAdjustRows").querySelectorAll(
        "[data-closing-day-hours]"
      )
    ];

    const updates=[];
    for(const input of inputs){
      const hours=Number(input.value);
      if(!Number.isFinite(hours)||hours<0.25||hours>24){
        input.focus();
        toast(
          "Informe horas válidas entre 0,25 e 24,00.",
          true
        );
        return;
      }

      const original=day.entries.find(
        entry=>entry.id===input.dataset.closingDayHours
      );
      if(!original)continue;

      if(Math.abs(hours-Number(original.hours||0))>0.001){
        updates.push({
          id:original.id,
          hours
        });
      }
    }

    if(!updates.length){
      toast("Nenhuma hora foi alterada.",true);
      return;
    }

    const newTotal=inputs.reduce(
      (sum,input)=>sum+Number(input.value||0),
      0
    );
    const newBalance=
      newTotal-
      Number(day.planned_hours||0);

    const confirmed=window.confirm(
      `SALVAR AJUSTE DO DIA ${dateBR(day.date)}?\n\n`+
      `Planejado: ${fmt(day.planned_hours)} h\n`+
      `Antes: ${fmt(day.pointed_hours)} h\n`+
      `Depois: ${fmt(newTotal)} h\n`+
      `Saldo após ajuste: ${signedHours(newBalance)} h\n\n`+
      `${updates.length} lançamento${updates.length===1?"":"s"} será${updates.length===1?"":"ão"} alterado${updates.length===1?"":"s"}.`
    );
    if(!confirmed)return;

    showLoading(true);
    try{
      for(const update of updates){
        const {error}=await sb
          .from("time_entries")
          .update({hours:update.hours})
          .eq("id",update.id);

        if(error)throw error;
      }

      dialog.close();

      await Promise.all([
        renderClosingHistory(),
        loadClosing(),
        renderEntries(),
        renderDashboard()
      ]);

      toast(
        `${updates.length} lançamento${updates.length===1?"":"s"} ajustado${updates.length===1?"":"s"}. `+
        `Novo total do dia: ${fmt(newTotal)} h.`
      );
    }catch(error){
      handleError(
        error,
        "Não foi possível ajustar as horas. Se o período estiver aprovado, devolva-o antes da correção."
      );
    }finally{
      showLoading(false);
    }
  }

  async function openAdjustedDayInEntries(){
    const context=currentClosingDayAdjustment();
    if(!context)return;

    const {dialog,row,day}=context;
    dialog.close();

    if(isManager()){
      $("filterEntryUser").value=row.user_id;
    }
    $("filterEntryStart").value=day.date;
    $("filterEntryEnd").value=day.date;

    const navButton=document.querySelector(
      '#mainNav button[data-page="entries"]'
    );
    if(navButton){
      navButton.click();
      await renderEntries();
      $("entriesTable")?.scrollIntoView({
        behavior:"smooth",
        block:"start"
      });
    }
  }

'@

$app = Replace-Required `
  $app `
  $closingBalanceMarker `
  ($dailyFunctions + $closingBalanceMarker) `
  "funcoes de conferencia diaria"

$conferenceSnippet = @'
        const conference=closingConference(balance);
        return {
'@

$conferenceReplacement = @'
        const conference=closingConference(balance);
        const monthEntries=entries.filter(entry=>
          entry.user_id===closing.user_id&&
          closingHistoryKey(
            entry.user_id,
            entry.entry_date
          )===closingHistoryKey(
            closing.user_id,
            closing.month_ref
          )
        );
        const dailyBreakdown=buildClosingDailyBreakdown(
          closing.user_id,
          closing.month_ref,
          monthEntries,
          approvedAbsences
        );
        const excessDays=dailyBreakdown.filter(
          day=>day.excess_hours>0.009
        );
        const dailyExcessHours=excessDays.reduce(
          (sum,day)=>sum+Number(day.excess_hours||0),
          0
        );
        return {
'@

$app = Replace-Required `
  $app `
  $conferenceSnippet `
  $conferenceReplacement `
  "calculo diario no fechamento"

$plannedDetailSnippet = @'
          planned_detail:plannedHoursDetail(planned),
          project_ids:projectIds,
'@

$plannedDetailReplacement = @'
          planned_detail:plannedHoursDetail(planned),
          daily_breakdown:dailyBreakdown,
          excess_days:excessDays,
          daily_excess_hours:dailyExcessHours,
          project_ids:projectIds,
'@

$app = Replace-Required `
  $app `
  $plannedDetailSnippet `
  $plannedDetailReplacement `
  "dados de excedentes por dia"

$selectorMarker = @'
        const selectorCell=isManager()
'@

$selectorReplacement = @'
        const excessSection=closingExcessSection(row);
        const selectorCell=isManager()
'@

$app = Replace-Required `
  $app `
  $selectorMarker `
  $selectorReplacement `
  "secao de excedentes no card"

$detailsActionsMarker = @'
                </div>
                <div class="closing-compact-details-actions">
'@

$detailsActionsReplacement = @'
                </div>
                ${excessSection}
                <div class="closing-compact-details-actions">
'@

$app = Replace-Required `
  $app `
  $detailsActionsMarker `
  $detailsActionsReplacement `
  "exibir conferencia diaria"

$clickMarker = @'
        return;
      }
      const button=event.target.closest("[data-open-closing]");
'@

$clickReplacement = @'
        return;
      }

      const adjustDayButton=event.target.closest(
        "[data-adjust-closing-day]"
      );
      if(adjustDayButton){
        openClosingDayAdjustment(
          adjustDayButton.dataset.adjustClosingDay,
          adjustDayButton.dataset.adjustClosingDate
        );
        return;
      }

      const button=event.target.closest("[data-open-closing]");
'@

$app = Replace-Required `
  $app `
  $clickMarker `
  $clickReplacement `
  "acao ajustar dia"

# -------------------------------------------------------------------
# CSS
# -------------------------------------------------------------------

$cssAppend = @'

/* ==========================================================
   v2.19.21 — dias excedentes e ajuste no fechamento
   ========================================================== */
.closing-daily-audit{
  margin-top:14px;
  padding:14px;
  border:1px solid #f1c7c3;
  border-left:5px solid #d92d20;
  border-radius:12px;
  background:#fffafa;
}
.closing-daily-audit-ok{
  border-color:#c7dfbd;
  border-left-color:#78ad3e;
  background:#f8fcf6;
}
.closing-daily-audit-heading{
  display:flex;
  justify-content:space-between;
  align-items:flex-start;
  gap:12px;
  margin-bottom:11px;
}
.closing-daily-audit-heading>div{
  min-width:0;
}
.closing-daily-audit-heading span{
  display:block;
  color:#667085;
  font-size:12px;
}
.closing-daily-audit-heading strong{
  display:block;
  margin-top:3px;
  color:#052630;
  font-size:15px;
}
.closing-daily-audit-heading small{
  display:block;
  max-width:850px;
  margin-top:4px;
  color:#667085;
  line-height:1.4;
}
.closing-daily-badge-excess{
  flex:0 0 auto;
  background:#fee4e2;
  color:#b42318;
  border:1px solid #f1aaa3;
  font-size:13px;
}
.closing-daily-badge-ok{
  background:#e8f5e2;
  color:#35691f;
  border:1px solid #b8d8aa;
}
.closing-daily-lock-note{
  margin:0 0 10px;
  padding:9px 11px;
  border-radius:8px;
  background:#fff4e5;
  color:#8a5100;
  font-size:12px;
  font-weight:700;
}
.closing-excess-days-list{
  display:grid;
  gap:8px;
}
.closing-excess-day-card{
  display:grid;
  grid-template-columns:minmax(170px,1.35fr) repeat(4,minmax(95px,.65fr)) auto;
  gap:9px;
  align-items:center;
  padding:10px 11px;
  border:1px solid #ead7d5;
  border-radius:10px;
  background:#fff;
}
.closing-excess-day-date strong,
.closing-excess-day-date span,
.closing-excess-day-date small,
.closing-excess-day-number span,
.closing-excess-day-number strong{
  display:block;
}
.closing-excess-day-date strong{
  color:#052630;
  font-size:14px;
}
.closing-excess-day-date span{
  margin-top:2px;
  color:#b42318;
  font-size:11px;
  font-weight:800;
}
.closing-excess-day-date small{
  margin-top:2px;
  color:#667085;
  font-size:10px;
}
.closing-excess-day-number span{
  color:#667085;
  font-size:10px;
}
.closing-excess-day-number strong{
  margin-top:3px;
  color:#052630;
  font-size:13px;
}
.closing-excess-day-value strong{
  color:#b42318;
}
.closing-excess-day-actions{
  text-align:right;
}
.closing-day-adjust-dialog{
  width:min(980px,94vw);
}
.closing-day-adjust-card{
  width:100%;
  max-height:88vh;
  overflow:auto;
}
.closing-day-adjust-heading{
  display:flex;
  align-items:flex-start;
  justify-content:space-between;
  gap:12px;
}
.closing-day-adjust-heading h3{
  margin:4px 0 3px;
  color:#052630;
}
.closing-day-adjust-heading p{
  margin:0;
  color:#667085;
}
.closing-day-adjust-summary{
  display:grid;
  grid-template-columns:repeat(4,1fr);
  gap:8px;
}
.closing-day-adjust-summary article{
  padding:10px 12px;
  border:1px solid #dbe5e1;
  border-radius:9px;
  background:#f7faf8;
}
.closing-day-adjust-summary span{
  display:block;
  color:#667085;
  font-size:11px;
}
.closing-day-adjust-summary strong{
  display:block;
  margin-top:3px;
  color:#052630;
  font-size:17px;
}
.closing-day-adjust-help{
  margin:0;
  padding:9px 11px;
  border-radius:8px;
  background:#eef5f2;
  color:#475467;
  font-size:12px;
  line-height:1.4;
}
.closing-day-adjust-table-wrap{
  max-height:360px;
}
.closing-day-adjust-table input{
  min-width:92px;
}
.closing-day-adjust-actions{
  display:flex;
  justify-content:flex-end;
  gap:8px;
  flex-wrap:wrap;
}

@media(max-width:1100px){
  .closing-excess-day-card{
    grid-template-columns:1.3fr repeat(2,.7fr);
  }
  .closing-excess-day-actions{
    text-align:left;
  }
}
@media(max-width:700px){
  .closing-daily-audit-heading{
    flex-direction:column;
  }
  .closing-excess-day-card{
    grid-template-columns:1fr 1fr;
  }
  .closing-excess-day-date,
  .closing-excess-day-actions{
    grid-column:1/-1;
  }
  .closing-day-adjust-summary{
    grid-template-columns:1fr 1fr;
  }
}
'@

if(-not $css.Contains("v2.19.21 — dias excedentes e ajuste no fechamento")){
  $css += $cssAppend
}

# -------------------------------------------------------------------
# INDEX E SERVICE WORKER — versao 2.19.21 / build 2211
# -------------------------------------------------------------------

$index = Replace-Required `
  $index `
  'manifest.webmanifest?v=2.19.20' `
  'manifest.webmanifest?v=2.19.21' `
  "manifest"

$index = Replace-Required `
  $index `
  'style-v2.19.20.css?build=2210' `
  'style-v2.19.21.css?build=2211' `
  "css"

$index = Replace-Required `
  $index `
  'const BUILD = "2.19.20";' `
  'const BUILD = "2.19.21";' `
  "build"

$index = Replace-Required `
  $index `
  'const ASSET_BUILD = "2210";' `
  'const ASSET_BUILD = "2211";' `
  "asset build"

$index = Replace-Required `
  $index `
  'app-v2.19.20.js?build=2210' `
  'app-v2.19.21.js?build=2211' `
  "app"

$index = Replace-Required `
  $index `
  'navigator.serviceWorker.register("./sw.js?v=2.19.20"' `
  'navigator.serviceWorker.register("./sw.js?v=2.19.21"' `
  "service worker"

$sw = Replace-Required `
  $sw `
  'const CACHE = "aponta-horas-v2.19.20-prevalidacao-importacao";' `
  'const CACHE = "aponta-horas-v2.19.21-excedentes-fechamento";' `
  "cache"

$sw = Replace-Required `
  $sw `
  '"./app-v2.19.20.js?build=2210",' `
  '"./app-v2.19.21.js?build=2211",' `
  "app cache"

$sw = Replace-Required `
  $sw `
  '"./style-v2.19.20.css?build=2210",' `
  '"./style-v2.19.21.css?build=2211",' `
  "css cache"

$sw = Replace-Required `
  $sw `
  '"./manifest.webmanifest?v=2.19.20",' `
  '"./manifest.webmanifest?v=2.19.21",' `
  "manifest cache"

# -------------------------------------------------------------------
# VALIDACAO FINAL ANTES DE ESCREVER OS ARQUIVOS
# -------------------------------------------------------------------

$Checks = @(
  @{ Label="funcao diaria"; Value=$app.Contains("function buildClosingDailyBreakdown(") },
  @{ Label="secao de excedentes"; Value=$app.Contains("function closingExcessSection(") },
  @{ Label="ajuste de horas"; Value=$app.Contains("function openClosingDayAdjustment(") },
  @{ Label="salvar ajuste"; Value=$app.Contains("async function saveClosingDayAdjustment(") },
  @{ Label="dados excess_days"; Value=$app.Contains("excess_days:excessDays") },
  @{ Label="botao ajustar"; Value=$app.Contains("data-adjust-closing-day") },
  @{ Label="app 2.19.21 no index"; Value=$index.Contains("app-v2.19.21.js?build=2211") },
  @{ Label="css 2.19.21 no index"; Value=$index.Contains("style-v2.19.21.css?build=2211") },
  @{ Label="cache 2.19.21"; Value=$sw.Contains("aponta-horas-v2.19.21-excedentes-fechamento") }
)

foreach($Check in $Checks){
  if(-not $Check.Value){
    throw ("Validacao final falhou: " + $Check.Label)
  }
}

Write-Host ""
Write-Host "Validacao final OK - todos os componentes v2.19.21 foram aplicados." -ForegroundColor Green
Write-Host ""

# -------------------------------------------------------------------
# GERAR PASTA PRONTA
# -------------------------------------------------------------------

$outDir = Join-Path $RepoDir "REVISAO_PRONTA_PARA_SUBIR_v2.19.21"
if(Test-Path $outDir){
  Remove-Item -Recurse -Force $outDir
}
New-Item -ItemType Directory -Path $outDir | Out-Null

[System.IO.File]::WriteAllText(
  (Join-Path $outDir "index.html"),
  $index,
  $utf8NoBom
)
[System.IO.File]::WriteAllText(
  (Join-Path $outDir "app-v2.19.21.js"),
  $app,
  $utf8NoBom
)
[System.IO.File]::WriteAllText(
  (Join-Path $outDir "style-v2.19.21.css"),
  $css,
  $utf8NoBom
)
[System.IO.File]::WriteAllText(
  (Join-Path $outDir "sw.js"),
  $sw,
  $utf8NoBom
)

$notes = @"
APONTA HORAS v2.19.21
FECHAMENTO - DIAS EXCEDENTES E AJUSTE

ALTERACOES
- Fechamentos enviados > Conferir mostra cada dia que excedeu a jornada.
- Exibe data, tipo do dia, planejado, apontado, excedente e quantidade de lancamentos.
- Mostra o excedente diario acumulado.
- Gestor/Administrador pode clicar em Ajustar horas.
- Abre uma janela com os apontamentos daquele dia.
- Permite alterar somente as horas diretamente nessa tela.
- Mostra o novo total e o novo saldo antes de salvar.
- Possui opcao Abrir dia em Apontamentos para ajustes completos.
- Fechamentos aprovados ficam bloqueados para ajuste direto.
- Nesses casos, o periodo deve ser devolvido antes.
- Nao exige SQL novo.

ARQUIVOS PARA SUBIR
- index.html
- app-v2.19.21.js
- style-v2.19.21.css
- sw.js
"@

[System.IO.File]::WriteAllText(
  (Join-Path $outDir "LEIA-ME.txt"),
  $notes,
  $utf8NoBom
)

Write-Host ""
Write-Host "==============================================================" -ForegroundColor Green
Write-Host " REVISAO GERADA COM SUCESSO - v2.19.21" -ForegroundColor Green
Write-Host "==============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Pasta pronta para subir:" -ForegroundColor Cyan
Write-Host $outDir -ForegroundColor Yellow
Write-Host ""
Write-Host "Arquivos:" -ForegroundColor White
Write-Host " - index.html"
Write-Host " - app-v2.19.21.js"
Write-Host " - style-v2.19.21.css"
Write-Host " - sw.js"
Write-Host ""
Read-Host "Pressione ENTER para finalizar"
