# GETECO-PERF-02B — sessões A/B de rota com o MESMO coletor.
# antes  = worktree de 9bd10e0 + mudanças locais de outras sessões (sem 02B)
# depois = árvore principal (9bd10e0 + mudanças locais + 02B)
# Rodam em sequência, nunca em paralelo, com APPDATA isolado por execução.
# Uso: powershell -File tests/perf_audit_claude/run_02b_ab_sessions.ps1 -Worktree <caminho> [-Repeat 2]
param([Parameter(Mandatory = $true)][string]$Worktree, [int]$Repeat = 2)
$godot = 'D:/Downloads Chrome/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
$main = 'D:/geteco/game'
$results = "$main/tests/perf_audit_claude/results"
# O coletor atualizado não existe na worktree: copiar só ele.
New-Item -ItemType Directory -Force "$Worktree/tests/perf_audit_claude" | Out-Null
Copy-Item "$main/tests/perf_audit_claude/perf_audit_session.gd" "$Worktree/tests/perf_audit_claude/perf_audit_session.gd" -Force
for ($i = 1; $i -le $Repeat; $i++) {
  foreach ($side in @(@{ label = "before"; path = $Worktree }, @{ label = "after"; path = $main })) {
    $run = "02b_ab_$($side.label)_$i"
    $dir = "$results/$run"
    New-Item -ItemType Directory -Force "$dir/appdata" | Out-Null
    $env:APPDATA = "$dir/appdata"
    "tree=$($side.path) head=$(git -C $side.path rev-parse --short HEAD) start=$(Get-Date -Format o)" | Out-File -Encoding utf8 "$dir/run_info.txt"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    # A worktree grava o relatório em seu próprio res://; o resultado é copiado depois.
    & $godot --path $side.path --script res://tests/perf_audit_claude/perf_audit_session.gd -- "run=$run" --no-budget-timing 2>&1 | Out-File -Encoding utf8 "$dir/godot_stdout.txt"
    "exit=$LASTEXITCODE wall_s=$($sw.Elapsed.TotalSeconds)" | Out-File -Append -Encoding utf8 "$dir/run_info.txt"
    if ($side.path -ne $main) {
      $produced = "$($side.path)/tests/perf_audit_claude/results/$run"
      foreach ($file in @('report.json', 'frames.csv')) {
        if (Test-Path "$produced/$file") { Copy-Item "$produced/$file" "$dir/$file" -Force }
      }
    }
    "$run exit=$LASTEXITCODE wall_s=$([math]::Round($sw.Elapsed.TotalSeconds, 1))"
  }
}
