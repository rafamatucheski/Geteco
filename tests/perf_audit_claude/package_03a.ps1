# GETECO-PERF-03A — empacota o relatório completo + diff + coletores + JSON/CSV
# relevantes + manifesto, num ZIP pequeno. Exclui appdata/saves/caches/logs de
# importação sem valor de medição.
$root = 'D:/geteco/game'
$stage = "$root/tests/perf_audit_claude/results/03a_package_stage"
Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $stage | Out-Null

# 1. Relatório completo
Copy-Item "$root/docs/history/GETECO_PERF_03A_LOADING_2026-09-15.md" "$stage/" -Force

# 2. Diff de produção (os 4 arquivos desta rodada)
git -C $root diff -- world/harbor/HarborSouthPort.gd world/harbor/HarborPreview.gd world/harbor/HarborGame.gd geodata/roads/RoadLighting.gd > "$stage/production_03a.diff"

# 3. Coletores/scripts criados nesta rodada
New-Item -ItemType Directory -Force "$stage/scripts" | Out-Null
Copy-Item "$root/tests/perf_audit_claude/measure_loading_03a.gd" "$stage/scripts/" -Force
Copy-Item "$root/tests/perf_audit_claude/probe_emergency_director_03a.gd" "$stage/scripts/" -Force
Copy-Item "$root/tests/perf_audit_claude/probe_south_port_positions_03a.gd" "$stage/scripts/" -Force
Copy-Item "$root/tests/perf_audit_claude/run_03a_regressions.ps1" "$stage/scripts/" -Force
Copy-Item "$root/tests/perf_audit_claude/package_03a.ps1" "$stage/scripts/" -Force

# 4. JSON/CSV das execuções relevantes (não appdata/saves/import logs)
$runs = @(
  '03a_fresh_baseline_new', '03a_before_new_2', '03a_before_new_3',
  '03a_after_fixed_new_1', '03a_after_fixed_new_2', '03a_after_fixed_new_3',
  'probe_emergency_director',
  '03a_priority_risk_checks',
  '03a_positions_before', '03a_positions_after',
  '03a_regressions_before', '03a_regressions_after_fixed',
  '03a_continue_before_fixed', '03a_continue_before_fixed_2', '03a_continue_before_fixed_3',
  '03a_continue_after_fixed', '03a_continue_after_fixed_2', '03a_continue_after_fixed_3',
  '03a_fixture_save'
)
foreach ($r in $runs) {
  $src = "$root/tests/perf_audit_claude/results/$r"
  if (-not (Test-Path $src)) { continue }
  $dst = "$stage/results/$r"
  New-Item -ItemType Directory -Force $dst | Out-Null
  Get-ChildItem $src -File -Recurse | Where-Object {
    $_.FullName -notmatch '\\appdata\\' -and $_.FullName -notmatch '\\saves\\' -and
    $_.Name -ne '_import.log' -and $_.Extension -ne '.log'
  } | ForEach-Object {
    $rel = $_.FullName.Substring($src.Length).TrimStart('\')
    $target = Join-Path $dst $rel
    New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
    Copy-Item $_.FullName $target -Force
  }
}

# 5. Manifesto: revisões, HEAD, comandos
@"
GETECO-PERF-03A — manifesto do pacote
======================================
HEAD (main, durante toda a rodada): $(git -C $root rev-parse HEAD)
Worktree "antes" (git worktree add --detach): commit 45ba477 + tests/perf_audit_claude/results/02b_baseline_state/local_changes_others.diff
  aplicado só a: characters/Player.gd, systems/RegionTravel.gd, systems/interiors/ExteriorOcclusion.gd,
  world/harbor/HarborArrivalStop.gd, world/harbor/HarborGame.gd, world/harbor/campaign/HarborArrivalMission.gd
Arquivos de produção alterados nesta rodada (03A): world/harbor/HarborSouthPort.gd, world/harbor/HarborPreview.gd, world/harbor/HarborGame.gd

Comandos executados (um processo Godot por vez, sem push):
  `$env:APPDATA = "<projeto>/tests/perf_audit_claude/results/<run>/appdata"
  & Godot..._console.exe --path <árvore> --script res://tests/perf_audit_claude/measure_loading_03a.gd -- run=<run> mode=new|continue|produce_save [save_fixture=<pasta>]
  & Godot..._console.exe --path <árvore> --script res://tests/perf_audit_claude/probe_emergency_director_03a.gd -- run=<run>
  powershell -File tests/perf_audit_claude/run_03a_regressions.ps1 -Label before|after -Path <árvore>

git worktree add --detach <caminho> 45ba477
git apply --whitespace=nowarn --include=<arquivos> local_changes_others.diff
Godot..._console.exe --headless --path <worktree> --import

Excluído deste pacote: appdata/ (user data isolado de cada execução), saves/,
logs de importação (_import.log) e outros *.log sem valor de medição.
"@ | Out-File -Encoding utf8 "$stage/MANIFEST.txt"

$zip = "$root/tests/perf_audit_claude/results/GETECO_PERF_03A_package.zip"
Remove-Item $zip -ErrorAction SilentlyContinue
Compress-Archive -Path "$stage/*" -DestinationPath $zip -CompressionLevel Optimal
$size = (Get-Item $zip).Length / 1MB
"pacote: $zip ($([math]::Round($size,2)) MiB)"
