param([int]$QuietDeadlineSeconds = 90)
$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$godot = 'D:/Downloads Chrome/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe'
$fixture = 'res://tests/measure/measure_park_countryside.gd'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$audit = Join-Path $workspace "evidence/recreation-ground-$stamp-processes.jsonl"
$deadline = [DateTime]::UtcNow.AddSeconds($QuietDeadlineSeconds)
$quiet = [DateTime]::UtcNow
while ($true) {
    $active = @(Get-CimInstance Win32_Process -Filter "Name LIKE 'Godot%'")
    if ($active.Count) { $quiet = [DateTime]::UtcNow }
    if (([DateTime]::UtcNow - $quiet).TotalSeconds -ge 15) { break }
    if ([DateTime]::UtcNow -gt $deadline) {
        Write-Output 'GROUND_COMPARISON_BLOCKED: no isolated start window'
        exit 7
    }
    Start-Sleep -Seconds 2
}
foreach ($phase in @('before', 'after')) {
    $log = Join-Path $workspace "evidence/recreation-ground-$stamp-$phase.log"
    $arguments = @('--path', $workspace, '--script', $fixture, '--log-file', $log, '--', '--no-save', '--skip-arrival', '--ground-blend')
    if ($phase -eq 'before') { $arguments += '--before' }
    $ownProcess = Start-Process -FilePath $godot -ArgumentList $arguments -WorkingDirectory $workspace -WindowStyle Hidden -PassThru
    Write-Output "GROUND_COMPARISON_START $phase PID=$($ownProcess.Id) LOG=$log AUDIT=$audit"
    $expires = [DateTime]::UtcNow.AddSeconds(370)
    while (-not $ownProcess.HasExited) {
        $active = @(Get-CimInstance Win32_Process -Filter "Name LIKE 'Godot%'")
        $foreign = @($active | Where-Object { $_.ProcessId -ne $ownProcess.Id -and $_.ParentProcessId -ne $ownProcess.Id })
        [ordered]@{
            utc = [DateTime]::UtcNow.ToString('o')
            phase = $phase
            own = $ownProcess.Id
            engines = @($active | Select-Object ProcessId, ParentProcessId, Name, CommandLine)
            foreign = @($foreign | Select-Object ProcessId, ParentProcessId, Name, CommandLine)
        } | ConvertTo-Json -Depth 5 -Compress | Add-Content -LiteralPath $audit
        if ($foreign.Count -or [DateTime]::UtcNow -gt $expires) {
            $owned = @($active | Where-Object {
                ($_.ProcessId -eq $ownProcess.Id -or $_.ParentProcessId -eq $ownProcess.Id) -and
                $_.CommandLine.Contains('measure_park_countryside.gd')
            })
            foreach ($entry in $owned) { Stop-Process -Id $entry.ProcessId -ErrorAction SilentlyContinue }
            Write-Output "GROUND_COMPARISON_ABORTED $phase foreign=$($foreign.Count)"
            exit 8
        }
        Start-Sleep -Seconds 2
        $ownProcess.Refresh()
    }
    $ownProcess.WaitForExit()
    if ($ownProcess.ExitCode -ne 0) {
        Write-Output "GROUND_COMPARISON_FAILED $phase code=$($ownProcess.ExitCode)"
        exit 9
    }
    $result = Select-String -LiteralPath $log -Pattern 'COUNTRYSIDE_MEASURE'
    if (-not $result) { Write-Output "GROUND_COMPARISON_MISSING_REPORT $phase"; exit 10 }
    Write-Output "GROUND_COMPARISON_DONE $phase"
}
Write-Output 'GROUND_COMPARISON_COMPLETE'
