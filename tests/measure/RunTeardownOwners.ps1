param([ValidateSet('before','after')][string]$Phase='after',[string]$RunId='',[switch]$ClearCursor)
$ErrorActionPreference='Stop'

# Exit code alone cannot certify assertions emitted while SceneTree finishes.
function Assert-TeardownOwnerReport([string]$Path,[string]$Phase) {
    if(-not (Test-Path -LiteralPath $Path)){throw 'Missing inventory report'}
    $r=Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    if(-not $r.initially_empty -or -not $r.cache_reused_on_second_warm -or
       $r.scratch_nodes_alive -ne 0 -or $r.template_node_count -le 0 -or
       $r.template_nodes_alive -ne $r.template_node_count -or
       $r.orphan_delta -ne $r.template_node_count){throw 'Template inventory/reuse contract failed'}
    if($Phase -eq 'after' -and ($r.actual_root_shutdown.passed -ne $true -or
       $r.actual_root_shutdown.templates_alive -ne 0 -or
       $r.actual_root_shutdown.cache_entries_cleared -ne $true)) {
        throw 'Template/cursor real shutdown contract failed'
    }
    return $r
}


function Assert-TeardownLogs([string]$Directory) {
    $lines=@([IO.File]::ReadAllLines((Join-Path $Directory 'stdout.log')))+@([IO.File]::ReadAllLines((Join-Path $Directory 'stderr.log')))
    $errors=@($lines | Where-Object { $_ -match '^\s*(ERROR:|SCRIPT ERROR:|FAIL[ :])' -or $_ -match '^\s*WARNING:.*(leak|ObjectDB|still in use)' })
    if($errors.Count){throw ('Teardown log contains failures: '+(($errors|Select-Object -First 3)-join ' | '))}
}

$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $root 'tests\Runner.Common.ps1')
$engine=Resolve-GodotEngine ''
$concurrent=@(Assert-GodotExclusive)
if(-not $RunId){$RunId='teardown-owners-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)}
$evidence=Join-Path $root ('evidence\'+$RunId+'\'+$Phase)
if(Test-Path -LiteralPath $evidence){throw 'Diretorio de evidencia ja existe; nao sobrescrever tentativa anterior'}
New-Item -ItemType Directory -Path $evidence -Force | Out-Null
$saveRoot=Join-Path ([IO.Path]::GetTempPath()) ('geteco-teardown-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $saveRoot | Out-Null
$arguments=@('--verbose','--path',('"'+$root+'"'),'--script','res://tests/measure/measure_teardown_owners.gd','--','--no-save','--skip-arrival',('--owner-label='+$Phase),('"--isolated-save-root='+$saveRoot+'"'),('--evidence-dir=res://evidence/'+$RunId+'/'+$Phase))

if($ClearCursor){$arguments+='--clear-cursor-on-shutdown'}
$sources=@('runtime/GameInput.gd','tests/measure/RunTeardownOwners.ps1','gameplay/ArsenalWeapon3D.gd','gameplay/police_response/air_k9/PoliceHelicopterArt.gd','gameplay/police_response/air_k9/PoliceAirK9Director.gd','tests/measure/measure_teardown_owners.gd','tests/measure/measure_full.gd','tests/measure/measure.gd','world/city_look/CityChunkDressing.gd','world/regions/NativeRegion.gd','world/urban_detail/HarborRoadGeometry3D.gd','world/editing/WorldEditRuntime.gd','tests/Runner.Common.ps1','scripts/Vehicle.gd','gameplay/VehicleBoardingPresentation.gd','runtime/ProductionWorld.gd','world/editing/world_edits.json','project.godot','audio/VehicleCrashAudio.gd','gameplay/vehicle_effects/VehicleImpactEffects.gd','gameplay/street_physics/StreetPhysics.gd')
$metadata=New-RunnerMetadata $root $engine @{Runner='teardown-attribution-rendered';Phase=$Phase;Args=$arguments;TimeoutSec=40;ConcurrentProcessIds=@($concurrent|ForEach-Object ProcessId);Scope='Actual cursor and templates lifecycle; lightweight scenes, no Main or FPS validation';DiagnosticCursorReset=[bool]$ClearCursor} $sources
$started=[DateTime]::UtcNow
$process=Start-Process -FilePath $engine -ArgumentList $arguments -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $evidence 'stdout.log') -RedirectStandardError (Join-Path $evidence 'stderr.log')
$null=$process.Handle
$state=[ordered]@{Pid=$process.Id;Evidence=$evidence;StartedUtc=$started.ToString('o');SaveRoot=$saveRoot;RunId=$RunId;Phase=$Phase}
$state|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $evidence 'run-state.json') -Encoding utf8
Write-Host ('RUNTIME_RESERVED PID='+$process.Id+' phase='+$Phase+' evidence='+$evidence)
$finished=$process.WaitForExit(40000)
$code=-1
if($finished){$process.WaitForExit();$code=$process.ExitCode}else{if(-not (Stop-OwnedGodot $process)){throw 'Timeout: nao foi possivel confirmar encerramento do processo proprio'}}
$result=[ordered]@{Script='tests/measure/measure_teardown_owners.gd';Phase=$Phase;ExitCode=$code;Timeout=(-not $finished);DurationSeconds=([DateTime]::UtcNow-$started).TotalSeconds;Pid=$process.Id;Args=$arguments}
$contractPassed=$false
$logsPassed=$false
$logsError=$null
$contractError=$null
try {
    $inventory=Assert-TeardownOwnerReport (Join-Path $evidence ($Phase+'.json')) $Phase
    $contractPassed=$true
} catch { $contractError=$_.Exception.Message }
try {Assert-TeardownLogs $evidence; $logsPassed=$true} catch {$logsError=$_.Exception.Message}
$result.LogsPassed=$logsPassed
$result.LogsError=$logsError
$result.ContractPassed=$contractPassed
$result.ContractError=$contractError
$metadata.Executions=@($result)
Save-RunnerReport $evidence @($result) $metadata $root $sources
Write-Host ('RUNTIME_RELEASED PID='+$process.Id+' exit='+$code+' seconds='+$result.DurationSeconds+' SourceChanged='+$metadata.SourceChanged)
$remaining=@(Get-CimInstance Win32_Process -Filter "Name LIKE 'Godot%'"|Select-Object ProcessId,ParentProcessId,CommandLine)
$remaining|ConvertTo-Json -Depth 3|Set-Content -LiteralPath (Join-Path $evidence 'processes-after.json') -Encoding utf8
Write-Output ($result|ConvertTo-Json -Compress)
if($metadata.SourceChanged -eq $true){throw 'Fontes mudaram durante medicao; amostra nao e comparativo estavel'}

if($code -ne 0 -or -not $finished -or -not $contractPassed -or -not $logsPassed){throw ('Teardown regression failed: '+$contractError+' '+$logsError)}
