# GETECO-PERF-03A — regressões de loading/menu/abertura/SouthPort/emergência,
# em sequência, um processo Godot por vez. Uso: -Label before|after -Path <árvore>
#
# GETECO-PERF-03A-R2: cada teste agora roda via Invoke-GodotTestLocked.ps1
# (mesmo diretório) em vez de "& $godot" direto — isso acrescenta exclusão
# mútua entre processos (mesmo entre cópias A/B em worktrees diferentes,
# via Mutex nomeado do Windows) e um timeout externo ao motor, que mata só
# o processo que ESTE script iniciou (nunca por nome). Sem isso, um teste
# que trava num loop de erro (já aconteceu nesta rodada) não termina por
# conta própria e pode rodar concorrente com outro processo de teste.
param([string]$Label = "after", [string]$Path = "D:/geteco/game", [int]$TimeoutSec = 150)
$runnerDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$locked = Join-Path $runnerDir "Invoke-GodotTestLocked.ps1"
$out = "D:/geteco/game/tests/perf_audit_claude/results/03a_regressions_$Label"
New-Item -ItemType Directory -Force $out | Out-Null
"tree=$Path head=$(git -C $Path rev-parse --short HEAD)" | Out-File -Encoding utf8 "$out/tree_info.txt"
$tests = @(
  'test_menu_flow_integration', 'test_continue_skips_opening', 'test_opening_loading', 'test_opening_cutscene_runtime',
  'test_legacy_save_route', 'test_south_port', 'test_south_port_production', 'test_harbor_emergency_dispatch',
  'test_harbor_local_streets', 'test_region_travel', 'test_continuous_save', 'test_pedestrian_life_routines',
  'test_pedestrian_render_lod', 'test_garage_weapon_restrictions', 'test_combat_audio', 'test_vehicle_audio_preparation',
  'test_vehicle_geometry_cache', 'test_vehicle_mesh_batcher', 'test_presentation_budget', 'test_vehicle_presentation_streaming',
  'test_resident_vehicle_preparation', 'test_emergency_pool_preparation', 'test_prepared_police_vehicle'
)
$rows = @()
foreach ($t in $tests) {
  $r = & $locked -ScriptPath "res://tests/$t.gd" -Path $Path -Run $t -OutDir $out -TimeoutSec $TimeoutSec
  $code = if ($r.rejected) { -2 } else { $r.exit_code }
  $errors = if (Test-Path "$out/$t.txt") { (Select-String -Path "$out/$t.txt" -Pattern 'SCRIPT ERROR|Assertion failed|FAIL ' -SimpleMatch:$false -ErrorAction SilentlyContinue).Count } else { -1 }
  $seconds = if ($r.wall_s) { $r.wall_s } else { 0 }
  $rows += [pscustomobject]@{ test = $t; exit = $code; error_lines = $errors; seconds = $seconds; timed_out = [bool]$r.timed_out; rejected = [bool]$r.rejected }
  "$t exit=$code error_lines=$errors timed_out=$($r.timed_out) rejected=$($r.rejected)"
}
Push-Location $Path
python tools/check_references.py *> "$out/check_references.txt"
$rows += [pscustomobject]@{ test = 'tools/check_references.py'; exit = $LASTEXITCODE; error_lines = 0; seconds = 0 }
Pop-Location
$rows | ConvertTo-Json | Out-File -Encoding utf8 "$out/summary.json"
