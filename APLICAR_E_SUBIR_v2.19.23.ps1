$ErrorActionPreference = "Stop"

$BaseDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Test-ApontaRoot {
  param([string]$Folder)
  if (-not $Folder) { return $false }
  if (-not (Test-Path $Folder -PathType Container)) { return $false }

  $required = @(
    "index.html",
    "app-v2.19.22.js",
    "style-v2.19.22.css",
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
if(Test-ApontaRoot $BaseDir){ $RepoDir = $BaseDir }

if(-not $RepoDir){
  $ParentDir = Split-Path -Parent $BaseDir
  if(Test-ApontaRoot $ParentDir){ $RepoDir = $ParentDir }
}

while(-not $RepoDir){
  Write-Host ""
  Write-Host "Cole o caminho da raiz do projeto APONTA P3:" -ForegroundColor Yellow
  $typed = Read-Host "CAMINHO"
  if($typed){ $typed = $typed.Trim().Trim('"') }

  if(Test-ApontaRoot $typed){
    $RepoDir = (Resolve-Path $typed).Path
  }else{
    Write-Host "Pasta invalida ou v2.19.22 nao encontrada." -ForegroundColor Red
  }
}

Write-Host ""
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host " APONTA P3 - CORRECAO IMPORTACAO AREA/REFERENCIA v2.19.23" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Projeto: $RepoDir" -ForegroundColor Green
Write-Host ""

$indexPath = Join-Path $RepoDir "index.html"
$appPath   = Join-Path $RepoDir "app-v2.19.22.js"
$swPath    = Join-Path $RepoDir "sw.js"

$index = [System.IO.File]::ReadAllText($indexPath).Replace("`r`n","`n")
$app   = [System.IO.File]::ReadAllText($appPath).Replace("`r`n","`n")
$sw    = [System.IO.File]::ReadAllText($swPath).Replace("`r`n","`n")

function Require-Text {
  param([string]$Text,[string]$Needle,[string]$Label)
  if(-not $Text.Contains($Needle)){
    throw "Validacao falhou: $Label"
  }
  Write-Host ("OK - " + $Label) -ForegroundColor DarkGreen
}

function Replace-TextOnce {
  param([string]$Text,[string]$Old,[string]$New,[string]$Label)
  $count=[regex]::Matches($Text,[regex]::Escape($Old)).Count
  if($count -ne 1){
    throw "Esperava encontrar '$Label' uma vez, mas encontrei $count."
  }
  Write-Host ("OK - " + $Label) -ForegroundColor DarkGreen
  return $Text.Replace($Old,$New)
}

function Replace-RegexOnce {
  param([string]$Text,[string]$Pattern,[string]$New,[string]$Label)

  $rx = New-Object System.Text.RegularExpressions.Regex(
    $Pattern,
    [System.Text.RegularExpressions.RegexOptions]::Singleline
  )
  $matches = $rx.Matches($Text)

  if($matches.Count -ne 1){
    throw "Esperava localizar '$Label' uma vez, mas encontrei $($matches.Count)."
  }

  $replacement = $New
  $evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
    param($match)
    return $replacement
  }

  Write-Host ("OK - " + $Label) -ForegroundColor DarkGreen
  return $rx.Replace($Text,$evaluator,1)
}

# -------------------------------------------------------------------
# 1. BASELINE
# -------------------------------------------------------------------

Require-Text $index 'const BUILD = "2.19.22";' "index v2.19.22"
Require-Text $index 'app-v2.19.22.js?build=2212' "app atual no index"
Require-Text $app 'async function analyzeExcelWorkbook(file) {' "analisador Excel"
Require-Text $app 'area_code: "ADM",' "forcamento ADM atual"
Require-Text $app 'function buildExcelPreflight() {' "pre-validacao atual"
Require-Text $sw 'aponta-horas-v2.19.22-colaborador-fechamento' "cache v2.19.22"

# -------------------------------------------------------------------
# 2. ANALISADOR EXCEL - SUPORTE AO FORMATO ENRIQUECIDO
# -------------------------------------------------------------------

$newAnalyzer = @'
  async function analyzeExcelWorkbook(file) {
    if (!window.XLSX) {
      throw new Error("A biblioteca de leitura do Excel não foi carregada. Atualize a página e tente novamente.");
    }

    const arrayBuffer = await file.arrayBuffer();
    const workbook = XLSX.read(arrayBuffer, {
      type: "array",
      cellDates: true,
      cellNF: false,
      cellText: false
    });

    const activityDefinitions = new Map();
    const activitiesSheetName = workbook.SheetNames.find(
      name => normalizeImportText(name) === "ATIVIDADES"
    );

    if (activitiesSheetName) {
      const rows = XLSX.utils.sheet_to_json(workbook.Sheets[activitiesSheetName], {
        header: 1,
        raw: true,
        defval: null
      });

      rows.slice(1).forEach(row => {
        const activityName = String(row[1] ?? "").trim();
        if (!activityName) return;

        activityDefinitions.set(normalizeImportText(activityName), {
          name: activityName,
          activity_type: String(row[0] ?? "Demanda").trim() || "Demanda",
          frequency: String(row[2] ?? "").trim(),
          responsible_name: String(row[3] ?? "").trim(),
          backup_name: String(row[4] ?? "").trim()
        });
      });
    }

    const ignoredSheets = new Set(["TOTAL", "ATIVIDADES"]);
    const projectMap = new Map();
    const activityMap = new Map(activityDefinitions);
    const holidayDates = new Set();
    const employeeSheets = [];
    let enrichedFormatDetected = false;

    workbook.SheetNames.forEach(sheetName => {
      if (ignoredSheets.has(normalizeImportText(sheetName))) return;

      const rows = XLSX.utils.sheet_to_json(workbook.Sheets[sheetName], {
        header: 1,
        raw: true,
        defval: null
      });

      if (rows.length < 4) return;

      const header = rows[2] || [];
      const headerIndex = new Map();

      header.forEach((value,index) => {
        const key = normalizeImportText(value);
        if (key && !headerIndex.has(key)) headerIndex.set(key,index);
      });

      const projectColumn =
        headerIndex.get("PROJETO") ?? 0;
      const activityColumn =
        headerIndex.get("ATIVIDADE") ?? 1;
      const areaColumn =
        headerIndex.has("AREA") ? headerIndex.get("AREA") : -1;
      const referenceColumn =
        headerIndex.has("REFERENCIA") ? headerIndex.get("REFERENCIA") : -1;
      const observationColumn =
        headerIndex.has("OBSERVACAO") ? headerIndex.get("OBSERVACAO") : -1;

      let detailColumn = -1;
      for(const [key,index] of headerIndex.entries()){
        if(key.startsWith("DETALHAR")){
          detailColumn=index;
          break;
        }
      }
      if(detailColumn < 0) detailColumn = 2;

      if(areaColumn >= 0 || referenceColumn >= 0 || observationColumn >= 0){
        enrichedFormatDetected = true;
      }

      const columns = [];
      header.forEach((value,column) => {
        const isoDate = parseExcelDate(value);
        if (isoDate) columns.push({column,date:isoDate});
      });

      if (!columns.length) return;

      const entries = [];
      const vacationDates = new Set();
      let ignoredFuture = 0;
      let ignoredInvalid = 0;
      let totalHours = 0;

      for (let rowIndex = 3; rowIndex < rows.length; rowIndex += 1) {
        const row = rows[rowIndex] || [];
        const projectName = String(row[projectColumn] ?? "").trim();
        const activityName = String(row[activityColumn] ?? "").trim();

        const areaName =
          areaColumn >= 0
            ? String(row[areaColumn] ?? "").trim()
            : "Administrativo";

        const reference =
          referenceColumn >= 0
            ? String(row[referenceColumn] ?? "").trim()
            : "";

        const observation =
          observationColumn >= 0
            ? String(row[observationColumn] ?? "").trim()
            : "";

        const detailRequired =
          detailColumn >= 0 &&
          normalizeImportText(row[detailColumn]) === "X";

        if (!projectName || !activityName || activityName === "-") continue;

        const projectKey = normalizeImportText(projectName);
        const activityKey = normalizeImportText(activityName);
        const areaCode = importAreaCode(areaName);

        if (!projectMap.has(projectKey)) {
          projectMap.set(projectKey, {
            name: projectName,
            description: "Importado da planilha de apontamentos."
          });
        }

        if (!activityMap.has(activityKey)) {
          activityMap.set(activityKey, {
            name: activityName,
            activity_type: "Demanda",
            frequency: "",
            responsible_name: "",
            backup_name: ""
          });
        }

        columns.forEach(({column,date}) => {
          const value = row[column];
          if (value === null || value === undefined || value === "") return;

          const numericValue = toImportNumber(value);

          if (numericValue !== null) {
            const normalizedHours = Math.round(numericValue * 100) / 100;

            if (normalizedHours <= 0) return;

            if (normalizedHours > 24) {
              ignoredInvalid += 1;
              return;
            }

            if (date > today()) {
              ignoredFuture += 1;
              return;
            }

            const detailsParts = [];

            if(observation){
              detailsParts.push(observation);
            }

            if(
              reference &&
              normalizeImportText(reference) !== "NAO APLICAVEL" &&
              (!areaCode || areaDetailType(areaCode) === "none")
            ){
              detailsParts.push(`Referência original: ${reference}`);
            }

            if(!detailsParts.length){
              detailsParts.push(`Importado da planilha ${file.name}`);
            }

            if(detailRequired){
              detailsParts.push("Atividade marcada para detalhamento na planilha original.");
            }

            entries.push({
              date,
              rowNumber: rowIndex + 1,
              projectKey,
              activityKey,
              areaName,
              areaCode,
              reference,
              observation,
              hours: normalizedHours,
              details: detailsParts.join(" — ")
            });

            totalHours += normalizedHours;
            return;
          }

          const special = normalizeImportText(value);
          if (!special) return;

          if (special.includes("FERIADO") || special === "FER") {
            holidayDates.add(date);
          } else if (special.includes("FERIAS")) {
            vacationDates.add(date);
          } else if (!["FDS","S","D","SAB","DOM"].includes(special)) {
            ignoredInvalid += 1;
          }
        });
      }

      const dates = columns.map(item => item.date).sort();

      employeeSheets.push({
        sheetName,
        matchedProfile: findBestProfileForSheet(sheetName),
        entries,
        vacationDates: [...vacationDates],
        startDate: dates[0],
        endDate: dates[dates.length - 1],
        totalHours,
        ignoredFuture,
        ignoredInvalid
      });
    });

    return {
      fileName: file.name,
      hasActivitiesSheet: Boolean(activitiesSheetName),
      enrichedFormatDetected,
      employeeSheets,
      projects: [...projectMap.values()],
      activities: [...activityMap.values()],
      holidays: [...holidayDates].sort()
    };
  }

  function buildImportProjectLookup() {
'@

$app = Replace-RegexOnce `
  $app `
  '  async function analyzeExcelWorkbook\(file\) \{.*?\n  \}\n  function buildImportProjectLookup\(\) \{' `
  $newAnalyzer `
  "analisador Excel enriquecido"

# -------------------------------------------------------------------
# 3. RESOLUCAO DE AREA E REFERENCIA
# -------------------------------------------------------------------

$newHelpers = @'
  function activityHasImportArea(activityId, areaCode) {
    const normalizedArea = String(areaCode || "").trim().toUpperCase();
    return activityAreaLinks.some(link =>
      String(link.activity_id || "") === String(activityId || "") &&
      String(link.area_code || "").trim().toUpperCase() === normalizedArea
    );
  }

  function importAreaCode(value) {
    const key = normalizeImportText(value);

    if (!key) return "";

    const direct = workAreas.find(area =>
      normalizeImportText(area.code) === key ||
      normalizeImportText(area.name) === key
    );

    if (direct) return String(direct.code || "").trim().toUpperCase();

    const aliases = {
      "ADMINISTRATIVO":"ADM",
      "ADMINISTRACAO":"ADM",
      "ADM":"ADM",
      "FABRICACAO":"FAB",
      "FAB":"FAB",
      "MONTAGEM ESTRUTURAL":"MES",
      "ESTRUTURAL":"MES",
      "MES":"MES",
      "MONTAGEM FINAL":"MFI",
      "FINAL":"MFI",
      "MFI":"MFI",
      "MONTAGEM DE PAINEIS":"MPA",
      "MONTAGEM PAINEIS":"MPA",
      "PAINEIS":"MPA",
      "MPA":"MPA",
      "COMISSIONAMENTO":"COM",
      "COM":"COM"
    };

    return aliases[key] || "";
  }

  function importLooseKey(value) {
    return normalizeImportText(value)
      .replace(/[^A-Z0-9]+/g,"");
  }

  function matchesImportReference(row, reference) {
    const key = importLooseKey(reference);
    if (!key || !row) return false;

    return [
      row.code,
      row.name,
      row.display_name
    ].some(value => value && importLooseKey(value) === key);
  }

  function findImportRoomInstance(projectId, reference) {
    const key = importLooseKey(reference);
    if (!key) return null;

    return projectRoomInstances.find(instance => {
      if(instance.project_id !== projectId || instance.active === false) return false;

      const room = rooms.find(item => item.id === instance.room_id);
      const number = String(instance.instance_number || "").padStart(2,"0");
      const candidates = [
        instance.code,
        instance.display_name,
        room?.code,
        room?.name,
        room?.code ? `${room.code} ${number}` : "",
        room?.name ? `${room.name} ${number}` : ""
      ];

      return candidates.some(value =>
        value && importLooseKey(value) === key
      );
    }) || null;
  }

  function findImportModuleInstance(roomInstanceId, reference) {
    const key = importLooseKey(reference);
    const numberMatch = String(reference || "").match(/(\d+)/);
    const moduleNumber = numberMatch ? Number(numberMatch[1]) : null;

    return projectRoomInstanceModules.find(module => {
      if(module.room_instance_id !== roomInstanceId || module.active === false) return false;

      if(
        key &&
        [module.code,module.display_name].some(value =>
          value && importLooseKey(value) === key
        )
      ){
        return true;
      }

      return Number.isInteger(moduleNumber) &&
        Number(module.module_number) === moduleNumber;
    }) || null;
  }

  function resolveImportReferencePayload(entry, project) {
    const areaCode =
      entry.areaCode ||
      importAreaCode(entry.areaName) ||
      "ADM";

    const detailType = areaDetailType(areaCode);
    const reference = String(entry.reference || "").trim();

    const payload = {
      area_code: areaCode,
      sector_id: null,
      room_id: null,
      module_id: null,
      panel_type_id: null,
      project_room_instance_id: null,
      project_room_instance_module_id: null,
      module_part: null
    };

    if(detailType === "none"){
      return {payload,error:null};
    }

    if(!reference || normalizeImportText(reference) === "NAO APLICAVEL"){
      return {
        payload,
        error:`A área ${areaName(areaCode)} exige referência, mas a planilha não informou uma referência.`
      };
    }

    if(detailType === "sector"){
      const sector = manufacturingSectors.find(row =>
        row.active !== false &&
        matchesImportReference(row,reference)
      );

      if(!sector){
        return {
          payload,
          error:`Setor "${reference}" não encontrado para Fabricação.`
        };
      }

      payload.sector_id = sector.id;
      return {payload,error:null};
    }

    if(detailType === "panel_type"){
      const panel = panelTypes.find(row =>
        row.active !== false &&
        matchesImportReference(row,reference)
      );

      if(!panel){
        return {
          payload,
          error:`Tipo de painel "${reference}" não encontrado.`
        };
      }

      payload.panel_type_id = panel.id;
      return {payload,error:null};
    }

    if(detailType === "room"){
      const roomInstance = findImportRoomInstance(project.id,reference);

      if(!roomInstance){
        return {
          payload,
          error:`Sala "${reference}" não encontrada no projeto ${project.name}.`
        };
      }

      payload.project_room_instance_id = roomInstance.id;
      payload.room_id = roomInstance.room_id || null;
      return {payload,error:null};
    }

    if(detailType === "module"){
      const parts = reference
        .split("/")
        .map(value => value.trim())
        .filter(Boolean);

      const roomReference = parts[0] || "";
      const moduleReference = parts[1] || "";
      const partReference = parts.slice(2).join(" ");

      const roomInstance = findImportRoomInstance(
        project.id,
        roomReference
      );

      if(!roomInstance){
        return {
          payload,
          error:`Sala estrutural "${roomReference}" não encontrada no projeto ${project.name}.`
        };
      }

      const moduleInstance = findImportModuleInstance(
        roomInstance.id,
        moduleReference
      );

      if(!moduleInstance){
        return {
          payload,
          error:`Módulo "${moduleReference}" não encontrado em ${roomReference} / ${project.name}.`
        };
      }

      payload.project_room_instance_id = roomInstance.id;
      payload.project_room_instance_module_id = moduleInstance.id;
      payload.room_id = roomInstance.room_id || null;
      payload.module_id = moduleInstance.legacy_module_id || null;

      if(!isMonoblockRoomInstance(roomInstance.id)){
        const normalizedPart = normalizeImportText(partReference);

        if(normalizedPart.includes("INFERIOR")){
          payload.module_part = "inferior";
        }else if(normalizedPart.includes("SUPERIOR")){
          payload.module_part = "superior";
        }else{
          return {
            payload,
            error:`Parte do módulo não identificada em "${reference}". Use Parte inferior ou Parte superior.`
          };
        }
      }

      return {payload,error:null};
    }

    return {
      payload,
      error:`Fluxo de referência não suportado para a área ${areaName(areaCode)}.`
    };
  }

  function importReferenceSignature(row) {
    return [
      row.area_code || "",
      row.sector_id || "",
      row.room_id || "",
      row.module_id || "",
      row.panel_type_id || "",
      row.project_room_instance_id || "",
      row.project_room_instance_module_id || "",
      row.module_part || ""
    ].join("|");
  }

  function importEntrySignature(row) {
    return [
      row.entry_date || "",
      row.project_id || "",
      row.activity_id || "",
      importReferenceSignature(row),
      normalizeImportText(row.details || "")
    ].join("|");
  }

  function ensureExcelPreflightUi() {
'@

$app = Replace-RegexOnce `
  $app `
  '  function activityHasImportAdminArea\(activityId\) \{.*?\n  \}\n\n  function ensureExcelPreflightUi\(\) \{' `
  $newHelpers `
  "resolucao de area e referencia"

$app = Replace-TextOnce `
  $app `
  '<span>Ajustes de área ADM</span>' `
  '<span>Vínculos de área</span>' `
  "rotulo de vinculos de area"

# -------------------------------------------------------------------
# 4. PRE-VALIDACAO POR AREA REAL + REFERENCIA
# -------------------------------------------------------------------

$newPreflight = @'
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
        referenceIssues: [],
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
      activities.map(activity => [
        normalizeImportText(activity.name),
        activity
      ])
    );

    const allEntries = analysis.employeeSheets.flatMap(
      sheet => sheet.entries || []
    );

    const usageByActivity = new Map();

    allEntries.forEach(entry => {
      const areaCode =
        entry.areaCode ||
        importAreaCode(entry.areaName) ||
        "ADM";

      if(!usageByActivity.has(entry.activityKey)){
        usageByActivity.set(entry.activityKey,new Set());
      }

      usageByActivity.get(entry.activityKey).add(areaCode);
    });

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

      const requiredAreas = [
        ...(usageByActivity.get(key) || new Set(["ADM"]))
      ].filter(Boolean);

      const missingAreas = existing
        ? requiredAreas.filter(areaCode =>
            !activityHasImportArea(existing.id,areaCode)
          )
        : [];

      let state = "existing";
      let action =
        `Usar cadastro existente nas áreas: ${requiredAreas.join(", ")}`;

      if (!existing) {
        state = catalogsEnabled ? "new" : "error";
        action = catalogsEnabled
          ? `Será cadastrada e vinculada às áreas: ${requiredAreas.join(", ")}`
          : "Não existe e NÃO será cadastrada";
      } else if (entriesEnabled && missingAreas.length) {
        state = catalogsEnabled ? "adjust" : "error";
        action = catalogsEnabled
          ? `Serão incluídos vínculos: ${missingAreas.join(", ")}`
          : `Sem vínculo com: ${missingAreas.join(", ")}`;
      } else if (existing.active === false) {
        state = "warning";
        action = "Cadastro encontrado, porém está inativo";
      }

      return {
        source: item.name,
        existing,
        requiredAreas,
        missingAreas,
        state,
        action
      };
    });

    const newProjects = projectRows.filter(row => !row.existing);
    const newActivities = activityRows.filter(row => !row.existing);

    // Mantém o nome da propriedade para compatibilidade com a UI v2.19.22,
    // mas agora representa vínculos de QUALQUER área, não somente ADM.
    const activitiesWithoutAdm = activityRows.filter(
      row =>
        row.existing &&
        entriesEnabled &&
        row.missingAreas.length
    );

    const mappingSelects = [
      ...document.querySelectorAll(".import-user-map")
    ];

    const mappedCount = mappingSelects.filter(
      select => Boolean(select.value)
    ).length;

    const unmappedCount = Math.max(
      0,
      analysis.employeeSheets.length - mappedCount
    );

    const blockers = [];
    const warnings = [];
    const referenceIssues = [];
    const invalidAreaEntries = [];

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

    if(entriesEnabled){
      allEntries.forEach(entry => {
        const areaCode =
          entry.areaCode ||
          importAreaCode(entry.areaName);

        if(!areaCode){
          invalidAreaEntries.push(entry);
          return;
        }

        const project = projectLookup.get(entry.projectKey);

        if(!project){
          return;
        }

        const resolution = resolveImportReferencePayload(
          {...entry,areaCode},
          project
        );

        if(resolution.error){
          referenceIssues.push({
            ...entry,
            error:resolution.error
          });
        }
      });
    }

    if(invalidAreaEntries.length){
      blockers.push(
        `${invalidAreaEntries.length} apontamento(s) possuem área não reconhecida.`
      );
    }

    if(referenceIssues.length){
      const samples = referenceIssues
        .slice(0,3)
        .map(issue =>
          `${issue.error} (linha ${issue.rowNumber || "?"})`
        )
        .join(" | ");

      blockers.push(
        `${referenceIssues.length} apontamento(s) possuem referência que não foi encontrada. ${samples}`
      );
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
        const totalMissing = activitiesWithoutAdm.reduce(
          (sum,row) => sum + row.missingAreas.length,
          0
        );

        blockers.push(
          `${totalMissing} vínculo(s) entre atividade e área estão ausentes.`
        );
      }
    }

    if (entriesEnabled && unmappedCount > 0) {
      warnings.push(
        `${unmappedCount} aba(s) estão sem usuário e serão ignoradas se permanecerem assim.`
      );
    }

    if(!analysis.enrichedFormatDetected){
      warnings.push(
        "Formato antigo detectado: sem colunas Área/Referência. Esses apontamentos continuarão sendo tratados como Administrativo."
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
      referenceIssues,
      mappedCount,
      unmappedCount,
      blockers,
      warnings
    };
  }

  function renderExcelPreflight() {
'@

$app = Replace-RegexOnce `
  $app `
  '  function buildExcelPreflight\(\) \{.*?\n  \}\n\n  function renderExcelPreflight\(\) \{' `
  $newPreflight `
  "pre-validacao por area real"

# Ajustar textos do render existente sem reescrever a UI inteira.
$app = $app.Replace(
  'if (row.state === "adjust") return "AJUSTAR ADM";',
  'if (row.state === "adjust") return "AJUSTAR ÁREA";'
)

$app = $app.Replace(
  '${preflight.activitiesWithoutAdm.length} ajuste(s) ADM',
  '${preflight.activitiesWithoutAdm.length} atividade(s) com vínculo a ajustar'
)

$app = $app.Replace(
  'Vínculos ADM a preparar:',
  'Atividades com vínculos de área a preparar:'
)

$app = $app.Replace(
  '${preflight.catalogsEnabled ? preflight.activitiesWithoutAdm.length : 0}\\n',
  '${preflight.catalogsEnabled ? preflight.activitiesWithoutAdm.length : 0}\\n'
)

# -------------------------------------------------------------------
# 5. VINCULAR ATIVIDADES AS AREAS REALMENTE USADAS
# -------------------------------------------------------------------

$newAreaLinksBlock = @'
        await loadBaseData();

        const requiredLinks = new Map();

        analysis.employeeSheets.forEach(sheet => {
          (sheet.entries || []).forEach(entry => {
            const activity = activities.find(
              row =>
                normalizeImportText(row.name) ===
                entry.activityKey
            );

            const areaCode =
              entry.areaCode ||
              importAreaCode(entry.areaName) ||
              "ADM";

            if(!activity || !areaCode) return;

            const key = `${activity.id}|${areaCode}`;

            if(!activityHasImportArea(activity.id,areaCode)){
              requiredLinks.set(key,{
                activity_id:activity.id,
                area_code:areaCode
              });
            }
          });
        });

        if(requiredLinks.size){
          importStage="Vínculo das atividades com as áreas da planilha";

          const {error:areaLinkError}=await sb
            .from("activity_area_links")
            .upsert(
              [...requiredLinks.values()],
              {
                onConflict:"activity_id,area_code",
                ignoreDuplicates:true
              }
            );

          if(areaLinkError)throw areaLinkError;
          await loadBaseData();
        }
      }
