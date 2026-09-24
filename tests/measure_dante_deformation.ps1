param([string]$Label = 'before', [switch]$Baseline)
$ErrorActionPreference = 'Stop'
$danteRoot = Split-Path -Parent $PSScriptRoot
$danteEngine = 'D:/Downloads Chrome/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
$danteOutput = Join-Path $danteRoot 'evidence/dante-deformation-0922'
$danteHashes = Get-ChildItem -LiteralPath $danteRoot -Recurse -File -Filter '*.gd' | Where-Object { $_.FullName -notmatch '\\(evidence|tests|assets|\.godot)\\' } | Get-FileHash
$danteHashes | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $danteOutput "$Label-source-hashes.json")
$danteExisting = @(Get-CimInstance Win32_Process -Filter "Name LIKE 'Godot%'" | Select-Object ProcessId,ParentProcessId,CommandLine)
if (@($danteExisting | Where-Object { $_.CommandLine -notmatch '(^|\s)--editor(\s|$)' }).Count -gt 0) { throw 'Outro runtime Godot ativo; benchmark recusado.' }
$danteProcesses = [Collections.Generic.List[object]]::new()
$danteProcesses.Add(@{time=[DateTime]::UtcNow.ToString('o');processes=$danteExisting})
$danteArgs = @('--path', ('"'+$danteRoot+'"'), '--script', 'res://tests/capture_dante_deformation.gd', '--', '--no-save', '--skip-arrival', '--population=24', "--dante-label=$Label")
if ($Baseline) { $danteArgs += '--dante-baseline' }
$danteProcess = Start-Process -FilePath $danteEngine -ArgumentList $danteArgs -WindowStyle Hidden -RedirectStandardOutput (Join-Path $danteOutput "$Label-measure.log") -RedirectStandardError (Join-Path $danteOutput "$Label-measure.err") -PassThru
$danteWatch = [Diagnostics.Stopwatch]::StartNew()
while (-not $danteProcess.HasExited) {
    $danteActive = @(Get-CimInstance Win32_Process -Filter "Name LIKE 'Godot%'" | Select-Object ProcessId,ParentProcessId,CommandLine)
    $danteForeign = @($danteActive | Where-Object { $_.ProcessId -ne $danteProcess.Id -and $_.ParentProcessId -ne $danteProcess.Id -and $_.CommandLine -notmatch '(^|\s)--editor(\s|$)' })
    $danteProcesses.Add(@{time=[DateTime]::UtcNow.ToString('o');processes=$danteActive;concurrent=($danteForeign.Count -gt 0)})
    $danteCompileFailure = $false
    if ($danteWatch.Elapsed.TotalSeconds -lt 12) {
        $danteCompileFailure = [bool](Select-String -LiteralPath (Join-Path $danteOutput "$Label-measure.err") -Pattern 'Parse Error:|Compile Error:' -Quiet)
    }
    if ($danteForeign.Count -gt 0 -or $danteWatch.Elapsed.TotalSeconds -gt 240 -or $danteCompileFailure) {
        # The console launcher owns a separate engine child on Windows.
        $danteActive | Where-Object { $_.ParentProcessId -eq $danteProcess.Id } | ForEach-Object { Stop-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }
        Stop-Process -Id $danteProcess.Id
        $danteProcesses | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $danteOutput "$Label-processes-aborted.json")
        throw 'Benchmark interrompido: runtime concorrente, compilação inválida ou limite de 240 s.'
    }
    Start-Sleep -Seconds 1
    $danteProcess.Refresh()
}
$danteProcess.WaitForExit()
$danteProcesses | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $danteOutput "$Label-processes.json")
Get-Content -LiteralPath (Join-Path $danteOutput "$Label-measure.log") -Tail 2
if ($danteProcess.ExitCode -ne 0) { throw "Exit $($danteProcess.ExitCode)" }
