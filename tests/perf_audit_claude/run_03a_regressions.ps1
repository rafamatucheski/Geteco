# GETECO-PERF-03A — regressões de loading/menu/abertura/SouthPort/emergência,
# em sequência, um processo Godot por vez. Uso: -Label before|after -Path <árvore>
param([string]$Label = "after", [string]$Path = "D:/geteco/game")
$godot = 'D:/Downloads Chrome/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
$out = "D:/geteco/game/tests/perf_audit_claude/results/03a_regressions_$Label"
New-Item -ItemType Directory -Force "$out/appdata" | Out-Null
$env:APPDATA = "$out/appdata"
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
  $sw = [Diagnostics.Stopwatch]::StartNew()
  & $godot --path $Path --script "res://tests/$t.gd" 2>&1 | Out-File -Encoding utf8 "$out/$t.txt"
  $code = $LASTEXITCODE
  $errors = (Select-String -Path "$out/$t.txt" -Pattern 'SCRIPT ERROR|Assertion failed|FAIL ' -SimpleMatch:$false -ErrorAction SilentlyContinue).Count
  $rows += [pscustomobject]@{ test = $t; exit = $code; error_lines = $errors; seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1) }
  "$t exit=$code error_lines=$errors"
}
Push-Location $Path
python tools/check_references.py *> "$out/check_references.txt"
$rows += [pscustomobject]@{ test = 'tools/check_references.py'; exit = $LASTEXITCODE; error_lines = 0; seconds = 0 }
Pop-Location
$rows | ConvertTo-Json | Out-File -Encoding utf8 "$out/summary.json"
