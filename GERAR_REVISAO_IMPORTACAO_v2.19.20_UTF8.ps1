$ErrorActionPreference = "Stop"

if ($env:APONT_PATCH_DIR) {
  $BaseDir = $env:APONT_PATCH_DIR.TrimEnd("\")
} else {
  $BaseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

$required = @(
  "index.html",
  "app-v2.19.5.js",
  "style-v2.19.5.css",
  "sw.js"
)

function Test-ApontaFolder {
  param([string]$Folder)
  if (-not $Folder) { return $false }
  if (-not (Test-Path $Folder -PathType Container)) { return $false }

  foreach ($file in $required) {
    if (-not (Test-Path (Join-Path $Folder $file) -PathType Leaf)) {
      return $false
    }
  }
  return $true
}

$RepoDir = $null

# 1) Tenta a própria pasta do pacote.
if (Test-ApontaFolder $BaseDir) {
  $RepoDir = $BaseDir
}

# 2) Tenta a pasta pai (caso o ZIP tenha sido extraído dentro do projeto).
if (-not $RepoDir) {
  $ParentDir = Split-Path -Parent $BaseDir
  if (Test-ApontaFolder $ParentDir) {
    $RepoDir = $ParentDir
  }
}

# 3) Se não localizar, pede o caminho ao usuário.
while (-not $RepoDir) {
  Write-Host ""
  Write-Host "==============================================================" -ForegroundColor Yellow
  Write-Host " PASTA DO PROJETO APONTA P3 NAO LOCALIZADA AUTOMATICAMENTE" -ForegroundColor Yellow
  Write-Host "==============================================================" -ForegroundColor Yellow
  Write-Host ""
  Write-Host "Cole abaixo a pasta onde estao estes arquivos:" -ForegroundColor White
  $required | ForEach-Object { Write-Host " - $_" -ForegroundColor Cyan }
  Write-Host ""
  Write-Host "Exemplo: C:\Users\SeuNome\Downloads\apontamentos-engmanufatura" -ForegroundColor Gray
  Write-Host ""

  $typed = Read-Host "CAMINHO DA PASTA DO PROJETO"
  if ($typed) {
    $typed = $typed.Trim().Trim('"')
  }

  if (Test-ApontaFolder $typed) {
    $RepoDir = (Resolve-Path $typed).Path
  } else {
    Write-Host ""
    Write-Host "Essa pasta nao contem todos os arquivos esperados." -ForegroundColor Red
    Write-Host "Tente novamente ou pressione CTRL+C para cancelar." -ForegroundColor Yellow
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
  if (-not $Text.Contains($Old)) {
    throw "Trecho obrigatorio nao encontrado em: $Label. O arquivo pode ter mudado de versao."
  }
  return $Text.Replace($Old, $New)
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$indexPath = Join-Path $RepoDir "index.html"
$appPath   = Join-Path $RepoDir "app-v2.19.5.js"
$cssPath   = Join-Path $RepoDir "style-v2.19.5.css"
$swPath    = Join-Path $RepoDir "sw.js"

$index = [System.IO.File]::ReadAllText($indexPath)
$app   = [System.IO.File]::ReadAllText($appPath)
$css   = [System.IO.File]::ReadAllText($cssPath)
$sw    = [System.IO.File]::ReadAllText($swPath)

# ----------------------------------------------------------------------
# 1. JavaScript: pre-validacao da importacao + match projeto por codigo/nome
# ----------------------------------------------------------------------

$jsInsertMarker = @'
  function renderExcelAnalysis() {
'@

$jsFunctions = @'
  function buildImportProjectLookup() {
    const lookup = new Map();
    projects.forEach(project => {
      const nameKey = normalizeImportText(project.name);
      const codeKey = normalizeImportText(project.code);
      if (nameKey && !lookup.has(nameKey)) lookup.set(nameKey, project);
      if (codeKey && !lookup.has(codeKey)) lookup.set(codeKey, project);
    });
    return lookup;
  }

  function activityHasImportAdminArea(activityId) {
    return activityAreaLinks.some(link =>
      String(link.activity_id || "") === String(activityId || "") &&
      String(link.area_code || "").trim().toUpperCase() === "ADM"
    );
  }

  function ensureExcelPreflightUi() {
    let container = $("importPreflight");
    if (container) return container;

    const warnings = $("importWarnings");
    if (!warnings) return null;

    container = document.createElement("section");
    container.id = "importPreflight";
    container.className = "import-preflight";
    container.hidden = true;
    container.innerHTML = `
      <div class="import-preflight-heading">
        <div>
          <h3>Prévia do que será feito na importação</h3>
          <p>Comparação da planilha com os cadastros atuais antes de gravar qualquer registro.</p>
        </div>
        <span id="importPreflightBadge" class="badge">Aguardando análise</span>
      </div>

      <div class="import-preflight-metrics">
        <article>
          <span>Projetos existentes</span>
          <strong id="importPreflightProjectsExisting">0</strong>
        </article>
        <article>
          <span>Projetos novos</span>
          <strong id="importPreflightProjectsNew">0</strong>
        </article>
        <article>
          <span>Atividades existentes</span>
          <strong id="importPreflightActivitiesExisting">0</strong>
        </article>
        <article>
          <span>Atividades novas</span>
          <strong id="importPreflightActivitiesNew">0</strong>
        </article>
        <article>
          <span>Ajustes de área ADM</span>
          <strong id="importPreflightAdmLinks">0</strong>
        </article>
        <article>
          <span>Colaboradores vinculados</span>
          <strong id="importPreflightMappings">0</strong>
        </article>
      </div>

      <div id="importPreflightMode" class="import-preflight-mode"></div>

      <div class="import-preflight-details">
        <details open>
          <summary id="importPreflightProjectsSummary">Projetos</summary>
          <div id="importPreflightProjectsList" class="import-preflight-list"></div>
        </details>
        <details>
          <summary id="importPreflightActivitiesSummary">Atividades</summary>
          <div id="importPreflightActivitiesList" class="import-preflight-list"></div>
        </details>
      </div>

      <div id="importPreflightStatus" class="import-preflight-status"></div>
    `;

    warnings.insertAdjacentElement("afterend", container);

    ["importCatalogs", "importEntries", "importHolidays", "importVacations"].forEach(id => {
      const field = $(id);
      if (!field || field.dataset.preflightBound === "1") return;
      field.dataset.preflightBound = "1";
      field.addEventListener("change", () => {
        if (excelImportAnalysis) renderExcelPreflight();
      });
    });

    return container;
  }

  function buildExcelPreflight() {
    const analysis = excelImportAnalysis;
    if (!analysis) {
      return {
        blockers: ["Nenhuma planilha foi analisada."],
        warnings: [],
        projectRows: [],
        activityRows: [],
        newProjects: [],
        newActivities: [],
        activitiesWithoutAdm: [],
        mappedCount: 0,
        unmappedCount: 0,
        catalogsEnabled: false,
        entriesEnabled: false
      };
    }

    const catalogsEnabled = $("importCatalogs").checked;
    const entriesEnabled = $("importEntries").checked;
    const projectLookup = buildImportProjectLookup();
    const activityLookup = new Map(
      activities.map(activity => [normalizeImportText(activity.name), activity])
    );

    const projectRows = analysis.projects.map(item => {
      const key = normalizeImportText(item.name);
      const existing = projectLookup.get(key) || null;
      const matchedByCode = Boolean(
        existing &&
        normalizeImportText(existing.code) &&
        normalizeImportText(existing.code) === key
      );

      let state = "existing";
      let action = "Usar cadastro existente";
      if (!existing) {
        state = catalogsEnabled ? "new" : "error";
        action = catalogsEnabled
          ? "Será cadastrado antes dos apontamentos"
          : "Não existe e NÃO será cadastrado";
      } else if (existing.active === false) {
        state = "warning";
        action = "Cadastro encontrado, porém está inativo";
      }

      return {
        source: item.name,
        existing,
        matchedBy: existing ? (matchedByCode ? "código" : "nome") : "",
        state,
        action
      };
    });

    const activityRows = analysis.activities.map(item => {
      const key = normalizeImportText(item.name);
      const existing = activityLookup.get(key) || null;
      const hasAdm = existing ? activityHasImportAdminArea(existing.id) : false;

      let state = "existing";
      let action = catalogsEnabled
        ? "Usar/atualizar cadastro existente"
        : "Usar cadastro existente";

      if (!existing) {
        state = catalogsEnabled ? "new" : "error";
        action = catalogsEnabled
          ? "Será cadastrada e vinculada ao ADM"
          : "Não existe e NÃO será cadastrada";
      } else if (entriesEnabled && !hasAdm) {
        state = catalogsEnabled ? "adjust" : "error";
        action = catalogsEnabled
          ? "Será incluído vínculo com ADM antes dos apontamentos"
          : "Sem vínculo ADM — bloqueia apontamentos históricos";
      } else if (existing.active === false) {
        state = "warning";
        action = "Cadastro encontrado, porém está inativo";
      }

      return {
        source: item.name,
        existing,
        hasAdm,
        state,
        action
      };
    });

    const newProjects = projectRows.filter(row => !row.existing);
    const newActivities = activityRows.filter(row => !row.existing);
    const activitiesWithoutAdm = activityRows.filter(
      row => row.existing && entriesEnabled && !row.hasAdm
    );

    const mappingSelects = [...document.querySelectorAll(".import-user-map")];
    const mappedCount = mappingSelects.filter(select => Boolean(select.value)).length;
    const unmappedCount = Math.max(0, analysis.employeeSheets.length - mappedCount);

    const blockers = [];
    const warnings = [];

    const anyOptionSelected =
      catalogsEnabled ||
      entriesEnabled ||
      $("importHolidays").checked ||
      $("importVacations").checked;

    if (!anyOptionSelected) {
      blockers.push("Nenhum tipo de dado foi selecionado para importação.");
    }

    if (entriesEnabled && mappedCount === 0) {
      blockers.push("Nenhuma aba de colaborador está vinculada a um usuário.");
    }

    if (entriesEnabled && !catalogsEnabled) {
      if (newProjects.length) {
        blockers.push(
          `${newProjects.length} projeto(s) da planilha não existem no cadastro atual.`
        );
      }
      if (newActivities.length) {
        blockers.push(
          `${newActivities.length} atividade(s) da planilha não existem no cadastro atual.`
        );
      }
      if (activitiesWithoutAdm.length) {
        blockers.push(
          `${activitiesWithoutAdm.length} atividade(s) existente(s) não possuem vínculo com a área ADM exigida pela importação histórica.`
        );
      }
    }

    if (entriesEnabled && unmappedCount > 0) {
      warnings.push(
        `${unmappedCount} aba(s) estão sem usuário e serão ignoradas se permanecerem assim.`
      );
    }

    const inactiveProjects = projectRows.filter(
      row => row.existing && row.existing.active === false
    );
    const inactiveActivities = activityRows.filter(
      row => row.existing && row.existing.active === false
    );

    if (inactiveProjects.length) {
      warnings.push(`${inactiveProjects.length} projeto(s) encontrado(s) estão inativos.`);
    }
    if (inactiveActivities.length) {
      warnings.push(`${inactiveActivities.length} atividade(s) encontrada(s) estão inativas.`);
    }

    return {
      catalogsEnabled,
      entriesEnabled,
      projectRows,
      activityRows,
      newProjects,
      newActivities,
      activitiesWithoutAdm,
      mappedCount,
      unmappedCount,
      blockers,
      warnings
    };
  }

  function renderExcelPreflight() {
    const container = ensureExcelPreflightUi();
    if (!container) return;

    if (!excelImportAnalysis) {
      container.hidden = true;
      $("executeExcelImportBtn").disabled = true;
      return;
    }

    const preflight = buildExcelPreflight();
    container.hidden = false;

    const existingProjects = preflight.projectRows.filter(row => row.existing).length;
    const existingActivities = preflight.activityRows.filter(row => row.existing).length;

    $("importPreflightProjectsExisting").textContent = existingProjects;
    $("importPreflightProjectsNew").textContent = preflight.newProjects.length;
    $("importPreflightActivitiesExisting").textContent = existingActivities;
    $("importPreflightActivitiesNew").textContent = preflight.newActivities.length;
    $("importPreflightAdmLinks").textContent = preflight.activitiesWithoutAdm.length;
    $("importPreflightMappings").textContent =
      `${preflight.mappedCount}/${excelImportAnalysis.employeeSheets.length}`;

    let modeText = "Modo atual: ";
    if (preflight.catalogsEnabled && preflight.entriesEnabled) {
      modeText +=
        "projetos/atividades + apontamentos. Novos cadastros serão criados antes das horas.";
    } else if (!preflight.catalogsEnabled && preflight.entriesEnabled) {
      modeText +=
        "somente apontamentos. Nenhum projeto ou atividade nova será cadastrado.";
    } else if (preflight.catalogsEnabled && !preflight.entriesEnabled) {
      modeText += "somente projetos e atividades.";
    } else {
      modeText += "sem importação de projetos, atividades ou apontamentos.";
    }
    $("importPreflightMode").textContent = modeText;

    const projectStateLabel = row => {
      if (row.state === "new") return "NOVO — SERÁ CADASTRADO";
      if (row.state === "error") return "BLOQUEIA IMPORTAÇÃO";
      if (row.state === "warning") return "ATENÇÃO";
      return "EXISTENTE";
    };

    const activityStateLabel = row => {
      if (row.state === "new") return "NOVA — SERÁ CADASTRADA";
      if (row.state === "adjust") return "AJUSTAR ADM";
      if (row.state === "error") return "BLOQUEIA IMPORTAÇÃO";
      if (row.state === "warning") return "ATENÇÃO";
      return "EXISTENTE";
    };

    $("importPreflightProjectsSummary").textContent =
      `Projetos — ${existingProjects} existentes / ${preflight.newProjects.length} novos`;

    $("importPreflightProjectsList").innerHTML =
      preflight.projectRows.map(row => {
        const target = row.existing
          ? `${esc(row.existing.code || "sem código")} · ${esc(row.existing.name || "")}`
          : "Não encontrado no banco";
        const matchInfo = row.existing ? ` · correspondência por ${esc(row.matchedBy)}` : "";
        return `
          <div class="import-preflight-row state-${row.state}">
            <div class="import-preflight-row-main">
              <strong>${esc(row.source)}</strong>
              <small>${target}${matchInfo}</small>
            </div>
            <div class="import-preflight-row-action">
              <span class="import-preflight-pill">${projectStateLabel(row)}</span>
              <small>${esc(row.action)}</small>
            </div>
          </div>
        `;
      }).join("") ||
      '<div class="empty">Nenhum projeto identificado na planilha.</div>';

    $("importPreflightActivitiesSummary").textContent =
      `Atividades — ${existingActivities} existentes / ${preflight.newActivities.length} novas / ${preflight.activitiesWithoutAdm.length} ajuste(s) ADM`;

    $("importPreflightActivitiesList").innerHTML =
      preflight.activityRows.map(row => {
        const target = row.existing
          ? `${esc(row.existing.code || "sem código")} · ${esc(row.existing.name || "")}`
          : "Não encontrada no banco";
        return `
          <div class="import-preflight-row state-${row.state}">
            <div class="import-preflight-row-main">
              <strong>${esc(row.source)}</strong>
              <small>${target}</small>
            </div>
            <div class="import-preflight-row-action">
              <span class="import-preflight-pill">${activityStateLabel(row)}</span>
              <small>${esc(row.action)}</small>
            </div>
          </div>
        `;
      }).join("") ||
      '<div class="empty">Nenhuma atividade identificada na planilha.</div>';

    const badge = $("importPreflightBadge");
    const status = $("importPreflightStatus");

    if (preflight.blockers.length) {
      badge.textContent = "NÃO IMPORTAR";
      badge.className = "badge import-preflight-badge danger";
      status.className = "import-preflight-status danger";
      status.innerHTML = `
        <strong>Não importar ainda.</strong>
        <span>${preflight.blockers.map(item => esc(item)).join("<br>")}</span>
        ${preflight.warnings.length
          ? `<small>${preflight.warnings.map(item => esc(item)).join("<br>")}</small>`
          : ""}
      `;
    } else {
      badge.textContent = "PRONTO PARA IMPORTAR";
      badge.className = "badge import-preflight-badge success";
      status.className = "import-preflight-status success";

      const catalogSummary = preflight.catalogsEnabled
        ? `${preflight.newProjects.length} projeto(s) novo(s), ${preflight.newActivities.length} atividade(s) nova(s) e ${preflight.activitiesWithoutAdm.length} vínculo(s) ADM serão preparados antes dos apontamentos.`
        : "Nenhum projeto ou atividade será criado ou alterado.";

      status.innerHTML = `
        <strong>Pré-validação concluída.</strong>
        <span>${esc(catalogSummary)}</span>
        ${preflight.warnings.length
          ? `<small>${preflight.warnings.map(item => esc(item)).join("<br>")}</small>`
          : ""}
      `;
    }

    const hasSelectedData =
      (preflight.catalogsEnabled &&
        (excelImportAnalysis.projects.length || excelImportAnalysis.activities.length)) ||
      (preflight.entriesEnabled && preflight.mappedCount > 0) ||
      ($("importHolidays").checked && excelImportAnalysis.holidays.length) ||
      ($("importVacations").checked && preflight.mappedCount > 0);

    $("executeExcelImportBtn").disabled =
      preflight.blockers.length > 0 || !hasSelectedData;
  }

'@

$app = Replace-Required $app $jsInsertMarker ($jsFunctions + $jsInsertMarker) "inserir funcoes de pre-validacao"

$oldMapBlock = @'
    document.querySelectorAll(".import-user-map").forEach(select => {
      const sheet = analysis.employeeSheets[Number(select.dataset.importSheet)];
      select.value = sheet.matchedProfile?.id || "";
    });
'@

$newMapBlock = @'
    document.querySelectorAll(".import-user-map").forEach(select => {
      const sheet = analysis.employeeSheets[Number(select.dataset.importSheet)];
      select.value = sheet.matchedProfile?.id || "";
      select.addEventListener("change", renderExcelPreflight);
    });
'@

$app = Replace-Required $app $oldMapBlock $newMapBlock "vincular atualizacao da pre-validacao aos colaboradores"

$oldWarningBlock = @'
    $("importWarnings").hidden = messages.length === 0;
    $("importWarnings").innerHTML = messages.map(message => `<p>${esc(message)}</p>`).join("");
    $("executeExcelImportBtn").disabled = analysis.employeeSheets.length === 0;
    $("importResult").hidden = true;
'@

$newWarningBlock = @'
    $("importWarnings").hidden = messages.length === 0;
    $("importWarnings").innerHTML = messages.map(message => `<p>${esc(message)}</p>`).join("");
    $("importResult").hidden = true;
    renderExcelPreflight();
'@

$app = Replace-Required $app $oldWarningBlock $newWarningBlock "renderizar pre-validacao depois da analise"

$guardMarker = @'
  function formatImportError(error, stage="Importação"){
'@

$checkboxBinding = @'
  ["importCatalogs", "importEntries", "importHolidays", "importVacations"].forEach(id => {
    const field = $(id);
    if (!field) return;
    field.addEventListener("change", () => {
      if (excelImportAnalysis) renderExcelPreflight();
    });
  });

'@

$app = Replace-Required $app $guardMarker ($checkboxBinding + $guardMarker) "atualizar pre-validacao ao mudar opcoes"

$oldConfirmBlock = @'
    const confirmed = window.confirm(
      "IMPORTAR BANCO DE DADOS\n\n" +
      "A importação adicionará dados ao Supabase e pulará apontamentos já existentes.\n" +
      "As abas sem usuário selecionado não serão importadas.\n\n" +
      "Deseja continuar?"
    );
'@

$newConfirmBlock = @'
    const preflight = buildExcelPreflight();
    renderExcelPreflight();

    if (preflight.blockers.length) {
      toast("A pré-validação encontrou itens que bloqueiam a importação. Confira a análise antes de continuar.", true);
      return;
    }

    const confirmed = window.confirm(
      "IMPORTAR BANCO DE DADOS\n\n" +
      `Projetos novos: ${preflight.catalogsEnabled ? preflight.newProjects.length : 0}\n` +
      `Atividades novas: ${preflight.catalogsEnabled ? preflight.newActivities.length : 0}\n` +
      `Vínculos ADM a preparar: ${preflight.catalogsEnabled ? preflight.activitiesWithoutAdm.length : 0}\n` +
      `Abas de colaboradores vinculadas: ${preflight.mappedCount}/${excelImportAnalysis.employeeSheets.length}\n\n` +
      (preflight.catalogsEnabled
        ? "Projetos/atividades marcados como NOVOS serão cadastrados antes dos apontamentos.\n"
        : "Modo SOMENTE APONTAMENTOS: nenhum projeto ou atividade será criado.\n") +
      "Registros já existentes serão ignorados.\n\n" +
      "Deseja continuar?"
    );
'@

$app = Replace-Required $app $oldConfirmBlock $newConfirmBlock "confirmacao com resumo da pre-validacao"

$app = Replace-Required `
  $app `
  '      if ($("importCatalogs").checked || $("importEntries").checked) {' `
  '      if ($("importCatalogs").checked) {' `
  "respeitar checkbox Projetos e atividades"

$app = Replace-Required `
  $app `
  '        const existingProjects = new Map(projects.map(project => [normalizeImportText(project.name), project]));' `
  '        const existingProjects = buildImportProjectLookup();' `
  "match de projeto por codigo ou nome no cadastro"

$app = Replace-Required `
  $app `
  '        const projectByKey = new Map(projects.map(project => [normalizeImportText(project.name), project]));' `
  '        const projectByKey = buildImportProjectLookup();' `
  "match de projeto por codigo ou nome nos apontamentos"

$oldMissingLinks = '          const missingLinks=importedActivityIds.filter(id=>!activityAreaLinks.some(link=>link.activity_id===id));'
$newMissingLinks = @'
          const missingLinks=importedActivityIds.filter(id=>!activityAreaLinks.some(link=>
            String(link.activity_id||"")===String(id||"")&&
            String(link.area_code||"").trim().toUpperCase()==="ADM"
          ));
'@
$newMissingLinks = $newMissingLinks.TrimEnd()

$app = Replace-Required $app $oldMissingLinks $newMissingLinks "garantir ADM nas atividades importadas"

$oldFinally = @'
    } finally {
      $("executeExcelImportBtn").disabled = false;
    }
  };
'@

$newFinally = @'
    } finally {
      renderExcelPreflight();
    }
  };
'@

$app = Replace-Required $app $oldFinally $newFinally "manter botao conforme pre-validacao"

# ----------------------------------------------------------------------
# 2. CSS: visual da pre-validacao
# ----------------------------------------------------------------------

$cssAppend = @'

/* ==========================================================
   v2.19.20 — Pré-validação da importação Excel
   ========================================================== */
.import-preflight{
  margin:12px 0 14px;
  padding:14px;
  border:1px solid #cbd8d2;
  border-radius:12px;
  background:#f8fbfa;
}
.import-preflight-heading{
  display:flex;
  align-items:flex-start;
  justify-content:space-between;
  gap:12px;
  margin-bottom:12px;
}
.import-preflight-heading h3{
  margin:0 0 3px;
  font-size:15px;
  color:#052630;
}
.import-preflight-heading p{
  margin:0;
  font-size:12px;
  color:#5b6b67;
}
.import-preflight-badge.success{
  background:#e9f7e5;
  color:#2f6d1f;
  border:1px solid #9dca8d;
}
.import-preflight-badge.danger{
  background:#fff0ef;
  color:#a12c22;
  border:1px solid #efb0aa;
}
.import-preflight-metrics{
  display:grid;
  grid-template-columns:repeat(6,minmax(110px,1fr));
  gap:8px;
  margin-bottom:10px;
}
.import-preflight-metrics article{
  padding:9px 10px;
  border:1px solid #dbe5e1;
  border-radius:9px;
  background:#fff;
}
.import-preflight-metrics span{
  display:block;
  font-size:10px;
  color:#66756f;
  line-height:1.2;
}
.import-preflight-metrics strong{
  display:block;
  margin-top:3px;
  font-size:18px;
  color:#052630;
}
.import-preflight-mode{
  margin:8px 0 10px;
  padding:9px 11px;
  border-radius:8px;
  background:#eef5f2;
  color:#25433b;
  font-size:12px;
  font-weight:600;
}
.import-preflight-details{
  display:grid;
  grid-template-columns:1fr 1fr;
  gap:10px;
}
.import-preflight-details details{
  min-width:0;
  border:1px solid #dbe5e1;
  border-radius:9px;
  background:#fff;
  overflow:hidden;
}
.import-preflight-details summary{
  cursor:pointer;
  padding:10px 12px;
  font-size:12px;
  font-weight:700;
  color:#052630;
  background:#f3f7f5;
}
.import-preflight-list{
  max-height:280px;
  overflow:auto;
}
.import-preflight-row{
  display:grid;
  grid-template-columns:minmax(0,1fr) minmax(185px,.75fr);
  gap:10px;
  align-items:center;
  padding:9px 11px;
  border-top:1px solid #edf2ef;
}
.import-preflight-row-main,
.import-preflight-row-action{
  min-width:0;
}
.import-preflight-row-main strong,
.import-preflight-row-main small,
.import-preflight-row-action small{
  display:block;
}
.import-preflight-row-main strong{
  font-size:11px;
  color:#17362f;
  overflow-wrap:anywhere;
}
.import-preflight-row-main small,
.import-preflight-row-action small{
  margin-top:2px;
  font-size:10px;
  color:#66756f;
  line-height:1.25;
}
.import-preflight-row-action{
  text-align:right;
}
.import-preflight-pill{
  display:inline-block;
  padding:3px 7px;
  border-radius:999px;
  font-size:9px;
  font-weight:800;
  letter-spacing:.02em;
  background:#eaf5e6;
  color:#2f6d1f;
}
.import-preflight-row.state-new .import-preflight-pill{
  background:#e9f2fb;
  color:#205b91;
}
.import-preflight-row.state-adjust .import-preflight-pill,
.import-preflight-row.state-warning .import-preflight-pill{
  background:#fff5db;
  color:#805c00;
}
.import-preflight-row.state-error .import-preflight-pill{
  background:#fff0ef;
  color:#a12c22;
}
.import-preflight-row.state-error{
  background:#fffafa;
}
.import-preflight-status{
  margin-top:10px;
  padding:10px 12px;
  border-radius:9px;
  display:grid;
  gap:3px;
  font-size:11px;
}
.import-preflight-status strong{
  font-size:12px;
}
.import-preflight-status.success{
  background:#edf8ea;
  border:1px solid #b9dcad;
  color:#315d24;
}
.import-preflight-status.danger{
  background:#fff1f0;
  border:1px solid #efb8b2;
  color:#8c2b22;
}
.import-preflight-status small{
  opacity:.85;
  margin-top:2px;
}

@media (max-width:1200px){
  .import-preflight-metrics{
    grid-template-columns:repeat(3,minmax(120px,1fr));
  }
}
@media (max-width:800px){
  .import-preflight-heading{
    flex-direction:column;
  }
  .import-preflight-metrics{
    grid-template-columns:repeat(2,minmax(120px,1fr));
  }
  .import-preflight-details{
    grid-template-columns:1fr;
  }
  .import-preflight-row{
    grid-template-columns:1fr;
  }
  .import-preflight-row-action{
    text-align:left;
  }
}
'@

if (-not $css.Contains("v2.19.20 — Pré-validação da importação Excel")) {
  $css += $cssAppend
}

# ----------------------------------------------------------------------
# 3. Index: nova versao/build e novos assets
# ----------------------------------------------------------------------

$index = Replace-Required $index 'manifest.webmanifest?v=2.19.19' 'manifest.webmanifest?v=2.19.20' "manifest build"
$index = Replace-Required $index 'style-v2.19.5.css?build=2209' 'style-v2.19.20.css?build=2210' "novo css"
$index = Replace-Required $index 'const BUILD = "2.19.19";' 'const BUILD = "2.19.20";' "BUILD index"
$index = Replace-Required $index 'const ASSET_BUILD = "2209";' 'const ASSET_BUILD = "2210";' "ASSET_BUILD index"
$index = Replace-Required $index 'app-v2.19.5.js?build=2209' 'app-v2.19.20.js?build=2210' "novo javascript"
$index = Replace-Required $index 'navigator.serviceWorker.register("./sw.js?v=2.19.19"' 'navigator.serviceWorker.register("./sw.js?v=2.19.20"' "service worker version"

# ----------------------------------------------------------------------
# 4. Service Worker: cache novo
# ----------------------------------------------------------------------

$sw = Replace-Required $sw 'const CACHE = "aponta-horas-v2.19.19-colunas-legiveis";' 'const CACHE = "aponta-horas-v2.19.20-prevalidacao-importacao";' "cache sw"
$sw = Replace-Required $sw '"./app-v2.19.5.js?build=2209",' '"./app-v2.19.20.js?build=2210",' "app no cache"
$sw = Replace-Required $sw '"./style-v2.19.5.css?build=2209",' '"./style-v2.19.20.css?build=2210",' "css no cache"
$sw = Replace-Required $sw '"./manifest.webmanifest?v=2.19.19",' '"./manifest.webmanifest?v=2.19.20",' "manifest no cache"

# ----------------------------------------------------------------------
# 5. Gerar pasta pronta para subir
# ----------------------------------------------------------------------

$outDir = Join-Path $RepoDir "REVISAO_PRONTA_PARA_SUBIR_v2.19.20"
if (Test-Path $outDir) {
  Remove-Item -Recurse -Force $outDir
}
New-Item -ItemType Directory -Path $outDir | Out-Null

[System.IO.File]::WriteAllText((Join-Path $outDir "index.html"), $index, $utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $outDir "app-v2.19.20.js"), $app, $utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $outDir "style-v2.19.20.css"), $css, $utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $outDir "sw.js"), $sw, $utf8NoBom)