'@

$app = Replace-RegexOnce `
  $app `
  '        await loadBaseData\(\);\n        const importedActivityIds=.*?\n      \}' `
  $newAreaLinksBlock `
  "vinculos reais de atividade/area"

# -------------------------------------------------------------------
# 6. IMPORTAR AREA + REFERENCIA E SOBREPOR RASCUNHO/DEVOLVIDO
# -------------------------------------------------------------------

$newEntriesBlock = @'
      if ($("importEntries").checked) {
        importStage="Preparação dos apontamentos";
        setImportProgress(55, "Validando áreas e referências...");

        const projectByKey = buildImportProjectLookup();
        const activityByKey = new Map(
          activities.map(activity => [
            normalizeImportText(activity.name),
            activity
          ])
        );

        const rowsToInsert = [];
        const rowsToUpdate = [];

        for (const [sheetIndex,userId] of mappings.entries()) {
          const sheet = analysis.employeeSheets[sheetIndex];
          if (!sheet.entries.length) continue;

          const start = sheet.entries.reduce(
            (min,entry) => entry.date < min ? entry.date : min,
            sheet.entries[0].date
          );

          const end = sheet.entries.reduce(
            (max,entry) => entry.date > max ? entry.date : max,
            sheet.entries[0].date
          );

          const {data:existingRows,error}=await sb
            .from("time_entries")
            .select(
              "id,entry_date,project_id,activity_id,area_code,sector_id,room_id,module_id,panel_type_id,project_room_instance_id,project_room_instance_module_id,module_part,hours,details,status"
            )
            .eq("user_id",userId)
            .gte("entry_date",start)
            .lte("entry_date",end);

          if(error)throw error;

          const existingBySignature = new Map();

          (existingRows || []).forEach(row => {
            const signature = importEntrySignature(row);
            if(!existingBySignature.has(signature)){
              existingBySignature.set(signature,[]);
            }
            existingBySignature.get(signature).push(row);
          });

          for(const entry of sheet.entries){
            const project = projectByKey.get(entry.projectKey);
            const activity = activityByKey.get(entry.activityKey);

            if(!project || !activity){
              entriesSkipped += 1;
              continue;
            }

            const areaCode =
              entry.areaCode ||
              importAreaCode(entry.areaName) ||
              "ADM";

            if(!activityHasImportArea(activity.id,areaCode)){
              throw new Error(
                `Linha ${entry.rowNumber || "?"}: a atividade "${activity.name}" não pertence à área ${areaName(areaCode)} (${areaCode}).`
              );
            }

            const resolution = resolveImportReferencePayload(
              {...entry,areaCode},
              project
            );

            if(resolution.error){
              throw new Error(
                `Linha ${entry.rowNumber || "?"}: ${resolution.error}`
              );
            }

            const payload = {
              user_id:userId,
              entry_date:entry.date,
              project_id:project.id,
              activity_id:activity.id,
              ...resolution.payload,
              hours:Math.round(Number(entry.hours) * 100) / 100,
              details:entry.details || "",
              status:"rascunho"
            };

            const signature = importEntrySignature(payload);
            const candidates = existingBySignature.get(signature) || [];
            const existing = candidates.shift() || null;

            if(existing){
              if(["rascunho","devolvido"].includes(existing.status)){
                rowsToUpdate.push({
                  id:existing.id,
                  payload
                });
                entriesUpdated += 1;
              }else{
                entriesSkipped += 1;
              }
            }else{
              rowsToInsert.push(payload);
            }
          }
        }

        if(rowsToUpdate.length){
          importStage="Atualização de apontamentos existentes";
          setImportProgress(
            65,
            `Atualizando ${rowsToUpdate.length} apontamento(s) existentes...`
          );

          for(let index=0;index<rowsToUpdate.length;index+=1){
            const item=rowsToUpdate[index];

            const {error:updateError}=await sb
              .from("time_entries")
              .update(item.payload)
              .eq("id",item.id);

            if(updateError){
              const detailedError=new Error(
                `atualização ${index+1}, data ${item.payload.entry_date}: ${updateError.message || "erro ao atualizar"}`
              );
              detailedError.code=updateError.code;
              detailedError.details=updateError.details;
              detailedError.hint=updateError.hint;
              throw detailedError;
            }
          }
        }

        setImportProgress(
          70,
          `Importando ${rowsToInsert.length} novo(s) apontamento(s)...`
        );

        importStage="Apontamentos";
        const chunkSize=100;

        for(
          let index=0;
          index<rowsToInsert.length;
          index+=chunkSize
        ){
          const chunk=rowsToInsert.slice(index,index+chunkSize);
          const inserted=await insertInChunks(
            "time_entries",
            chunk,
            chunkSize
          );

          entriesCreated += inserted;

          const fraction=rowsToInsert.length
            ?Math.min(index+chunk.length,rowsToInsert.length)/
              rowsToInsert.length
            :1;

          setImportProgress(
            70+Math.round(fraction*25),
            `Importando novos apontamentos: ${entriesCreated}/${rowsToInsert.length}`
          );
        }
      }
