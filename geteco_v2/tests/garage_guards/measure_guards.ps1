param([switch]$Control)
$ErrorActionPreference='Stop'
$guardRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$guardEngine='D:\Downloads Chrome\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$guardLabel=if($Control){'garage-guards-control'}else{'garage-guards-product'}
$guardExisting=@(Get-CimInstance Win32_Process -Filter "Name LIKE 'Godot%'" | Select-Object ProcessId,ParentProcessId,CommandLine)
if(@($guardExisting | Where-Object {$_.CommandLine -notmatch '(^|\s)--editor(\s|$)'}).Count -gt 0){throw 'Outro jogo ativo; medição recusada.'}
$guardSamples=[System.Collections.Generic.List[object]]::new()
$guardSamples.Add(@{utc=[DateTime]::UtcNow.ToString('o');phase='before';processes=$guardExisting})
$guardArguments=@('--path',('"'+$guardRoot+'"'),'--script','res://tests/garage_guards/measure_guards.gd','--','--no-save','--skip-arrival','--benchmark','--population=24')
if($Control){$guardArguments+='--without-guards'}
$guardLog=Join-Path $guardRoot "evidence/$guardLabel.log"
$guardErr=Join-Path $guardRoot "evidence/$guardLabel.err"
$guardProcess=Start-Process -FilePath $guardEngine -ArgumentList $guardArguments -WindowStyle Hidden -RedirectStandardOutput $guardLog -RedirectStandardError $guardErr -PassThru
$guardWatch=[Diagnostics.Stopwatch]::StartNew()
while(-not $guardProcess.HasExited){
    $guardActive=@(Get-CimInstance Win32_Process -Filter "Name LIKE 'Godot%'" | Select-Object ProcessId,ParentProcessId,CommandLine)
    $guardForeign=@($guardActive | Where-Object {$_.ProcessId -ne $guardProcess.Id -and $_.ParentProcessId -ne $guardProcess.Id -and $_.CommandLine -notmatch '(^|\s)--editor(\s|$)'})
    $guardSamples.Add(@{utc=[DateTime]::UtcNow.ToString('o');phase='during';concurrent=($guardForeign.Count -gt 0);processes=$guardActive})
    if($guardForeign.Count -gt 0 -or $guardWatch.Elapsed.TotalSeconds -gt 80){Stop-Process -Id $guardProcess.Id -Force; throw 'Medição interrompida: concorrência ou limite80s.'}
    Start-Sleep -Milliseconds 1000
    $guardProcess.Refresh()
}
$guardProcess.WaitForExit()
$guardSamples | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $guardRoot "evidence/$guardLabel-processes.json")
Get-Content -LiteralPath $guardLog -Tail 2
Get-Content -LiteralPath $guardErr -Tail 15
if($guardProcess.ExitCode -ne 0){throw "Benchmark encerrou com código $($guardProcess.ExitCode)"}
if((Get-Item -LiteralPath $guardErr).Length -gt 0){throw 'Stderr presente; evidência exige revisão.'}
