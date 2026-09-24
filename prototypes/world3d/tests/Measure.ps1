param([switch]$AllowConcurrent, [int[]]$Counts = @(0,24,96), [string]$Prefix = '', [switch]$Driving)
$ErrorActionPreference = 'Stop'
$prototypeRoot = Split-Path -Parent $PSScriptRoot
$engine = 'D:\Downloads Chrome\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
if ($Prefix -notmatch '^[a-zA-Z0-9-]*$') { throw 'Prefixo inválido.' }
foreach ($count in $Counts) {
    $existing = @(Get-CimInstance Win32_Process -Filter "Name LIKE 'Godot%'" | Select-Object ProcessId,ParentProcessId,CommandLine)
    $running = @($existing | Where-Object { $_.CommandLine -notmatch '(^|\s)--editor(\s|$)' })
    if ($running.Count -gt 0 -and -not $AllowConcurrent) {
        throw 'Feche as outras janelas do jogo antes de medir. O editor pode continuar aberto.'
    }
    $label = if ($running.Count -gt 0) { "concurrent-population$count" } else { "isolated-population$count" }
    $label = $Prefix + $label
    $outputLog = Join-Path $prototypeRoot "evidence/$label.log"
    $errorLog = Join-Path $prototypeRoot "evidence/$label.err"
    $snapshots = [System.Collections.Generic.List[object]]::new()
    $snapshots.Add(@{utc=[DateTime]::UtcNow.ToString('o'); phase='before'; processes=$existing})
    $runArguments = @('--path',('"'+$prototypeRoot+'"'),'--script','res://tests/measure.gd','--',"--population=$count","--label=$label")
    if ($Driving) { $runArguments += '--drive' }
    $process = Start-Process -FilePath $engine -ArgumentList $runArguments -WindowStyle Hidden -RedirectStandardOutput $outputLog -RedirectStandardError $errorLog -PassThru
    $watch = [Diagnostics.Stopwatch]::StartNew()
    while (-not $process.HasExited) {
        $active = @(Get-CimInstance Win32_Process -Filter "Name LIKE 'Godot%'" | Select-Object ProcessId,ParentProcessId,CommandLine)
        # Godot's console launcher starts the rendering executable as its child.
        $foreign = @($active | Where-Object { $_.ProcessId -ne $process.Id -and $_.ParentProcessId -ne $process.Id -and $_.CommandLine -notmatch '(^|\s)--editor(\s|$)' })
        $snapshots.Add(@{utc=[DateTime]::UtcNow.ToString('o'); phase='during'; concurrent=($foreign.Count -gt 0); processes=$active})
        if (($foreign.Count -gt 0 -and -not $AllowConcurrent) -or $watch.Elapsed.TotalSeconds -gt 65) {
            # This PID was created above and belongs solely to this measurement.
            Stop-Process -Id $process.Id -Force
            $snapshots | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $prototypeRoot "evidence/$label-processes.json")
            throw 'Medição interrompida: concorrência detectada ou limite de duração atingido.'
        }
        Start-Sleep -Milliseconds 1000
        $process.Refresh()
    }
    $process.WaitForExit()
    $snapshots | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $prototypeRoot "evidence/$label-processes.json")
    Get-Content -LiteralPath $outputLog -Tail 1
    if ($process.ExitCode -ne 0 -or (Get-Item -LiteralPath $errorLog).Length -gt 0) {
        Get-Content -LiteralPath $errorLog
        throw "Falha na medição $label"
    }
}