'@

$app = Replace-RegexOnce `
  $app `
  '      if \(\$\("importEntries"\)\.checked\) \{\n        importStage="Preparação dos apontamentos";.*?\n      \}\n\n      await loadBaseData\(\);' `
  ($newEntriesBlock + "`n`n      await loadBaseData();") `
  "importacao com area/referencia"

# Contador de atualizados.
$app = Replace-TextOnce `
  $app `
  '      let entriesCreated = 0;' `
  '      let entriesCreated = 0;`n      let entriesUpdated = 0;' `
  "contador de atualizados"

# Corrigir o `n literal gerado pelo PowerShell no texto acima.
$app = $app.Replace(
  'let entriesCreated = 0;`n      let entriesUpdated = 0;',
  "let entriesCreated = 0;`n      let entriesUpdated = 0;"
)

# Resultado final.
$app = Replace-TextOnce `
  $app `
  '          <span><strong>${entriesCreated}</strong> apontamentos importados</span>' `
  '          <span><strong>${entriesCreated}</strong> apontamentos novos importados</span>`n          <span><strong>${entriesUpdated}</strong> apontamentos existentes atualizados</span>' `
  "resultado com atualizados"

$app = $app.Replace(
  '</span>`n          <span><strong>${entriesUpdated}',
  "</span>`n          <span><strong>`${entriesUpdated}"
)

