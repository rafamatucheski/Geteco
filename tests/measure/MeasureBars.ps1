param(
    [ValidateSet('harbor_bar','desert_bar')][string]$Bar = 'harbor_bar',
    [switch]$Before,
    [string]$Label = 'bars-rendered'
)
$ErrorActionPreference = 'Stop'
if ($Label -notmatch '^[a-zA-Z0-9-]+$') { throw 'Rótulo inválido.' }
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$enginePath = 'D:/Downloads Chrome/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe'
function Get-GodotProcesses {
    @(Get-CimInstance Win32_Process -Filter "Name LIKE 'Godot%'" | Where-Object { $_.CommandLine -notmatch '(^|\s)--editor(\s|$)' } | Select-Object ProcessId,ParentProcessId,CommandLine)
}
$initialProcesses = @(Get-GodotProcesses)
if ($initialProcesses.Count -gt 0) { throw 'Medição não iniciada: outro processo Godot está em execução.' }
& dotnet build (Join-Path $projectRoot 'Harbor.csproj') --no-restore
if ($LASTEXITCODE -ne 0) { throw 'Build .NET falhou.' }
$evidenceRoot = Join-Path $projectRoot 'artifacts/bars-20261027'
[IO.Directory]::CreateDirectory($evidenceRoot) | Out-Null
$stdoutPath = Join-Path $evidenceRoot "$Label.log"
$stderrPath = Join-Path $evidenceRoot "$Label.err"
$processPath = Join-Path $evidenceRoot "$Label-processes.json"
$arguments = @('--path',('"'+$projectRoot+'"'),'--script','res://tests/measure/measure_bars.gd','--',"--bar=$Bar",'--measure-bars',('--isolated-save-root="'+$evidenceRoot+'/saves"'))
if ($Before) { $arguments += '--bars-before' }
$childProcess = Start-Process -FilePath $enginePath -ArgumentList $arguments -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
$history = [Collections.Generic.List[object]]::new()
$watch = [Diagnostics.Stopwatch]::StartNew()
$invalid = ''
try {
    while (-not $childProcess.HasExited) {
        $inventory = @(Get-GodotProcesses)
        $foreignProcesses = @($inventory | Where-Object { $_.ProcessId -ne $childProcess.Id -and $_.ParentProcessId -ne $childProcess.Id })
        $history.Add(@{utc=[DateTime]::UtcNow.ToString('o'); foreign=($foreignProcesses.Count -gt 0); processes=$inventory})
        if ($foreignProcesses.Count -gt 0) { $invalid = 'Outro processo Godot iniciou durante a medição.'; break }
        if ($watch.Elapsed.TotalSeconds -gt 330) { $invalid = 'Prazo finito de medição excedido.'; break }
        Start-Sleep -Milliseconds 1000
        $childProcess.Refresh()
    }
    if ($invalid) {
        # Stop only the launcher created here and its explicitly observed child.
        $owned = @(Get-GodotProcesses | Where-Object { $_.ProcessId -eq $childProcess.Id -or $_.ParentProcessId -eq $childProcess.Id })
        foreach ($ownedProcess in $owned) { Stop-Process -Id $ownedProcess.ProcessId -Force -ErrorAction SilentlyContinue }
        throw $invalid
    }
    $childProcess.WaitForExit()
    Get-Content -LiteralPath $stdoutPath -Tail 6
    if ($childProcess.ExitCode -ne 0) { Get-Content -LiteralPath $stderrPath; throw "Execução falhou ($($childProcess.ExitCode))." }
    $diagnostics = Get-Content -LiteralPath $stderrPath -Raw
    if ($diagnostics -match '(?m)^(SCRIPT ERROR|ERROR):') { throw 'O motor registrou erros; métricas não aprovadas.' }
} finally {
    $history | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $processPath
}
