param([switch]$Cgi, [string]$Label = '')
$ErrorActionPreference = 'Stop'
$arrivalRoot = Split-Path -Parent $PSScriptRoot
$arrivalEngine = 'D:\Downloads Chrome\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$arrivalLabel = if ($Cgi) { 'arrival-cgi' } else { 'arrival-tour' }
if ($Label -ne '') {
    if ($Label -notmatch '^[a-zA-Z0-9-]+$') { throw 'Identificador inválido.' }
    $arrivalLabel = $Label
}
$arrivalExisting = @(Get-CimInstance Win32_Process -Filter "Name LIKE 'Godot%'" | Select-Object ProcessId,ParentProcessId,CommandLine)
$arrivalRunning = @($arrivalExisting | Where-Object { $_.CommandLine -notmatch '(^|\s)--editor(\s|$)' })
if ($arrivalRunning.Count -gt 0) { throw 'Outro jogo ativo: medição não iniciada.' }
$arrivalSamples = [System.Collections.Generic.List[object]]::new()
$arrivalSamples.Add(@{utc=[DateTime]::UtcNow.ToString('o');phase='before';processes=$arrivalExisting})
$arrivalArguments = @('--path',('"'+$arrivalRoot+'"'),'--script','res://tests/arrival_measure.gd','--','--no-save','--skip-arrival','--benchmark','--population=24')
$arrivalArguments += "--label=$arrivalLabel"
if ($Cgi) { $arrivalArguments += '--cgi' }
$arrivalLog = Join-Path $arrivalRoot "evidence/$arrivalLabel.log"
$arrivalErr = Join-Path $arrivalRoot "evidence/$arrivalLabel.err"
$arrivalProcess = Start-Process -FilePath $arrivalEngine -ArgumentList $arrivalArguments -WindowStyle Hidden -RedirectStandardOutput $arrivalLog -RedirectStandardError $arrivalErr -PassThru
$arrivalWatch = [Diagnostics.Stopwatch]::StartNew()
while (-not $arrivalProcess.HasExited) {
    $arrivalActive = @(Get-CimInstance Win32_Process -Filter "Name LIKE 'Godot%'" | Select-Object ProcessId,ParentProcessId,CommandLine)
    $arrivalForeign = @($arrivalActive | Where-Object { $_.ProcessId -ne $arrivalProcess.Id -and $_.ParentProcessId -ne $arrivalProcess.Id -and $_.CommandLine -notmatch '(^|\s)--editor(\s|$)' })
    $arrivalSamples.Add(@{utc=[DateTime]::UtcNow.ToString('o');phase='during';concurrent=($arrivalForeign.Count -gt 0);processes=$arrivalActive})
    if ($arrivalForeign.Count -gt 0 -or $arrivalWatch.Elapsed.TotalSeconds -gt 95) {
        Stop-Process -Id $arrivalProcess.Id -Force
        throw 'Medição interrompida por concorrência ou limite de95s.'
    }
    Start-Sleep -Milliseconds 1000
    $arrivalProcess.Refresh()
}
$arrivalProcess.WaitForExit()
$arrivalSamples | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $arrivalRoot "evidence/$arrivalLabel-processes.json")
Get-Content -LiteralPath $arrivalLog -Tail 3
Get-Content -LiteralPath $arrivalErr -Tail 30
if ($arrivalProcess.ExitCode -ne 0) { throw "Benchmark terminou com código $($arrivalProcess.ExitCode)." }
if ((Get-Item -LiteralPath $arrivalErr).Length -gt 0) { throw 'Benchmark produziu stderr; examinar evidência antes de aprovar.' }