# Confirmacao: informar que rascunho/devolvido pode ser atualizado.
$app = $app.Replace(
  '"Registros já existentes serão ignorados.\n\n" +',
  '"Registros equivalentes em Rascunho/Devolvido serão atualizados; Enviados/Aprovados serão preservados.\n\n" +'
)

# -------------------------------------------------------------------
# 7. VERSAO / CACHE
# -------------------------------------------------------------------

$index = Replace-TextOnce `
  $index `
  'manifest.webmanifest?v=2.19.22' `
  'manifest.webmanifest?v=2.19.23' `
  "manifest v2.19.23"

$index = Replace-TextOnce `
  $index `
  'style-v2.19.22.css?build=2212' `
  'style-v2.19.22.css?build=2213' `
  "cache bust do CSS"

$index = Replace-TextOnce `
  $index `
  'const BUILD = "2.19.22";' `
  'const BUILD = "2.19.23";' `
  "BUILD v2.19.23"

$index = Replace-TextOnce `
  $index `
  'const ASSET_BUILD = "2212";' `
  'const ASSET_BUILD = "2213";' `
  "ASSET_BUILD 2213"

$index = Replace-TextOnce `
  $index `
  'app-v2.19.22.js?build=2212' `
  'app-v2.19.23.js?build=2213' `
  "app v2.19.23"

