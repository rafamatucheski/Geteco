# Elevated WPR helper ONLY. Build and gameplay runner stay in a normal terminal.
# Adapted from evidence/performance-implementation-20261002/capture-native-cpu.ps1.
# First-passage scheduling capture only: 55 s does not cover the 180 s route.
# Example: .\tests\measure\capture_stall_native_cpu.ps1 -Label first-passage-01
# Then launch the normal runner with the same unused Label. This helper creates
# nothing until that runner creates its run directory, and waits for its READY.
# System-wide CPU/scheduling/module metadata; no FileIO/DiskIO/NetworkIO provider.
# 256 MiB circular buffers are not a promise of complete time-window coverage.
# Check ETL start/end and event loss before interpreting native stacks.
# The deadline requests stop within 55 s (50-60 configurable); saving/cleanup
# have separate bounded command timeouts. An OS-level failure can need recovery.
# No power policy, sampling interval, registry, services or game processes change.
# Finally handles ordinary failures/Ctrl+C. Killing this helper/Windows can bypass
# finally: ownership.json contains the exact GUID and manual recovery commands.
param(
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$')][string]$Label,
    [ValidateRange(50,60)][int]$CaptureSeconds=55,
    [ValidateRange(1,300)][int]$ReadyTimeoutSeconds=300,
    [string]$AuditFolder='D:/geteco/game/evidence/intermittent-stalls-20261004',
    [ValidatePattern('^[A-Z][A-Z0-9_]{0,63}$')][string]$ReadyMarker='STALL_CAPTURE_READY',
    [ValidatePattern('^[A-Z][A-Z0-9_]{0,63}$')][string]$FinishMarker='STALL_CAPTURE_FINISHED'
)
$ErrorActionPreference='Stop'
$principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'This WPR-only helper requires an authorized elevated terminal. No capture started. Keep build/game unelevated.'
}
$auditFolder=[IO.Path]::GetFullPath($AuditFolder)
$runFolder=Join-Path $auditFolder $Label
$captureFolder=Join-Path $runFolder 'native-cpu'
$profilePath='D:/geteco/game/evidence/performance-implementation-20261002/game-cpu.wprp'
$wprPath=Join-Path $env:WINDIR 'System32/wpr.exe'
if (-not (Test-Path -LiteralPath $wprPath) -or -not (Test-Path -LiteralPath $profilePath)) {
    throw 'WPR or the reviewed CPU profile is missing. No capture started.'
}
$profileXml=[xml](Get-Content -LiteralPath $profilePath -Raw)
if ($profileXml.WindowsPerformanceRecorder.Profiles.Profile.LoggingMode -ne 'Memory') {
    throw 'Expected the reviewed Memory profile; file-mode capture is not allowed by this helper.'
}
$instance='GetecoAudit-'+[Guid]::NewGuid().ToString('N')
$etlPath=Join-Path $captureFolder 'cpu.etl'
$statusPath=Join-Path $captureFolder 'status.json'
$readyClock=[Diagnostics.Stopwatch]::StartNew()
$captureClock=$null
$ownsCaptureFolder=$false
$attempted=$false
$started=$false
$stopSucceeded=$false
$cleanupVerified=$false
$gameProcessId=0
$gameStartUtc=$null
$idleStatus=$null
$failure=$null
$commandIndex=0
$state=[ordered]@{
    instance=$instance; label=$Label; audit_folder=$auditFolder; ready_marker=$ReadyMarker; finish_marker=$FinishMarker; helper_pid=$PID; helper_started_utc=[DateTime]::UtcNow.ToString('o')
    ready_timeout_seconds=$ReadyTimeoutSeconds; capture_deadline_seconds=$CaptureSeconds
    deadline_scope='Stop request deadline; bounded save/cleanup command time is additional'
    logging_mode='Memory'; buffer_size_kib=1024; buffer_count=256
    scope='System-wide CPU scheduling/stacks, process/module and power metadata; no file/network I/O event keywords'
    phase='waiting_for_runner'; commands=@(); log_errors=@(); capture_started=$false
    cleanup_status_matches_idle_baseline=$false; coverage_verified=$false; events_lost_verified=$false
}

