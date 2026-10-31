param(
    [Parameter(Mandatory=$true)][ValidatePattern('^[a-zA-Z0-9-]+$')][string]$Label,
    [ValidateSet('on','off')][string]$Observer='on',
    [string]$Project='D:/geteco/game/evidence/intermittent-stalls-20261004/snapshot',
    [switch]$PrepareSnapshot,
    [switch]$EventPipe,
    [ValidateRange(50,150)][int]$EventPipeSeconds=55,
    [switch]$ScriptProfiler,
    [switch]$ExternalTelemetry,
    [switch]$ProcessProvenance,
    [switch]$ThreadStateSamples,
    [switch]$PinGroundBlood,
    [string]$ShaderCacheSeed='',
    [ValidateRange(1,8)][int]$MaxPhysicsSteps=3
)
$ErrorActionPreference='Stop'
$live='D:/geteco/game'
$base=Join-Path $live 'evidence/intermittent-stalls-20261004'
$folder=Join-Path $base $Label
$engine='D:/Downloads Chrome/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe'
. (Join-Path $PSScriptRoot 'ShaderCacheSeed.ps1')
function GameProcesses {
    @(Get-CimInstance Win32_Process -Filter "Name LIKE 'Godot%'" | Where-Object { $_.CommandLine -notmatch '(^|\s)--editor(\s|$)' })
}
if(Test-Path -LiteralPath $folder) { throw 'Label already exists; evidence must not be overwritten.' }
New-Item -ItemType Directory -Path $folder -Force | Out-Null
$existing=@(GameProcesses)
if($existing.Count) {
    $existing | Select-Object ProcessId,ParentProcessId,CommandLine | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $folder 'blocked.json')
    throw 'Another Godot game/test is active. No capture started.'
}
if($PrepareSnapshot) {
    if(Test-Path -LiteralPath $Project) { throw 'Use a new snapshot destination.' }
    New-Item -ItemType Directory -Path $Project | Out-Null
    foreach($directory in @('activities','addons','assets','audio','cutscenes','data','gameplay','migration','runtime','scripts','systems','tests','tools','ui','world','.godot')) {
        & robocopy (Join-Path $live $directory) (Join-Path $Project $directory) /E /R:0 /W:0 /NFL /NDL /NJH /NJS /NP /XD editor logs | Out-Null
        if($LASTEXITCODE -gt 7) { throw "Snapshot copy failed: $directory" }
    }
    foreach($file in @('project.godot','Harbor.csproj','Harbor.sln','Main.tscn','AGENTS.md')) {
        Copy-Item -LiteralPath (Join-Path $live $file) -Destination (Join-Path $Project $file)
    }
    # O retrato das fontes é uma cópia independente; assets e cache de importação também são copiados.
    $drift=@(Get-ChildItem -LiteralPath $Project -Recurse -File | Where-Object {
        $_.FullName -notmatch '[\\/]\.godot[\\/]' -and $_.Extension -in '.gd','.cs','.gdshader','.tscn','.json','.godot','.csproj'
    } | ForEach-Object {
        $relative=$_.FullName.Substring($Project.Length).TrimStart('\','/')
        $original=Join-Path $live $relative
        if((Test-Path -LiteralPath $original) -and (Get-FileHash -LiteralPath $original).Hash -ne (Get-FileHash -LiteralPath $_.FullName).Hash) { $relative }
    })
    @{prepared_utc=[DateTime]::UtcNow.ToString('o'); drift_during_copy=$drift; project=$Project} | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $folder 'snapshot-state.json')
    if($drift.Count) { throw 'Concurrent source edit during snapshot; inspect preserved snapshot-state.' }
}
Push-Location -LiteralPath $Project
try {
    & dotnet build Harbor.csproj --no-restore *> (Join-Path $folder 'build.log')
    if($LASTEXITCODE -ne 0) { throw 'Snapshot C# build failed.' }
} finally { Pop-Location }
$hashes=@{}
Get-ChildItem -LiteralPath $Project -Recurse -File | Where-Object {
    $_.FullName -notmatch '[\\/]\.godot[\\/]' -and $_.Extension -in '.gd','.cs','.gdshader','.gdshaderinc','.tscn','.json','.godot','.csproj','.scn','.tres','.res'
} | ForEach-Object { $hashes[$_.FullName.Substring($Project.Length)] = (Get-FileHash -LiteralPath $_.FullName).Hash }
$hashes | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $folder 'source-hashes.json')
$savedApp=$env:APPDATA
$savedLocal=$env:LOCALAPPDATA
try {
    $env:APPDATA=Join-Path $folder 'user'
    $env:LOCALAPPDATA=Join-Path $folder 'local'
    New-Item -ItemType Directory -Path (Join-Path $env:APPDATA 'GetecoV2'),$env:LOCALAPPDATA -Force | Out-Null
    $settings=Join-Path $savedApp 'GetecoV2/settings.cfg'
    if(Test-Path -LiteralPath $settings) { Copy-Item -LiteralPath $settings -Destination (Join-Path $env:APPDATA 'GetecoV2/settings.cfg') }
    # Isolar os saves também isola o cache do ShaderRD. Declara rodadas frias e permite
    # uma semente compatível congelada para condições de jogador que volta.
    $cachePreparation=Prepare-IsolatedShaderCache $ShaderCacheSeed (Join-Path $env:APPDATA 'GetecoV2/shader_cache')
    $cachePreparation | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $folder 'shader-cache-preparation.json') -Encoding utf8
    foreach($key in @('HARBOR_NO_CSHARP','HARBOR_PLAN_BAKE_SOURCE','HARBOR_PLAN_BAKE_RESULT','HARBOR_PLAN_WARMUP_IDENTITY','HARBOR_PLAN_STARTUP_ORPHANS','HARBOR_WCT','HARBOR_STALL_AGGREGATE')) {
        [Environment]::SetEnvironmentVariable($key,$null,'Process')
    }
    $env:HARBOR_MAX_PHYSICS_STEPS=[string]$MaxPhysicsSteps
    $env:HARBOR_STALL_LOG='1'
    $env:HARBOR_STALL_MS='25'
    $env:HARBOR_STALL_SELF_PROFILE='1'
    $env:HARBOR_STALL_WORK=if($Observer -eq 'on'){'1'}else{'0'}
    $env:HARBOR_STALL_TRACE=if($Observer -eq 'on'){'1'}else{'0'}
    # Mantém o StallLog normal do lançador nos dois braços; só as sondas extras variam.
    $profileOwned=$null
    if($ScriptProfiler) {
        $receiver=Join-Path $base 'continuation-native/godot_profile_ring_receiver.py'
        $profileOwned=Start-Process -FilePath 'python' -ArgumentList @($receiver,'--port','6017','--out',(Join-Path $folder 'script-profile.json'),'--seconds','170','--threshold-ms','25','--ring-seconds','3') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $folder 'profile-stdout.log') -RedirectStandardError (Join-Path $folder 'profile-stderr.log')
        $profileTimer=[Diagnostics.Stopwatch]::StartNew()
        do {
            Start-Sleep -Milliseconds 100
            $profileOwned.Refresh()
            $profileReady=(Get-Content -LiteralPath (Join-Path $folder 'profile-stdout.log') -Raw) -match 'PROFILE_(RING_)?LISTENING'
        } while(-not $profileReady -and -not $profileOwned.HasExited -and $profileTimer.Elapsed.TotalSeconds -lt 5)
        if(-not $profileReady){throw 'Script profiler receiver did not become ready.'}
    }
    $args=@('--path',$Project)
    if($ScriptProfiler){$args+=@('--remote-debug','tcp://127.0.0.1:6017')}
    $args+=@('--script','res://tests/measure/measure_intermittent_stalls.gd','--','--no-save','--skip-arrival',"--label=$Label","--out=$folder","--observer=$Observer")
    if($ScriptProfiler){$args+='--script-profile'}
    if($PinGroundBlood){$args+='--pin-ground-blood'}
    $owned=Start-Process -FilePath $engine -ArgumentList $args -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $folder 'stdout.log') -RedirectStandardError (Join-Path $folder 'stderr.log')
    $null=$owned.Handle
    @{shader_cache=$cachePreparation; scope='ShaderRD cache only; driver/pipeline caches are not seeded.'} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $folder 'shader-cache-launch.json') -Encoding utf8
    @{utc=[DateTime]::UtcNow.ToString('o'); pid=$owned.Id; engine=$engine; project=$Project; arguments=$args; observer=$Observer; eventpipe=$EventPipe.IsPresent; eventpipe_seconds=$EventPipeSeconds; script_profiler=$ScriptProfiler.IsPresent; external_telemetry=$ExternalTelemetry.IsPresent; process_provenance=$ProcessProvenance.IsPresent; thread_state_samples=$ThreadStateSamples.IsPresent; pin_ground_blood=$PinGroundBlood.IsPresent; appdata=$env:APPDATA; localappdata=$env:LOCALAPPDATA} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $folder 'launch.json')
    $watch=[Collections.Generic.List[object]]::new()
    $timer=[Diagnostics.Stopwatch]::StartNew()
    $invalid=''
    $traceOwned=$null
    $telemetryOwned=$null
    $threadStateOwned=$null
    while(-not $owned.HasExited) {
        $active=@(GameProcesses)
        $foreign=@($active | Where-Object { $_.ProcessId -ne $owned.Id -and $_.ParentProcessId -ne $owned.Id })
        $watch.Add(@{utc=[DateTime]::UtcNow.ToString('o'); foreign=@($foreign | Select-Object ProcessId,ParentProcessId,CommandLine)})
        if($foreign.Count -or $timer.Elapsed.TotalSeconds -gt 250) {
            $invalid=if($foreign.Count){'concurrent_process'}else{'timeout'}
            # Só o lançador exato e o filho Godot dele pertencem a esta captura.
            foreach($proc in @($active | Where-Object { $_.ProcessId -eq $owned.Id -or $_.ParentProcessId -eq $owned.Id })) { Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue }
            break
        }
        if($EventPipe -and $null -eq $traceOwned -and $timer.Elapsed.TotalSeconds -ge 3) {
            $nativeChild=@($active | Where-Object { $_.ParentProcessId -eq $owned.Id -and $_.Name -eq 'Godot_v4.7.2-stable_mono_win64.exe' })
            if($nativeChild.Count -eq 1) {
                $traceTarget=Get-Process -Id $nativeChild[0].ProcessId
                $traceHelper=if($EventPipeSeconds -gt 60){Join-Path $base 'continuation-native/recovery-eventpipe/bin/Release/net10.0/EventPipeCapture.dll'}else{Join-Path $base 'eventpipe-helper/bin/Release/net10.0/EventPipeCapture.dll'}
                $traceArgs=@($traceHelper,
                    '--pid',[string]$traceTarget.Id,'--expected-start-utc',$traceTarget.StartTime.ToUniversalTime().ToString('O'),
                    '--expected-exe',('"'+$traceTarget.MainModule.FileName+'"'),
                    '--out',(Join-Path $folder 'eventpipe'),'--seconds',[string]$EventPipeSeconds)
                $traceOwned=Start-Process -FilePath 'dotnet' -ArgumentList $traceArgs -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $folder 'eventpipe-stdout.log') -RedirectStandardError (Join-Path $folder 'eventpipe-stderr.log')
            }
        }
        if($ExternalTelemetry -and $null -eq $telemetryOwned -and $timer.Elapsed.TotalSeconds -ge 3) {
            $nativeChild=@($active | Where-Object { $_.ParentProcessId -eq $owned.Id -and $_.Name -eq 'Godot_v4.7.2-stable_mono_win64.exe' })
            if($nativeChild.Count -eq 1) {
                $telemetryTarget=Get-Process -Id $nativeChild[0].ProcessId
                $telemetryHelper=if($ProcessProvenance){Join-Path $base 'continuation-native/provenance-cpu/bin/Release/net10.0/ProcessCpuProbe.dll'}else{Join-Path $base 'continuation-native/bin/Release/net10.0/ProcessCpuProbe.dll'}
                $telemetryArgs=@($telemetryHelper,
                    '--pid',[string]$telemetryTarget.Id,'--expected-start-utc',$telemetryTarget.StartTime.ToUniversalTime().ToString('O'),
                    '--expected-exe',('"'+$telemetryTarget.MainModule.FileName+'"'),
                    '--out',(Join-Path $folder 'process-cpu.json'),'--seconds','160')
                $telemetryOwned=Start-Process -FilePath 'dotnet' -ArgumentList $telemetryArgs -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $folder 'telemetry-stdout.log') -RedirectStandardError (Join-Path $folder 'telemetry-stderr.log')
            }
        }
        if($ThreadStateSamples -and $null -eq $threadStateOwned) {
            $readyLine=Select-String -LiteralPath (Join-Path $folder 'stdout.log') -Pattern '^STALL_CAPTURE_READY ' | Select-Object -Last 1
            if($null -ne $readyLine) {
                $ready=($readyLine.Line.Substring($readyLine.Line.IndexOf('{')) | ConvertFrom-Json)
                $nativeChild=@($active | Where-Object { $_.ParentProcessId -eq $owned.Id -and $_.ProcessId -eq $ready.details.pid -and $_.Name -eq 'Godot_v4.7.2-stable_mono_win64.exe' })
                if($nativeChild.Count -ne 1){throw 'Thread state target differs from owned native child.'}
                $stateTarget=Get-Process -Id $nativeChild[0].ProcessId
                $stateArgs=@((Join-Path $base 'continuation-native/bin/Release/net10.0/ThreadStateProbe.dll'),
                    '--pid',[string]$stateTarget.Id,'--tid',[string]$ready.details.thread_sample[1],
                    '--expected-start-utc',$stateTarget.StartTime.ToUniversalTime().ToString('O'),
                    '--expected-exe',('"'+$stateTarget.MainModule.FileName+'"'),
                    '--out',(Join-Path $folder 'thread-states.json'),'--seconds','150','--hz','20')
                $threadStateOwned=Start-Process -FilePath 'dotnet' -ArgumentList $stateArgs -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $folder 'thread-state-stdout.log') -RedirectStandardError (Join-Path $folder 'thread-state-stderr.log')
            }
        }
        Start-Sleep -Milliseconds 1000
        $owned.Refresh()
    }
    $owned.WaitForExit()
    if($ShaderCacheSeed) {
        $seedAfter=Read-VerifiedShaderCacheSeed $ShaderCacheSeed
        if($seedAfter.manifest_sha256 -ne $cachePreparation.manifest_sha256) { throw 'Frozen seed changed while game ran.' }
        @{verified_after_finished_utc=[DateTime]::UtcNow.ToString('o'); manifest_sha256=$seedAfter.manifest_sha256; unchanged=$true} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $folder 'shader-cache-seed-after.json') -Encoding utf8
    }
    if($null -ne $threadStateOwned) {
        $stateFinished=$threadStateOwned.WaitForExit(10000)
        @{pid=$threadStateOwned.Id; finished=$stateFinished; exit_code=if($stateFinished){$threadStateOwned.ExitCode}else{$null}} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $folder 'thread-state-process.json')
    }
    if($null -ne $telemetryOwned) {
        $telemetryFinished=$telemetryOwned.WaitForExit(10000)
        @{pid=$telemetryOwned.Id; finished=$telemetryFinished; exit_code=if($telemetryFinished){$telemetryOwned.ExitCode}else{$null}} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $folder 'telemetry-process.json')
    }
    if($null -ne $profileOwned) {
        $profileFinished=$profileOwned.WaitForExit(10000)
        @{pid=$profileOwned.Id; finished=$profileFinished; exit_code=if($profileFinished){$profileOwned.ExitCode}else{$null}} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $folder 'profile-process.json')
    }
    if($null -ne $traceOwned) {
        $traceFinished=$traceOwned.WaitForExit(10000)
        @{pid=$traceOwned.Id; finished=$traceFinished; exit_code=if($traceFinished){$traceOwned.ExitCode}else{$null}} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $folder 'eventpipe-process.json')
    }
    $changed=@(foreach($relative in $hashes.Keys) { if((Get-FileHash -LiteralPath ($Project+$relative)).Hash -ne $hashes[$relative]) { $relative } })
    if($changed.Count) { $invalid='source_changed' }
    $errors=@()
    foreach($log in @('stdout.log','stderr.log')) {
        $contents=[string](Get-Content -LiteralPath (Join-Path $folder $log) -Raw)
        $errors+=@([regex]::Matches($contents,'(?m)^\s*(?:SCRIPT ERROR|Parse Error|ERROR:)[^\r\n]*') | ForEach-Object { $_.Value.Trim() })
    }
    if($errors.Count) { $invalid='runtime_errors' }
    $watch | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $folder 'process-watch.json')
    @{invalid=$invalid; exit_code=$owned.ExitCode; seconds=$timer.Elapsed.TotalSeconds; source_changed=$changed; errors=$errors} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $folder 'validity.json')
    Get-Content -LiteralPath (Join-Path $folder 'stdout.log') -Tail 5
    if($errors.Count) { $errors | Select-Object -First 8 }
    if($invalid -or $owned.ExitCode -ne 0) { throw "Invalid capture: $invalid exit=$($owned.ExitCode)" }
} finally {
    $env:APPDATA=$savedApp
    $env:LOCALAPPDATA=$savedLocal
}