$index = Replace-TextOnce `
  $index `
  'navigator.serviceWorker.register("./sw.js?v=2.19.22"' `
  'navigator.serviceWorker.register("./sw.js?v=2.19.23"' `
  "service worker v2.19.23"

$sw = Replace-TextOnce `
  $sw `
  'const CACHE = "aponta-horas-v2.19.22-colaborador-fechamento";' `
  'const CACHE = "aponta-horas-v2.19.23-importacao-area-referencia";' `
  "cache v2.19.23"

$sw = Replace-TextOnce `
  $sw `
  '"./app-v2.19.22.js?build=2212",' `
  '"./app-v2.19.23.js?build=2213",' `
  "app no service worker"

$sw = Replace-TextOnce `
  $sw `
  '"./style-v2.19.22.css?build=2212",' `
  '"./style-v2.19.22.css?build=2213",' `
  "CSS no service worker"

$sw = Replace-TextOnce `
  $sw `
  '"./manifest.webmanifest?v=2.19.22",' `
  '"./manifest.webmanifest?v=2.19.23",' `
  "manifest no service worker"

# -------------------------------------------------------------------
# 8. VALIDACAO E BACKUP
# -------------------------------------------------------------------

$checks=@(
  @{Label="sem ADM fixo";Ok=(-not $app.Contains('area_code: "ADM",'))},
  @{Label="le coluna Area";Ok=$app.Contains('headerIndex.has("AREA")')},
  @{Label="le coluna Referencia";Ok=$app.Contains('headerIndex.has("REFERENCIA")')},
  @{Label="le coluna Observacao";Ok=$app.Contains('headerIndex.has("OBSERVACAO")')},
  @{Label="resolve setor";Ok=$app.Contains('detailType === "sector"')},
  @{Label="resolve painel";Ok=$app.Contains('detailType === "panel_type"')},
  @{Label="resolve sala";Ok=$app.Contains('detailType === "room"')},
  @{Label="resolve modulo";Ok=$app.Contains('detailType === "module"')},
  @{Label="atualiza existentes";Ok=$app.Contains("rowsToUpdate.push")},
  @{Label="v2.19.23";Ok=$index.Contains('const BUILD = "2.19.23";')},
  @{Label="cache novo";Ok=$sw.Contains("aponta-horas-v2.19.23-importacao-area-referencia")}
)