function Save-Status {
    try { $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statusPath -Encoding UTF8 }
    catch { Write-Warning ('Could not update capture status: '+$_.Exception.Message) }
}

function Invoke-OwnedWpr([string]$Operation,[string[]]$Arguments,[int]$TimeoutSeconds) {
    # Direct executable invocation, never a shell. Every operation is scoped to
    # the unique instance and -instancename remains the final WPR parameter.
    foreach ($argument in $Arguments) {
        if ($argument -match '["\r\n\x00]') { throw 'Unexpected character in WPR argument' }
    }
    $script:commandIndex++
    $prefix=Join-Path $captureFolder ('{0:D2}-{1}' -f $script:commandIndex,$Operation)
    $allArguments=@($Arguments)+@('-instancename',$instance)
    $info=[Diagnostics.ProcessStartInfo]::new()
    $info.FileName=$wprPath
    $info.Arguments=($allArguments | ForEach-Object { '"'+$_+'"' }) -join ' '
    $info.UseShellExecute=$false
    $info.CreateNoWindow=$true
    $info.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
    $info.RedirectStandardOutput=$true
    $info.RedirectStandardError=$true
    $process=[Diagnostics.Process]::new()
    $process.StartInfo=$info
    $commandStarted=$false
    $result=[ordered]@{operation=$Operation; arguments=$allArguments; begin_utc=[DateTime]::UtcNow.ToString('o'); timeout_seconds=$TimeoutSeconds; timed_out=$false; exit_code=$null; stdout=''; stderr=''}
    try {
        if (-not $process.Start()) { throw 'WPR process could not be started' }
        $commandStarted=$true
        $result['pid']=$process.Id
        $stdoutTask=$process.StandardOutput.ReadToEndAsync()
        $stderrTask=$process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds*1000)) {
            $result.timed_out=$true
            # Killing this owned command does not stop ETW; outer finally still
            # stops/cancels the uniquely named recording, including partial start.
            try { $process.Kill() } catch { $result['kill_error']=$_.Exception.Message }
            $null=$process.WaitForExit(2000)
        }
        if ($process.HasExited) {
            $result.exit_code=$process.ExitCode
            $null=$stdoutTask.Wait(1000)
            $null=$stderrTask.Wait(1000)
        }
        if ($stdoutTask.IsCompleted) { $result.stdout=$stdoutTask.Result }
        if ($stderrTask.IsCompleted) { $result.stderr=$stderrTask.Result }
    } catch {
        $result['error']=$_.Exception.Message
    } finally {
        if ($commandStarted) {
            try {
                if (-not $process.HasExited) { $process.Kill(); $null=$process.WaitForExit(2000) }
            } catch { $result['final_command_cleanup_error']=$_.Exception.Message }
        }
        $result['end_utc']=[DateTime]::UtcNow.ToString('o')
        $process.Dispose()
    }
    $state.commands+=@($result)
    try {
        $result.stdout | Set-Content -LiteralPath ($prefix+'.stdout.log') -Encoding UTF8
        $result.stderr | Set-Content -LiteralPath ($prefix+'.stderr.log') -Encoding UTF8
    } catch { $state.log_errors+=@($_.Exception.Message) }
    Save-Status
    return $result
}

function Game-StillMatchesLaunch {
    if ($gameProcessId -le 0 -or $null -eq $gameStartUtc) { return $false }
    $process=Get-Process -Id $gameProcessId -ErrorAction SilentlyContinue
    if ($null -eq $process) { return $false }
    try { return $process.StartTime.ToUniversalTime() -eq $gameStartUtc }
    catch { return $false }
    finally { $process.Dispose() }
}

