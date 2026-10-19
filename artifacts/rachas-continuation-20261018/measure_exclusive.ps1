$ErrorActionPreference = 'Stop'
$enginePath = 'D:/Downloads Chrome/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe'
$workspacePath = 'D:/geteco/game'
$deadline = (Get-Date).AddSeconds(180)
$observations = [System.Collections.Generic.List[object]]::new()
do {
    $otherEngines = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'Godot|ffmpeg' })
    if ($otherEngines.Count -eq 0) { break }
    if ((Get-Date) -ge $deadline) {
        Write-Output 'PERF_WAIT_EXPIRED: another session still uses the engine; no benchmark launched.'
        exit 2
    }
    Start-Sleep -Seconds 2
} while ($true)
$startedAt = (Get-Date).ToUniversalTime().ToString('o')
$runProcess = Start-Process -FilePath $enginePath -WindowStyle Hidden -WorkingDirectory $workspacePath -ArgumentList @('--path','D:/geteco/game','--script','res://artifacts/rachas-implementation-20261018/measure_design.gd','--','--no-save') -RedirectStandardOutput "$workspacePath/output/drag-polish-after-20261018.log" -RedirectStandardError "$workspacePath/output/drag-polish-after-20261018.stderr.log" -PassThru
Write-Output "PERF_STARTED wrapper=$($runProcess.Id) at=$startedAt"
while (-not $runProcess.HasExited) {
    $engines = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'Godot|ffmpeg' })
    foreach ($entry in $engines) {
        if ($entry.ProcessId -ne $runProcess.Id -and $entry.ParentProcessId -ne $runProcess.Id) {
            $observations.Add(@{at=(Get-Date).ToUniversalTime().ToString('o');pid=$entry.ProcessId;command=$entry.CommandLine})
        }
    }
    Start-Sleep -Seconds 2
    $runProcess.Refresh()
}
$runProcess.WaitForExit()
@{started=$startedAt;ended=(Get-Date).ToUniversalTime().ToString('o');external_observations=$observations.ToArray();sample_seconds=2;exit_code=$runProcess.ExitCode} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath "$workspacePath/artifacts/rachas-continuation-20261018/performance-processes.json"
Write-Output "PERF_DONE external_observations=$($observations.Count) exit=$($runProcess.ExitCode)"
exit $runProcess.ExitCode