foreach($check in $checks){
  if(-not $check.Ok){
    throw ("Validacao final falhou: " + $check.Label)
  }
  Write-Host ("VALIDADO - " + $check.Label) -ForegroundColor Green
}

$stamp=Get-Date -Format "yyyyMMdd-HHmmss"
$backup=Join-Path $RepoDir ("BACKUP_ANTES_v2.19.23_" + $stamp)
New-Item -ItemType Directory -Path $backup | Out-Null

Copy-Item $indexPath (Join-Path $backup "index.html") -Force
Copy-Item $appPath (Join-Path $backup "app-v2.19.22.js") -Force
Copy-Item $swPath (Join-Path $backup "sw.js") -Force

$utf8NoBom=New-Object System.Text.UTF8Encoding($false)

[System.IO.File]::WriteAllText(
  $indexPath,
  $index,
  $utf8NoBom
)

$newAppPath=Join-Path $RepoDir "app-v2.19.23.js"

[System.IO.File]::WriteAllText(
  $newAppPath,
  $app,
  $utf8NoBom
)

[System.IO.File]::WriteAllText(
  $swPath,
  $sw,
  $utf8NoBom
)

Write-Host ""
Write-Host "Backup criado: $backup" -ForegroundColor Cyan

$node=Get-Command node -ErrorAction SilentlyContinue
if($node){
  Write-Host "Validando JavaScript..." -ForegroundColor Cyan
  & node --check $newAppPath
  if($LASTEXITCODE -ne 0){
    throw "Erro de sintaxe no app-v2.19.23.js. O GitHub NAO sera atualizado."
  }
  Write-Host "OK - JavaScript valido." -ForegroundColor Green
}else{
  Write-Host "Node nao encontrado. A validacao estrutural passou, mas o teste node --check foi ignorado." -ForegroundColor Yellow
}

