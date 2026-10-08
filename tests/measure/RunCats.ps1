param([string]$Prefix = 'cats-comparison')
$ErrorActionPreference = 'Stop'
$projectRoot = 'D:\geteco\game'
$enginePath = 'D:\Downloads Chrome\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe'
if ($Prefix -notmatch '^[a-zA-Z0-9-]+$') { throw 'Invalid evidence prefix' }
function Get-GameProcesses {
    return @(Get-CimInstance Win32_Process -Filter "Name LIKE 'Godot%'" | Where-Object { $_.CommandLine -notmatch '(^|\s)--editor(\s|$)' })
}
$deadline = [DateTime]::UtcNow.AddSeconds(120)
while ((Get-GameProcesses).Count -gt 0) {
    if ([DateTime]::UtcNow -ge $deadline) { Write-Output 'CATS_MEASURE_BLOCKED other Godot sessions stayed active'; exit 4 }
    Start-Sleep -Seconds 3
}
foreach ($variant in @('baseline','final')) {
    if ((Get-GameProcesses).Count -gt 0) { Write-Output 'CATS_MEASURE_BLOCKED concurrent session before launch'; exit 4 }
    $arguments = @('--path',$projectRoot,'--script','res://tests/measure/measure_cats.gd','--','--no-save','--skip-arrival')
    if ($variant -eq 'baseline') { $arguments += '--cats-baseline' }
    $run = Start-Process -FilePath $enginePath -ArgumentList $arguments -WindowStyle Hidden -RedirectStandardOutput "$projectRoot\evidence\$Prefix-$variant.log" -RedirectStandardError "$projectRoot\evidence\$Prefix-$variant.err" -PassThru
    $watch = [Diagnostics.Stopwatch]::StartNew()
    while (-not $run.HasExited) {
        $processes = Get-GameProcesses
        $foreign = @($processes | Where-Object { $_.ProcessId -ne $run.Id -and $_.ParentProcessId -ne $run.Id })
        if ($foreign.Count -gt 0 -or $watch.Elapsed.TotalSeconds -gt 280) {
            # Stop only this measurement and its verified launcher child.
            foreach ($child in @($processes | Where-Object { $_.ParentProcessId -eq $run.Id -and $_.CommandLine -like '*measure_cats.gd*' })) { Stop-Process -Id $child.ProcessId -ErrorAction SilentlyContinue }
            if (-not $run.HasExited) { Stop-Process -Id $run.Id -ErrorAction SilentlyContinue }
            Write-Output "CATS_MEASURE_BLOCKED $variant concurrent=$($foreign.Count) elapsed=$($watch.Elapsed.TotalSeconds)"
            exit 4
        }
        Start-Sleep -Seconds 2
        $run.Refresh()
    }
    $output = Get-Content -LiteralPath "$projectRoot\evidence\$Prefix-$variant.log" -Raw
    $errors = Get-Content -LiteralPath "$projectRoot\evidence\$Prefix-$variant.err" -Raw
    if ($run.ExitCode -ne 0 -or $errors -match 'SCRIPT ERROR|ERROR:' -or $output -notmatch 'CATS_MEASURE res://') { Write-Output "CATS_MEASURE_FAILED $variant"; exit 1 }
    Write-Output "CATS_MEASURE_FINISHED $variant"
}
