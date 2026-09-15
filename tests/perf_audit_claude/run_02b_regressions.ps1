# GETECO-PERF-02B — regressões de veículos/apresentação, em sequência.
# Uso: powershell -File tests/perf_audit_claude/run_02b_regressions.ps1 -Label before|after
# Cada teste roda em processo próprio, renderizado, com APPDATA isolado.
param([string]$Label = "before")
$godot = 'D:/Downloads Chrome/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
$out = "D:/geteco/game/tests/perf_audit_claude/results/02b_regressions_$Label"
New-Item -ItemType Directory -Force "$out/appdata" | Out-Null
$env:APPDATA = "$out/appdata"
$tests = @(
  'test_vehicle_geometry_cache', 'test_vehicle_mesh_batcher', 'test_presentation_budget',
  'test_vehicle_presentation_streaming', 'test_resident_vehicle_preparation', 'test_traffic_render_budget',
  'test_emergency_pool_preparation', 'test_prepared_police_vehicle', 'test_sculpted_vehicle_fleet',
  'test_wheel_body_clearance', 'test_vehicle_wheel_steering', 'test_native_vehicle_doors',
  'test_coupe_crash_lab', 'test_traffic_vehicle_repair_clears_skid', 'test_emergency_lightbars',
  'test_vehicle_entry_exit', 'test_motorcycle_geometry', 'test_vehicle_lamp_origins',
  'test_vehicle_crash_and_explosion', 'test_in_game_fleet_integration', 'test_region_travel',
  'test_continuous_save', 'test_menu_flow_integration'
)
$rows = @()
foreach ($t in $tests) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  # Out-File UTF-8: o redirecionamento *> do PowerShell 5 grava UTF-16 e esconde
  # as linhas FAIL de grep/Select-String em logs anteriores.
  & $godot --path D:/geteco/game --script "res://tests/$t.gd" 2>&1 | Out-File -Encoding utf8 "$out/$t.txt"
  $code = $LASTEXITCODE
  $errors = (Select-String -Path "$out/$t.txt" -Pattern 'SCRIPT ERROR|Assertion failed|FAIL ' -SimpleMatch:$false).Count
  $rows += [pscustomobject]@{ test = $t; exit = $code; error_lines = $errors; seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1) }
  "$t exit=$code error_lines=$errors"
}
Push-Location D:/geteco/game
python tools/check_references.py *> "$out/check_references.txt"
$rows += [pscustomobject]@{ test = 'tools/check_references.py'; exit = $LASTEXITCODE; error_lines = 0; seconds = 0 }
Pop-Location
$rows | ConvertTo-Json | Out-File -Encoding utf8 "$out/summary.json"