# -------------------------------------------------------------------
# 9. GIT ADD / COMMIT / PUSH
# -------------------------------------------------------------------

Set-Location $RepoDir

$git=Get-Command git -ErrorAction SilentlyContinue
if(-not $git){ throw "Git nao encontrado." }

Write-Host ""
Write-Host "Arquivos alterados:" -ForegroundColor Cyan
& git status --short

& git add index.html app-v2.19.23.js sw.js
if($LASTEXITCODE -ne 0){ throw "Falha no git add." }

& git diff --cached --quiet
$hasChanges=($LASTEXITCODE -ne 0)

if($hasChanges){
  & git commit -m "v2.19.23 - importar area e referencia reais"
  if($LASTEXITCODE -ne 0){ throw "Falha no git commit." }
}else{
  Write-Host "Nenhuma alteracao nova para commit." -ForegroundColor Yellow
}

$branch=(& git branch --show-current).Trim()
if(-not $branch){ $branch="main" }

Write-Host ""
Write-Host ("Enviando para origin/" + $branch + "...") -ForegroundColor Cyan

& git push origin $branch
if($LASTEXITCODE -ne 0){ throw "Falha no git push." }

Write-Host ""
Write-Host "==============================================================" -ForegroundColor Green
Write-Host " SUCESSO - v2.19.23 ENVIADA PARA O GITHUB" -ForegroundColor Green
Write-Host "==============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Agora use a planilha APONTAMENTOS_2026-08-10_IMPORTACAO_AREAS_REFERENCIAS.xlsx." -ForegroundColor White
Write-Host ""
& git log -1 --oneline
