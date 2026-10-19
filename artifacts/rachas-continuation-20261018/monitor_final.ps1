$ErrorActionPreference = 'Stop'
$observations = [System.Collections.Generic.List[object]]::new()
$deadline = (Get-Date).AddSeconds(300)
$owned = @()
do {
    $owned = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'Godot' -and $_.CommandLine -match 'rachas-implementation-20261018/measure_design.gd' })
    if ($owned.Count -gt 0) { break }
    Start-Sleep -Seconds 1
} while ((Get-Date) -lt $deadline)
if ($owned.Count -eq 0) { throw 'Final benchmark process was not found.' }
$started = (Get-Date).ToUniversalTime().ToString('o')
do {
    $engines = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'Godot|ffmpeg' })
    $owned = @($engines | Where-Object { $_.CommandLine -match 'rachas-implementation-20261018/measure_design.gd' })
    foreach ($entry in $engines) {
        if ($entry.CommandLine -notmatch 'rachas-implementation-20261018/measure_design.gd') {
            $observations.Add(@{at=(Get-Date).ToUniversalTime().ToString('o');pid=$entry.ProcessId;command=$entry.CommandLine})
        }
    }
    if ($owned.Count -gt 0) { Start-Sleep -Seconds 2 }
} while ($owned.Count -gt 0)
@{started=$started;ended=(Get-Date).ToUniversalTime().ToString('o');sample_seconds=2;external_observations=$observations.ToArray()} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath 'D:/geteco/game/artifacts/rachas-continuation-20261018/performance-final-processes.json'
Write-Output "PERF_FINAL_MONITOR_DONE external_observations=$($observations.Count)"
