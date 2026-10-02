param([Parameter(Mandatory=$true)][string]$Name,[string]$Weapon='',[int]$Seconds=300,[int]$Port=0,[switch]$Profile,[switch]$NativeStacks,[switch]$NoStallLogger,[int]$StackThresholdMs=200,[switch]$Driving,[int]$Distance=1000,[switch]$AudioCache,[switch]$WalkLoop,[switch]$Fast)
$ErrorActionPreference='Stop'
if (Get-Process | Where-Object ProcessName -Like 'Godot*') { throw 'Outra instância do Godot está ativa.' }
$folder='D:/geteco/game/evidence/stall-investigation-20261001'
$output=Join-Path $folder ($Name+'.json')
if (Test-Path -LiteralPath $output) { throw 'Saída já existe.' }
function SourceHashes {
    $result=@{}
    $files=rg --files runtime gameplay scripts world assets audio tests/measure -g '*.gd' -g '*.cs' -g '*.tscn' -g '*.tres' -g '*.json' -g '*.py'
    foreach ($item in $files) { $result[$item]=(Get-FileHash -LiteralPath $item -Algorithm SHA256).Hash }
    foreach ($item in @('project.godot','Main.tscn')) { $result[$item]=(Get-FileHash -LiteralPath $item -Algorithm SHA256).Hash }
    return $result
}
$before=SourceHashes
$before | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $folder ($Name+'-source-before.json'))
$env:HARBOR_STALL_LOG='1'
if ($NoStallLogger) { $env:HARBOR_STALL_LOG='0' }
$env:HARBOR_STALL_WORK='1'
$env:HARBOR_STALL_BACKGROUND='1'
$env:HARBOR_STALL_SELF_PROFILE='1'
$env:HARBOR_MAX_PHYSICS_STEPS='3'
$executable='D:/Downloads Chrome/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64.exe'
$scriptPath=if ($AudioCache) { 'res://tests/measure/measure_foreground_engine_cache.gd' } elseif ($Driving) { 'res://tests/measure/measure_stall_streaming.gd' } else { 'res://tests/measure/measure_stall_combat.gd' }
$arguments=@('--path','D:/geteco/game','--log-file',($folder+'/'+$Name+'.engine.log'),'--script',$scriptPath)
if ($Port -gt 0) { $arguments+=@('--remote-debug',('tcp://127.0.0.1:'+$Port)) }
$arguments+=@('--','--no-save',('--seconds='+$Seconds),'--stars=6','--quiet',('--out=res://evidence/stall-investigation-20261001/'+$Name+'.json'))
if ($Weapon) { $arguments+=('--combat-weapon='+$Weapon) }
if ($Profile) { $arguments+='--profile' }
if ($Driving) { $arguments+=@('--godmode',('--distance='+$Distance)) }
if ($AudioCache) { $arguments+='--compare' }
if ($WalkLoop) { $arguments+='--walk-loop' }
if ($Fast) { $arguments+='--fast' }
$owned=Start-Process -FilePath $executable -ArgumentList $arguments -WindowStyle Hidden -PassThru
Write-Output ('CAPTURE_STARTED pid='+$owned.Id+' name='+$Name)
$samples=[System.Collections.Generic.List[object]]::new()
$threadId=0
$stackSampler=$null
while (-not $owned.HasExited) {
    try {
        $owned.Refresh()
        if ($threadId -eq 0) {
            $threadId=($owned.Threads | Sort-Object StartTime | Select-Object -First 1).Id
            if ($NativeStacks -and $threadId) {
                $samplerArgs=@('tests/measure/windows_wait_stacks.py','--pid',$owned.Id,'--tid',$threadId,'--seconds',($Seconds+120),'--stall-ms',$StackThresholdMs,'--out',($folder+'/'+$Name+'-stacks.json'),'--ready-log',($folder+'/'+$Name+'.engine.log'))
                $stackSampler=Start-Process python -ArgumentList $samplerArgs -WindowStyle Hidden -PassThru -RedirectStandardOutput ($folder+'/'+$Name+'-stacks.stdout.log') -RedirectStandardError ($folder+'/'+$Name+'-stacks.stderr.log')
            }
        }
        $thread=$owned.Threads | Where-Object Id -EQ $threadId
        if ($thread) {
            $reason=if ($thread.ThreadState -eq 'Wait') { [string]$thread.WaitReason } else { '' }
            $samples.Add(@{unix_ms=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();cpu_ms=$thread.TotalProcessorTime.TotalMilliseconds;state=[string]$thread.ThreadState;reason=$reason})
        }
    } catch { }
    Start-Sleep -Milliseconds 100
}
$owned.WaitForExit()
if ($stackSampler) { $stackSampler.WaitForExit() }
$after=SourceHashes
$after | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $folder ($Name+'-source-after.json'))
$changes=@($before.Keys | Where-Object { $before[$_] -ne $after[$_] })
@{exit_code=$owned.ExitCode;source_changes=$changes;native_samples=$samples.Count;oldest_thread_inferred=$threadId;stack_sampler_exit=$(if ($stackSampler) { $stackSampler.ExitCode } else { $null })} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $folder ($Name+'-run.json'))
$samples | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $folder ($Name+'-thread-samples.json'))
Get-Content -LiteralPath (Join-Path $folder ($Name+'.engine.log')) -Tail 12
if ($changes.Count -gt 0) { throw 'Fontes mudaram durante captura.' }
exit $owned.ExitCode
