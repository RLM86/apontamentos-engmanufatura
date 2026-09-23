$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$OldJs = Join-Path $Root "app-v2.19.24.js"
$NewJs = Join-Path $Root "app-v2.19.25.js"
$Index = Join-Path $Root "index.html"
$Sw = Join-Path $Root "sw.js"
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$Backup = Join-Path $Root ("BACKUP_ANTES_ATIVIDADE_MACRO_v2.19.25_" + $Stamp)
$Log = Join-Path $Root ("ATUALIZACAO_ATIVIDADE_MACRO_v2.19.25_" + $Stamp + ".log")

function Log([string]$Message) {
    $line = ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message)
    $line | Tee-Object -FilePath $Log -Append
}

function Replace-Exact([string]$Text, [string]$Old, [string]$New, [string]$Description) {
    if (-not $Text.Contains($Old)) {
        throw "Ponto de alteracao nao encontrado: $Description"
    }
    Log "OK: $Description"
    return $Text.Replace($Old, $New)
}

function Replace-RegexOptional([string]$Text, [string]$Pattern, [string]$Replacement, [string]$Description) {
    $rx = [regex]::new($Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($rx.IsMatch($Text)) {
        Log "OK opcional: $Description"
        return $rx.Replace($Text, $Replacement)
    }
    Log "Aviso: ponto opcional nao encontrado: $Description"
    return $Text
}

Log "Inicio da atualizacao."

foreach ($f in @($OldJs,$Index,$Sw)) {
    if (-not (Test-Path $f)) {
        throw "Arquivo obrigatorio nao encontrado: $f. Extraia este pacote na pasta raiz do APONT MAN P3."
    }
}

New-Item -ItemType Directory -Path $Backup | Out-Null
Copy-Item $OldJs (Join-Path $Backup "app-v2.19.24.js") -Force
Copy-Item $Index (Join-Path $Backup "index.html") -Force
Copy-Item $Sw (Join-Path $Backup "sw.js") -Force
Log "Backup criado em $Backup"

$Js = Get-Content $OldJs -Raw -Encoding UTF8

# 1. Estrutura em memoria
$Js = Replace-Exact $Js `
'let macroActivities = [];' `
"let macroActivities = [];`r`n  let disciplinaMacroMap = [];" `
"criar cache disciplinaMacroMap"

# 2. Corrige a ordem de retorno do Promise.all e inclui o mapa disciplina -> macro.
# O app v2.19.24 ja consultava macro_atividades, mas a variavel mac estava na posicao errada.
$Js = Replace-Exact $Js `
'const [p, pr, ac, ho, wa, ms, mo, ro, pt, aal, pm, pro, prm, pri, prim, mac] = await Promise.all([' `
'const [p, pr, ac, mac, dmm, ho, wa, ms, mo, ro, pt, aal, pm, pro, prm, pri, prim] = await Promise.all([' `
"corrigir ordem do carregamento de macro_atividades"

$Js = Replace-Exact $Js `
'sb.from("macro_atividades").select("*").order("ordem"),' `
"sb.from(""macro_atividades"").select(""*"").order(""ordem""),`r`n      sb.from(""disciplina_macro_map"").select(""*"")," `
"carregar disciplina_macro_map"

$Js = Replace-Exact $Js `
'macroActivities = mac.data || [];' `
"macroActivities = mac.data || [];`r`n    disciplinaMacroMap = dmm.data || [];" `
"armazenar mapa de disciplinas"

# 3. Funcoes centrais
$ActivityMacroPattern = 'function activityMacro\(id\)\s*\{.*?return macro \? macro\.nome : "";\s*\}'
$ActivityMacroReplacement = @'
function macroByDiscipline(discipline){
  const key = String(discipline || "").trim().toLowerCase();
  if(!key) return null;

  const link = disciplinaMacroMap.find(item =>
    String(item.disciplina || "").trim().toLowerCase() === key
  );

  if(!link) return null;

  return macroActivities.find(item =>
    String(item.id) === String(link.macro_atividade_id)
  ) || null;
}

function activityMacro(id){
  const activity = activities.find(a => String(a.id) === String(id));
  if(!activity) return "";

  let macro = null;

  if(activity.macro_atividade_id){
    macro = macroActivities.find(
      m => String(m.id) === String(activity.macro_atividade_id)
    ) || null;
  }

  if(!macro){
    macro = macroByDiscipline(activity.discipline_name);
  }

  return macro ? macro.nome : "";
}

function activityMacroCode(id){
  const activity = activities.find(a => String(a.id) === String(id));
  if(!activity) return "";

  let macro = null;

  if(activity.macro_atividade_id){
    macro = macroActivities.find(
      m => String(m.id) === String(activity.macro_atividade_id)
    ) || null;
  }

  if(!macro){
    macro = macroByDiscipline(activity.discipline_name);
  }

  return macro ? (macro.codigo || "") : "";
}

function macroNameByDiscipline(discipline){
  const macro = macroByDiscipline(discipline);
  return macro ? macro.nome : "";
}

function ensureMacroFieldForDisciplineElement(el){
  if(!el || el.dataset.macroUiInstalled === "1") return;
  el.dataset.macroUiInstalled = "1";

  const wrapper = document.createElement("div");
  wrapper.className = "activity-macro-auto";
  wrapper.style.marginTop = "8px";

  const label = document.createElement("label");
  label.textContent = "Atividade Macro";
  label.style.display = "block";
  label.style.fontWeight = "600";
  label.style.marginBottom = "4px";

  const input = document.createElement("input");
  input.type = "text";
  input.readOnly = true;
  input.tabIndex = -1;
  input.placeholder = "Definida automaticamente pela disciplina";
  input.style.width = "100%";
  input.style.opacity = "0.9";

  wrapper.appendChild(label);
  wrapper.appendChild(input);

  el.insertAdjacentElement("afterend", wrapper);

  const refresh = () => {
    input.value = macroNameByDiscipline(el.value);
  };

  el.addEventListener("change", refresh);
  el.addEventListener("input", refresh);
  el._refreshMacroAuto = refresh;
  refresh();
}

function installMacroAutoUi(){
  const selectors = [
    "#activityDiscipline",
    "#editActivityDiscipline",
    "#newActivityDiscipline",
    'select[id*="ActivityDiscipline"]',
    'input[id*="ActivityDiscipline"]'
  ];

  document.querySelectorAll(selectors.join(",")).forEach(ensureMacroFieldForDisciplineElement);
}

function refreshMacroAutoUi(){
  installMacroAutoUi();
  document.querySelectorAll('[data-macro-ui-installed="1"]').forEach(el => {
    if(typeof el._refreshMacroAuto === "function") el._refreshMacroAuto();
  });
}
'@

$rxMacro = [regex]::new($ActivityMacroPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
if (-not $rxMacro.IsMatch($Js)) {
    throw "Funcao activityMacro nao localizada. Atualizacao interrompida para proteger o aplicativo."
}
$Js = $rxMacro.Replace($Js, $ActivityMacroReplacement, 1)
Log "OK: funcoes de Atividade Macro instaladas"

# 4. Atualiza a UI depois do carregamento base
$Js = Replace-Exact $Js `
'disciplinaMacroMap = dmm.data || [];' `
"disciplinaMacroMap = dmm.data || [];`r`n    setTimeout(() => refreshMacroAutoUi(), 0);" `
"atualizar campo automatico apos carregar dados"

# 5. Exportacao da lista de atividades: adiciona codigo e nome da macro.
$Js = Replace-Exact $Js `
'        "Disciplina":activity.discipline_name||"",`r`n        "Natureza":activity.nature||"",' `
'        "Disciplina":activity.discipline_name||"",`r`n        "Código Macro":activityMacroCode(activity.id),`r`n        "Atividade Macro":activityMacro(activity.id),`r`n        "Natureza":activity.nature||"",' `
"adicionar Macro na exportacao das atividades"

$Js = Replace-Exact $Js `
'        "Atividade",`r`n        "Disciplina",`r`n        "Natureza",' `
'        "Atividade",`r`n        "Disciplina",`r`n        "Código Macro",`r`n        "Atividade Macro",`r`n        "Natureza",' `
"adicionar cabecalhos Macro no Excel"

# Ajuste de filtro da planilha, quando presente.
$Js = $Js.Replace('activitySheet["!autofilter"]={ref:`A1:I${Math.max(rows.length+1,2)}`};',
                  'activitySheet["!autofilter"]={ref:`A1:K${Math.max(rows.length+1,2)}`};')

# 6. Instrucoes do modelo de importacao.
$InstructionAnchor = '      ["Atividade","Campo obrigatÃ³rio e Ãºnico."],'
if ($Js.Contains($InstructionAnchor)) {
    $Js = $Js.Replace(
      $InstructionAnchor,
      $InstructionAnchor + "`r`n      [""Atividade Macro"",""Preenchida automaticamente conforme a Disciplina. Nao editar manualmente.""],"
    )
    Log "OK: instrucao de Atividade Macro incluida no modelo Excel"
} else {
    Log "Aviso: bloco de instrucoes do Excel nao localizado; importacao continua funcional pelo gatilho do banco."
}

# 7. Exportacoes de relatorio/CSV: inclui Macro sempre que houver Disciplina por activityDiscipline().
# Fazemos apenas substituicoes reconheciveis e sem alterar o fluxo dos relatorios.
$Js = Replace-RegexOptional $Js `
'("Disciplina"\s*:\s*activityDiscipline\(([^)]+)\)\s*,)' `
'$1`r`n        "Código Macro":activityMacroCode($2),`r`n        "Atividade Macro":activityMacro($2),' `
"adicionar Macro aos objetos de exportacao de relatorios"

# 8. Importacao: reconhece a coluna Atividade Macro, mas o banco permanece fonte da verdade.
$ImportAnchor = '      const disciplineName=String(workbookValue(row,["Disciplina","discipline_name"])||"").trim();'
if ($Js.Contains($ImportAnchor)) {
    $Js = $Js.Replace(
      $ImportAnchor,
      $ImportAnchor + "`r`n      const macroActivityName=String(workbookValue(row,[""Atividade Macro"",""Macro Atividade"",""macro_atividade""])||"""").trim();"
    )
    Log "OK: coluna Atividade Macro reconhecida na importacao"

    $PushAnchor = '        discipline_name:disciplineName,'
    if ($Js.Contains($PushAnchor)) {
        $Js = $Js.Replace(
          $PushAnchor,
          $PushAnchor + "`r`n        macro_activity_name:macroActivityName,"
        )
        Log "OK: valor Macro preservado durante leitura da planilha"
    }
}

# 9. Marca a versao.
$Js = "/* APONT MAN P3 v2.19.25 - Atividade Macro completa */`r`n" + $Js
Set-Content -Path $NewJs -Value $Js -Encoding UTF8
Log "app-v2.19.25.js criado"

# 10. Atualiza index.html para apontar para a nova versao.
$IndexText = Get-Content $Index -Raw -Encoding UTF8
if ($IndexText -match 'app-v2\.19\.24\.js(\?build=\d+)?') {
    $IndexText = [regex]::Replace(
      $IndexText,
      'app-v2\.19\.24\.js(\?build=\d+)?',
      'app-v2.19.25.js?build=2216',
      1
    )
} else {
    throw "Referencia app-v2.19.24.js nao encontrada em index.html."
}
Set-Content -Path $Index -Value $IndexText -Encoding UTF8
Log "index.html atualizado"

# 11. Atualiza service worker para invalidar cache e carregar novo JS.
$SwText = Get-Content $Sw -Raw -Encoding UTF8
$SwText = $SwText -replace 'app-v2\.19\.24\.js\?build=\d+', 'app-v2.19.25.js?build=2216'
$SwText = $SwText -replace 'app-v2\.19\.24\.js', 'app-v2.19.25.js'
$SwText = $SwText -replace 'aponta-horas-v2\.19\.24[^"''\r\n]*', 'aponta-horas-v2.19.25-atividade-macro'
Set-Content -Path $Sw -Value $SwText -Encoding UTF8
Log "sw.js atualizado"

# 12. Validacoes finais.
$FinalJs = Get-Content $NewJs -Raw -Encoding UTF8
foreach ($required in @(
    'disciplina_macro_map',
    'macroByDiscipline',
    'activityMacroCode',
    '"Atividade Macro"',
    '"Código Macro"'
)) {
    if (-not $FinalJs.Contains($required)) {
        throw "Validacao final falhou: $required nao encontrado no novo JS."
    }
}

Log "Validacao final OK."
Log "Atualizacao v2.19.25 concluida."
Write-Host ""
Write-Host "ATUALIZACAO CONCLUIDA COM SUCESSO." -ForegroundColor Green
Write-Host "Novo arquivo: app-v2.19.25.js" -ForegroundColor Green
Write-Host "Backup: $Backup" -ForegroundColor Cyan
Write-Host ""
Write-Host "IMPORTANTE:" -ForegroundColor Yellow
Write-Host "1. O banco Supabase deve permanecer com macro_atividades, disciplina_macro_map e o trigger ja configurado."
Write-Host "2. Publique/suba index.html, sw.js e app-v2.19.25.js pelo procedimento normal do APONT MAN."
Write-Host "3. Depois force Ctrl+F5 ou limpe o cache do aplicativo."
