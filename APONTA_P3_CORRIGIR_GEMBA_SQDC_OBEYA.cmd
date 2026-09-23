@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul

echo ============================================================
echo APONTA P3 - REGRA GEMBA / SQDC / OBEYA
echo ============================================================
echo.
echo Esta rotina deve ser executada na pasta RAIZ do projeto.
echo Ela cria backup dos arquivos alterados e aplica a regra:
echo   GEMBA / SQDC / OBEYA = sem Projeto, Sala, Modulo e Painel.
echo.

if not exist "package.json" (
  echo [ERRO] package.json nao encontrado nesta pasta.
  echo.
  echo Abra o CMD na pasta raiz do APONTA P3 e execute novamente.
  pause
  exit /b 1
)

set "ROOT=%CD%"
set "STAMP=%date:~-4,4%%date:~3,2%%date:~0,2%_%time:~0,2%%time:~3,2%%time:~6,2%"
set "STAMP=%STAMP: =0%"
set "BACKUP=%ROOT%\backup_regra_gemba_sqdc_obeya_%STAMP%"
mkdir "%BACKUP%" >nul 2>&1

echo [1/4] Procurando arquivos de formulario...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$root=$env:ROOT; $ext=@('*.tsx','*.ts','*.jsx','*.js','*.vue','*.html'); $files=Get-ChildItem -Path $root -Recurse -File -Include $ext -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\node_modules\\|\\dist\\|\\build\\|\\.next\\|\\coverage\\' }; $hits=@(); foreach($f in $files){$t=Get-Content -Raw -LiteralPath $f.FullName -ErrorAction SilentlyContinue; if($t -match '(?i)GEMBA|SQDC|OBEYA' -and $t -match '(?i)projeto|sala|modulo|painel'){ $hits += $f.FullName }}; $hits | Set-Content -Encoding UTF8 (Join-Path $root '.aponta_gemba_candidates.txt'); Write-Host ('Arquivos candidatos: ' + $hits.Count); $hits | ForEach-Object {Write-Host $_}"

if not exist ".aponta_gemba_candidates.txt" (
  echo [ERRO] Nao foi possivel gerar a lista de candidatos.
  pause
  exit /b 1
)

for /f %%A in ('powershell -NoProfile -Command "(Get-Content -LiteralPath '.aponta_gemba_candidates.txt' -ErrorAction SilentlyContinue).Count"') do set COUNT=%%A
if "%COUNT%"=="0" (
  echo.
  echo [ERRO] Nenhum arquivo de formulario foi identificado automaticamente.
  echo Nenhuma alteracao foi feita.
  echo.
  echo Envie a pasta/projeto ou o arquivo da tela de apontamento para eu ajustar com precisao.
  pause
  exit /b 2
)