try {
    # Never create runFolder: the normal runner must own its directory first.
    while (-not (Test-Path -LiteralPath $runFolder -PathType Container)) {
        if ($readyClock.Elapsed.TotalSeconds -ge $ReadyTimeoutSeconds) { throw 'Runner directory did not appear before the deadline. No capture started.' }
        Start-Sleep -Milliseconds 250
    }
    if (Test-Path -LiteralPath $captureFolder) { throw 'This run already has a native-cpu capture directory; choose a fresh Label.' }
    New-Item -ItemType Directory -Path $captureFolder | Out-Null
    $ownsCaptureFolder=$true
    # Persistent ownership exists BEFORE any attempt to start an ETW session.
    $ownership=[ordered]@{
        instance=$instance; label=$Label; helper_pid=$PID; created_utc=[DateTime]::UtcNow.ToString('o')
        wpr=$wprPath; profile=$profilePath; profile_sha256=(Get-FileHash -LiteralPath $profilePath -Algorithm SHA256).Hash
        output=$etlPath; buffers_mib=256; mode='Memory'; maximum_capture_seconds=$CaptureSeconds
        recovery_status=('wpr -status -instancename '+$instance)
        recovery_stop=('wpr -stop "'+$etlPath+'" -skipPdbGen -instancename '+$instance)
        recovery_cancel=('wpr -cancel -instancename '+$instance)
        warning='Use only this exact instance for recovery. Memory mode is circular; inspect time coverage/event loss. Forced termination can bypass finally.'
    }
    $ownership | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $captureFolder 'ownership.json') -Encoding UTF8
    $state.phase='waiting_for_ready'
    Save-Status
    while ($true) {
        if ($readyClock.Elapsed.TotalSeconds -ge $ReadyTimeoutSeconds) { throw 'READY did not appear before the deadline. No capture started.' }
        $launchPath=Join-Path $runFolder 'launch.json'
        $stdoutPath=Join-Path $runFolder 'stdout.log'
        $text=Get-Content -LiteralPath $stdoutPath -Raw -ErrorAction SilentlyContinue
        if ($text -match ('(?m)^'+[Regex]::Escape($FinishMarker)+'\s') -or (Test-Path -LiteralPath (Join-Path $runFolder 'validity.json'))) {
            throw 'The selected run already finished. No capture started.'
        }
        if ((Test-Path -LiteralPath $launchPath) -and $text -match ('(?m)^'+[Regex]::Escape($ReadyMarker)+' '+[Regex]::Escape($Label)+' ')) {
            $launch=Get-Content -LiteralPath $launchPath -Raw | ConvertFrom-Json
            $gameProcessId=[int]$launch.pid
            $game=Get-Process -Id $gameProcessId -ErrorAction SilentlyContinue
            if ($null -eq $game) { throw 'The selected game process exited before capture.' }
            try {
                $gameStartUtc=$game.StartTime.ToUniversalTime()
                if ([Math]::Abs(($gameStartUtc-([DateTime]$launch.time).ToUniversalTime()).TotalSeconds) -gt 15) {
                    throw 'Process start does not match launch.json; refusing a stale/reused PID.'
                }
            } finally { $game.Dispose() }
            break
        }
        Start-Sleep -Milliseconds 250
    }
    $state['ready_observed_utc']=[DateTime]::UtcNow.ToString('o')
    $state['game_pid']=$gameProcessId
    $state['game_start_utc']=$gameStartUtc.ToString('o')
    $idleStatus=Invoke-OwnedWpr 'status-before' @('-status') 5
    if ($idleStatus.timed_out -or $idleStatus.Contains('error')) { throw 'Cannot query the new WPR instance before recording.' }
    if (-not (Game-StillMatchesLaunch)) { throw 'Game exited while preparing capture.' }
    $state.phase='starting'
    Save-Status
    $attempted=$true
    $captureClock=[Diagnostics.Stopwatch]::StartNew()
    $start=Invoke-OwnedWpr 'start' @('-start',($profilePath+'!GameCpu')) 10
    if ($start.timed_out -or $start.exit_code -ne 0 -or $start.Contains('error')) {
        throw 'WPR start failed. Inspect start logs; this helper will clean only its own instance.'
    }
    $started=$true
    $state.capture_started=$true
    $state['capture_started_utc']=[DateTime]::UtcNow.ToString('o')
    $state.phase='recording'
    Save-Status
    while ($captureClock.Elapsed.TotalSeconds -lt $CaptureSeconds) {
        if (-not (Game-StillMatchesLaunch)) { $state['stop_reason']='game_exited'; break }
        $text=Get-Content -LiteralPath (Join-Path $runFolder 'stdout.log') -Raw -ErrorAction SilentlyContinue
        if ($text -match ('(?m)^'+[Regex]::Escape($FinishMarker)+'\s') -or (Test-Path -LiteralPath (Join-Path $runFolder 'validity.json'))) {
            $state['stop_reason']='measurement_finished'; break
        }
        Start-Sleep -Milliseconds 250
    }
    if (-not $state.Contains('stop_reason')) { $state['stop_reason']='capture_deadline' }
} catch {
    $failure=$_.Exception.Message
    $state['failure']=$failure
} finally {
    if ($attempted) {
        $state.phase='stopping'
        $state['stop_requested_utc']=[DateTime]::UtcNow.ToString('o')
        Save-Status
        try {
            $stop=Invoke-OwnedWpr 'stop' @('-stop',$etlPath,'-skipPdbGen') 45
            $stopSucceeded=(-not $stop.timed_out -and $stop.exit_code -eq 0 -and -not $stop.Contains('error'))
        } catch { $state['stop_error']=$_.Exception.Message }
        # Also covers partial starts and unsuccessful saves. A no-recording
        # response after a successful stop is expected; never cancel globally.
        try { $null=Invoke-OwnedWpr 'cancel-owned' @('-cancel') 10 }
        catch { $state['cancel_error']=$_.Exception.Message }
        try {
            $after=Invoke-OwnedWpr 'status-after' @('-status') 5
            $cleanupVerified=($null -ne $idleStatus -and -not $after.timed_out -and -not $after.Contains('error') -and
                $after.exit_code -eq $idleStatus.exit_code -and
                $after.stdout.Trim() -eq $idleStatus.stdout.Trim() -and $after.stderr.Trim() -eq $idleStatus.stderr.Trim())
        } catch { $state['status_error']=$_.Exception.Message }
    }
    $state['capture_started']=$started
    $state['stop_succeeded']=$stopSucceeded
    $state['cleanup_status_matches_idle_baseline']=$cleanupVerified
    $traceFile=Get-Item -LiteralPath $etlPath -ErrorAction SilentlyContinue
    $state['etl_exists']=($null -ne $traceFile -and $traceFile.Length -gt 0)
    $state['etl_bytes']=if ($null -ne $traceFile) { $traceFile.Length } else { 0 }
    $state['finished_utc']=[DateTime]::UtcNow.ToString('o')
    $state.phase=if ($started -and $stopSucceeded -and $cleanupVerified -and $state.etl_exists -and $null -eq $failure) {'saved_needs_coverage_review'} else {'failed_or_cleanup_needs_review'}
    if ($ownsCaptureFolder) { Save-Status }
}
if ($null -ne $failure) { throw $failure }
if (-not $started -or -not $stopSucceeded -or -not $cleanupVerified -or -not $state.etl_exists) {
    throw ('Capture or cleanup is unconfirmed; inspect '+$statusPath+' and ownership.json. Never stop/cancel an unnamed or different WPR session.')
}
Write-Output ('Native CPU trace saved: '+$etlPath+'. Verify event loss and overlap with the measurement before drawing conclusions.')
