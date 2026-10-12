param([string]$Label = 'day-cause-baseline', [string]$Runner = 'res://tests/measure/measure_fleet_day_cost.gd', [switch]$IdentifyProcesses, [switch]$IdentifyFromLaunch)
$ErrorActionPreference = 'Stop'
$projectRoot = 'D:/geteco/game'
$engineRoot = 'D:/Downloads Chrome/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64'
$engine = Join-Path $engineRoot 'Godot_v4.7.2-stable_mono_win64_console.exe'
$folder = Join-Path $projectRoot ('evidence/fleet-redesign-20261011/validation/performance/' + $Label)
if ($Label -notmatch '^[a-z0-9-]+$') { throw 'Unsafe evidence label.' }
if (Test-Path -LiteralPath $folder) { throw 'Evidence folder already exists; never overwrite a run.' }
$other = @(Get-Process | Where-Object { $_.ProcessName -match '^Godot' })
if ($other.Count) { throw 'Another Godot process is active. No benchmark started.' }
New-Item -ItemType Directory -Path $folder | Out-Null
$runtimeSources = Get-Content -LiteralPath (Join-Path $projectRoot 'evidence/fleet-redesign-20261011/validation/performance/ten-cars-rolefix-stable/runtime-source-snapshot.json') -Raw | ConvertFrom-Json -AsHashtable
$snapshot = [ordered]@{}
foreach ($source in $runtimeSources.Keys) {
    $snapshot[$source] = (Get-FileHash -LiteralPath (Join-Path $projectRoot $source) -Algorithm SHA256).Hash.ToLowerInvariant()
}
$snapshot | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $folder 'runtime-source-snapshot.json') -Encoding utf8
$arguments = @('--path', $projectRoot, '--script', $Runner, '--', '--no-save', '--skip-arrival', '--population=24', '--confirm=day', ('--label=' + $Label))
$owned = Start-Process -FilePath $engine -ArgumentList $arguments -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $folder 'benchmark.log') -RedirectStandardError (Join-Path $folder 'benchmark.err')
$native = $null
$cpuObserver = $null
$gpuObserver = $null
$processObserver = $null
$processStartAfter = $null
$watch = [Diagnostics.Stopwatch]::StartNew()
try {
    while (-not $owned.HasExited -and $watch.Elapsed.TotalSeconds -lt 20) {
        $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$($owned.Id)" | Where-Object { $_.Name -eq 'Godot_v4.7.2-stable_mono_win64.exe' })
        if ($children.Count -eq 1) { $native = Get-Process -Id $children[0].ProcessId; break }
        Start-Sleep -Milliseconds 250
    }
    if ($null -eq $native) { throw 'Owned native child was not identified.' }
    if ($IdentifyFromLaunch) { $IdentifyProcesses = $true; $processStartAfter = 0 }
    $cpuArgs = @('tests/measure/observe_fleet_cpu.py', '--pid', [string]$native.Id, '--seconds', '350', '--out', (Join-Path $folder 'external-cpu.json'))
    $cpuObserver = Start-Process -FilePath 'python' -ArgumentList $cpuArgs -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $folder 'cpu-observer.log') -RedirectStandardError (Join-Path $folder 'cpu-observer.err')
    $gpuArgs = @('--query-gpu=timestamp,utilization.gpu,utilization.memory,clocks.gr,clocks.mem,temperature.gpu,power.draw,clocks_event_reasons.active', '--format=csv,noheader,nounits', '-lms', '500')
    $gpuObserver = Start-Process -FilePath 'nvidia-smi.exe' -ArgumentList $gpuArgs -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $folder 'gpu.csv') -RedirectStandardError (Join-Path $folder 'gpu.err')
    @{utc=[DateTime]::UtcNow.ToString('o'); console_pid=$owned.Id; native_pid=$native.Id; native_start_utc=$native.StartTime.ToUniversalTime().ToString('o'); cpu_observer_pid=$cpuObserver.Id; gpu_observer_pid=$gpuObserver.Id; arguments=$arguments; scope='Four day windows, same ten targets and active city. Observers read counters; no application, power, quality, device, priority or affinity changes.'} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $folder 'launch.json') -Encoding utf8
    while (-not $owned.HasExited -and $watch.Elapsed.TotalSeconds -lt 480) {
        if ($IdentifyProcesses -and $null -eq $processObserver) {
            if ($null -eq $processStartAfter -and (Select-String -LiteralPath (Join-Path $folder 'benchmark.log') -Pattern 'FLEET_DAY_COST_PHASE .*window_begin' -Quiet)) {
                $processStartAfter = $watch.Elapsed.TotalSeconds + 8
            }
            if ($null -ne $processStartAfter -and $watch.Elapsed.TotalSeconds -ge $processStartAfter) {
                $probeDll = Join-Path $projectRoot 'evidence/intermittent-stalls-20261004/continuation-native/bin/Release/net10.0/ProcessCpuProbe.dll'
                $probeSeconds = '160'
                if ($IdentifyFromLaunch) {
                    $probeDll = Join-Path $projectRoot 'evidence/fleet-day-investigation-20261011/process-probe-long/bin/Release/net10.0/ProcessCpuProbe.dll'
                    $probeSeconds = '360'
                }
                $nativeExe = Join-Path $engineRoot 'Godot_v4.7.2-stable_mono_win64.exe'
                # Start-Process joins ArgumentList; quote only the known path containing spaces.
                $probeArgs = @($probeDll, '--pid', [string]$native.Id, '--expected-start-utc', $native.StartTime.ToUniversalTime().ToString('o'), '--expected-exe', ('"' + $nativeExe + '"'), '--seconds', $probeSeconds, '--out', (Join-Path $folder 'process-cpu.json'))
                $processObserver = Start-Process -FilePath 'dotnet' -ArgumentList $probeArgs -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $folder 'process-observer.log') -RedirectStandardError (Join-Path $folder 'process-observer.err')
                @{utc=[DateTime]::UtcNow.ToString('o'); pid=$processObserver.Id; arguments=$probeArgs; dll_sha256=(Get-FileHash -LiteralPath $probeDll -Algorithm SHA256).Hash} | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $folder 'process-observer-launch.json') -Encoding utf8
            }
        }
        Start-Sleep -Seconds 1
        $owned.Refresh()
    }
    if (-not $owned.HasExited) { throw 'Owned diagnostic exceeded the finite 480 s deadline.' }
    $owned.WaitForExit()
    Write-Output "FLEET_DAY_EXIT $($owned.ExitCode) $folder"
} finally {
    # Only processes created here are stopped; no name-based termination.
    if ($null -ne $native -and -not $native.HasExited -and -not $owned.HasExited) { $native.Kill() }
    if (-not $owned.HasExited) { $owned.Kill() }
    if ($null -ne $gpuObserver -and -not $gpuObserver.HasExited) { $gpuObserver.Kill(); $gpuObserver.WaitForExit() }
    if ($null -ne $cpuObserver) { $null = $cpuObserver.WaitForExit(10000) }
    if ($null -ne $processObserver) { $null = $processObserver.WaitForExit(10000) }
    $changed = @()
    foreach ($source in $snapshot.Keys) {
        if ((Get-FileHash -LiteralPath (Join-Path $projectRoot $source) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $snapshot[$source]) { $changed += $source }
    }
    @{files=$snapshot.Count; changed=$changed} | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $folder 'source-check-after.json') -Encoding utf8
}
if ($owned.ExitCode -ne 0 -or $changed.Count) { exit 1 }
# Start-Process does not set LASTEXITCODE in the calling PowerShell scope.
exit 0