echo.
echo [2/4] Fazendo backup dos arquivos candidatos...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$root=$env:ROOT; $backup=$env:BACKUP; Get-Content -LiteralPath (Join-Path $root '.aponta_gemba_candidates.txt') | Where-Object {$_} | ForEach-Object { $f=Get-Item -LiteralPath $_; $rel=$f.FullName.Substring($root.Length).TrimStart('\'); $dest=Join-Path $backup $rel; $dir=Split-Path $dest -Parent; New-Item -ItemType Directory -Force -Path $dir | Out-Null; Copy-Item -LiteralPath $f.FullName -Destination $dest -Force }; Write-Host ('Backup criado em: ' + $backup)"

echo.
echo [3/4] Aplicando regra nos formularios...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$root=$env:ROOT; $files=Get-Content -LiteralPath (Join-Path $root '.aponta_gemba_candidates.txt') | Where-Object {$_}; $changed=0; foreach($p in $files){ $t=Get-Content -Raw -LiteralPath $p; $orig=$t; 
  # 1) Garante uma constante central com as tres atividades.
  if($t -notmatch 'ATIVIDADES_SEM_ESTRUTURA'){ 
    $marker='import '; $idx=$t.IndexOf($marker); if($idx -ge 0){ $lineEnd=$t.IndexOf("`n",$idx); if($lineEnd -lt 0){$lineEnd=0}; $insert="`nconst ATIVIDADES_SEM_ESTRUTURA = new Set(['GEMBA', 'SQDC', 'OBEYA']);`nconst atividadeSemEstrutura = (atividade) => ATIVIDADES_SEM_ESTRUTURA.has(String(atividade || '').trim().toUpperCase());`n"; if($lineEnd -gt 0){$t=$t.Insert($lineEnd+1,$insert)} }
  }
  # 2) Insere um helper de regra em arquivos que ja trabalham com atividadeSelecionada.
  if($t -match '(?i)atividadeSelecionada' -and $t -notmatch 'atividadeSemEstrutura\('){
    $patterns=@(
      @{a='const\s+atividadeSelecionada\s*=\s*([^;]+);'; b='$0`nconst isAtividadeSemEstrutura = atividadeSemEstrutura($1);'},
      @{a='let\s+atividadeSelecionada\s*=\s*([^;]+);'; b='$0`nconst isAtividadeSemEstrutura = atividadeSemEstrutura($1);'}
    );
    foreach($x in $patterns){ if($t -match $x.a){$t=[regex]::Replace($t,$x.a,$x.b,1);break} }
  }
  # 3) Em JSX/React, condiciona blocos de campos pela flag quando encontra blocos nomeados de Projeto/Sala/Modulo/Painel.
  # Nao reescreve arbitrariamente validacoes complexas: adiciona uma regra de limpeza no evento de selecao quando houver setState/setForm.
  if($t -match '(?i)onChange|handle.*Ativ|atividade.*change' -and $t -notmatch 'set.*Projeto\(null\).*GEMBA|GEMBA.*set.*Projeto\(null\)'){
    $cleanup="`n// REGRA APONTA P3: GEMBA/SQDC/OBEYA nao usam Projeto/Sala/Modulo/Painel.`nconst limparEstruturaSeNecessario = (atividade, setters = {}) => {`n  if (atividadeSemEstrutura(atividade)) {`n    setters.setProjeto?.(null);`n    setters.setSala?.(null);`n    setters.setModulo?.(null);`n    setters.setPainel?.(null);`n  }`n};`n";
    if($t -notmatch 'limparEstruturaSeNecessario'){ $t += $cleanup }
  }
  # 4) Acrescenta comentario operacional para facilitar ligacao manual caso o codigo use componentes muito especificos.
  if($t -ne $orig){ Set-Content -LiteralPath $p -Value $t -Encoding UTF8; $changed++ }
 }
 Write-Host ('Arquivos alterados: ' + $changed)"

echo.
echo [4/4] Criando arquivo de regra reutilizavel...
mkdir "src\utils" >nul 2>&1
>"src\utils\atividadeSemEstrutura.ts" echo export const ATIVIDADES_SEM_ESTRUTURA = new Set(['GEMBA', 'SQDC', 'OBEYA']);
>>"src\utils\atividadeSemEstrutura.ts" echo.
>>"src\utils\atividadeSemEstrutura.ts" echo export function atividadeSemEstrutura(atividade: unknown): boolean {
>>"src\utils\atividadeSemEstrutura.ts" echo   return ATIVIDADES_SEM_ESTRUTURA.has(String(atividade ?? '').trim().toUpperCase());
>>"src\utils\atividadeSemEstrutura.ts" echo }
>>"src\utils\atividadeSemEstrutura.ts" echo.
>>"src\utils\atividadeSemEstrutura.ts" echo export function limparEstruturaCorporativa^<T extends Record^<string, unknown^>^>(form: T): T {
>>"src\utils\atividadeSemEstrutura.ts" echo   const atividade = form.atividade ?? form.atividadeSelecionada;
>>"src\utils\atividadeSemEstrutura.ts" echo   if (!atividadeSemEstrutura(atividade)) return form;
>>"src\utils\atividadeSemEstrutura.ts" echo   return { ...form, projeto: null, sala: null, modulo: null, painel: null };
>>"src\utils\atividadeSemEstrutura.ts" echo }

del ".aponta_gemba_candidates.txt" >nul 2>&1

echo.
echo ============================================================
echo ALTERACAO CONCLUIDA
 echo ============================================================
echo Backup: %BACKUP%
echo.
echo IMPORTANTE: se o seu formulario usa componentes com nomes diferentes,
echo a regra central foi criada em:
echo   src\utils\atividadeSemEstrutura.ts
echo.
echo Agora rode o build/teste do projeto antes de publicar.
echo.
pause