$notes = @"
APONTА HORAS v2.19.20 — PRE-VALIDACAO DE IMPORTACAO

ARQUIVOS PARA SUBIR:
- index.html
- app-v2.19.20.js
- style-v2.19.20.css
- sw.js

ALTERACOES:
1. A tela Importar Excel mostra ANTES da gravacao:
   - projetos existentes;
   - projetos novos;
   - atividades existentes;
   - atividades novas;
   - atividades que precisam receber vinculo ADM;
   - colaboradores vinculados;
   - erros bloqueantes.
2. O botao Importar dados fica bloqueado quando:
   - esta em modo Somente apontamentos;
   - existe projeto nao cadastrado;
   - existe atividade nao cadastrada;
   - existe atividade sem vinculo ADM.
3. Se Projetos e atividades estiver marcado:
   - novos projetos/atividades sao mostrados como "sera cadastrado";
   - vinculos ADM necessarios sao mostrados antes;
   - a importacao prepara esses cadastros antes dos apontamentos.
4. O checkbox Projetos e atividades passa a ser respeitado:
   - desmarcado = NAO cria nem atualiza projetos/atividades.
5. Projetos passam a ser encontrados por CODIGO OU NOME.
   Ex.: CORP encontra o projeto cujo nome e CORPORATIVO e codigo CORP.
6. Atividades historicas usadas em ADM:
   - a verificacao considera especificamente se existe vinculo ADM;
   - com Projetos e atividades marcado, o vinculo ADM faltante e incluido.
7. Cache atualizado para v2.19.20 / build 2210.

NAO EXIGE SQL NOVO.
"@
[System.IO.File]::WriteAllText((Join-Path $outDir "LEIA-ME.txt"), $notes, $utf8NoBom)

Write-Host ""
Write-Host "==============================================================" -ForegroundColor Green
Write-Host " REVISAO GERADA COM SUCESSO - v2.19.20" -ForegroundColor Green
Write-Host "==============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Pasta pronta para subir:" -ForegroundColor Cyan
Write-Host $outDir -ForegroundColor Yellow
Write-Host ""
Write-Host "Suba os 4 arquivos principais para a raiz do projeto:" -ForegroundColor White
Write-Host " - index.html"
Write-Host " - app-v2.19.20.js"
Write-Host " - style-v2.19.20.css"
Write-Host " - sw.js"
Write-Host ""
Read-Host "Pressione ENTER para finalizar"
