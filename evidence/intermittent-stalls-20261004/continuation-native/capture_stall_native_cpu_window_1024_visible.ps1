# Elevated WPR helper ONLY. Build and gameplay runner stay in a normal terminal.
# Adapted from evidence/performance-implementation-20261002/capture-native-cpu.ps1.
# Finite owned window: requests stop 30..55 s after start-command invocation.
# StartMode NativeCreated starts before READY/loading; Ready permits delayed return coverage.
# Helpers/game remain separate. No profile/policy/process changes are made.
# Memory1024MiB is circular: final ETL can exclude earlier frames. Audit coverage.
# Example: .\evidence\intermittent-stalls-20261004\continuation-native\capture_stall_native_cpu_window_1024_visible.ps1 -Label stall1709-wpr-rec1 -StartMode Ready -StartDelaySeconds 85 -CaptureSeconds 40
# Then launch the normal runner with the same unused Label. This helper creates
# no run directory; the optional boot receipt is written before that runner.
# System-wide CPU/scheduling/module metadata; no FileIO/DiskIO/NetworkIO provider.
# 1024 MiB circular buffers are not a promise of complete time-window coverage.
# Check ETL start/end and event loss before interpreting native stacks.
# The deadline requests stop within 30..55 s; saving/cleanup
# have separate bounded command timeouts. An OS-level failure can need recovery.
# No power policy, sampling interval, registry, services or game processes change.
# Finally handles ordinary failures/Ctrl+C. Killing this helper/Windows can bypass
# finally: ownership.json contains the exact GUID and manual recovery commands.
param(
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$')][string]$Label,
    [ValidateRange(30,55)][int]$CaptureSeconds=55,
    [ValidateSet('NativeCreated','Ready')][string]$StartMode='Ready',
    [ValidateRange(0,90)][int]$StartDelaySeconds=0,
    [Alias('BootStatusPath')][string]$ReadyReceipt='',
    [switch]$ValidateOnly,
    [ValidateRange(1,300)][int]$ReadyTimeoutSeconds=300,
    [string]$AuditFolder='D:/geteco/game/evidence/intermittent-stalls-20261004',
    [ValidatePattern('^[A-Z][A-Z0-9_]{0,63}$')][string]$ReadyMarker='STALL_CAPTURE_READY',
    [ValidatePattern('^[A-Z][A-Z0-9_]{0,63}$')][string]$FinishMarker='STALL_CAPTURE_FINISHED'
)
$ErrorActionPreference='Stop'
$principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
$elevated=$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $elevated -and -not $ValidateOnly) {
    throw 'This WPR-only helper requires an authorized elevated terminal. No capture started. Keep build/game unelevated.'
}
$auditFolder=[IO.Path]::GetFullPath($AuditFolder)
$runFolder=Join-Path $auditFolder $Label
$captureFolder=Join-Path $runFolder 'native-cpu'
$profilePath='D:/geteco/game/evidence/intermittent-stalls-20261004/continuation-native/game-cpu-1024.wprp'
$wprPath=Join-Path $env:WINDIR 'System32/wpr.exe'
if (-not (Test-Path -LiteralPath $wprPath) -or -not (Test-Path -LiteralPath $profilePath)) {
    throw 'WPR or the reviewed CPU profile is missing. No capture started.'
}
$profileXml=[xml](Get-Content -LiteralPath $profilePath -Raw)
if ($profileXml.WindowsPerformanceRecorder.Profiles.Profile.LoggingMode -ne 'Memory') {
    throw 'Expected the reviewed Memory profile; file-mode capture is not allowed by this helper.'
}
if ([int]$profileXml.WindowsPerformanceRecorder.Profiles.SystemCollector.BufferSize.Value -ne 1024 -or
    [int]$profileXml.WindowsPerformanceRecorder.Profiles.SystemCollector.Buffers.Value -ne 1024) {
    throw 'Expected the reviewed 1024 KiB x 1024 circular buffers.'
}
if ($ValidateOnly) {
    Write-Output ([ordered]@{ validated_only=$true; start_mode=$StartMode; start_delay_seconds=$StartDelaySeconds; capture_seconds=$CaptureSeconds;
        profile=$profilePath; profile_sha256=(Get-FileHash -LiteralPath $profilePath -Algorithm SHA256).Hash; elevated=$elevated;
        scope='Parameter/profile validation only: no WPR command, capture, process lookup or artifact write.' } | ConvertTo-Json -Compress)
    return
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
$wrapperProcessId=0
$wrapperStartUtc=$null
$wrapperImage=$null
$nativeImage=$null
$triggerAnchor=$null
$readyDetails=$null
$launchHash=$null
$idleStatus=$null
$failure=$null
$commandIndex=0
$helperProcess=[Diagnostics.Process]::GetCurrentProcess()
$helperCpuAtEntryMs=$helperProcess.TotalProcessorTime.TotalMilliseconds
$helperEntryQpc=[Diagnostics.Stopwatch]::GetTimestamp()
$state=[ordered]@{
    instance=$instance; label=$Label; audit_folder=$auditFolder; ready_marker=$ReadyMarker; finish_marker=$FinishMarker; helper_pid=$PID; helper_started_utc=[DateTime]::UtcNow.ToString('o')
    ready_timeout_seconds=$ReadyTimeoutSeconds; capture_deadline_seconds=$CaptureSeconds; start_mode=$StartMode; start_delay_seconds=$StartDelaySeconds
    deadline_scope='Stop request deadline; bounded save/cleanup command time is additional'
    logging_mode='Memory'; buffer_size_kib=1024; buffer_count=1024
    scope='System-wide CPU scheduling/stacks, process/module and power metadata; no file/network I/O event keywords'
    phase='waiting_for_runner'; commands=@(); log_errors=@(); capture_started=$false
    cleanup_status_matches_idle_baseline=$false; coverage_verified=$false; events_lost_verified=$false
    identity_query_calls=0; identity_query_wall_qpc=0L; identity_query_max_wall_qpc=0L
    observer_scope='Own helper CPU and owned WPR command CPU only. ETW/kernel recording overhead requires a separate controlled comparison.'
}

function Save-Status {
    try { $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statusPath -Encoding UTF8 }
    catch { Write-Warning ('Could not update capture status: '+$_.Exception.Message) }
}

function Get-ClockAnchor {
    $before=[Diagnostics.Stopwatch]::GetTimestamp()
    $utc=[DateTime]::UtcNow
    $after=[Diagnostics.Stopwatch]::GetTimestamp()
    return [ordered]@{qpc_before=$before; qpc_after=$after; frequency=[Diagnostics.Stopwatch]::Frequency; utc_filetime=$utc.ToFileTimeUtc(); utc=$utc.ToString('o')}
}

function Get-HelperCpuAnchor {
    $helperProcess.Refresh()
    return [ordered]@{qpc=[Diagnostics.Stopwatch]::GetTimestamp(); cpu_total_ms=$helperProcess.TotalProcessorTime.TotalMilliseconds;
        cpu_user_ms=$helperProcess.UserProcessorTime.TotalMilliseconds; cpu_kernel_ms=$helperProcess.PrivilegedProcessorTime.TotalMilliseconds}
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
        if ($commandStarted) {
            try {
                if ($process.HasExited) {
                    $result['cpu_total_ms']=$process.TotalProcessorTime.TotalMilliseconds
                    $result['cpu_user_ms']=$process.UserProcessorTime.TotalMilliseconds
                    $result['cpu_kernel_ms']=$process.PrivilegedProcessorTime.TotalMilliseconds
                }
            } catch { $result['cpu_query_error']=$_.Exception.Message }
        }
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

# Toolhelp metadata only. No command lines, environment, thread contexts or control.
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class GetecoWindowProcesses {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    public struct Entry {
        public uint size, usage, pid; public UIntPtr heap; public uint module, threads, parent;
        public int priority; public uint flags;
        [MarshalAs(UnmanagedType.ByValTStr,SizeConst=260)] public string image;
    }
    [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr CreateToolhelp32Snapshot(uint flags,uint pid);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool Process32FirstW(IntPtr snapshot, ref Entry entry);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool Process32NextW(IntPtr snapshot, ref Entry entry);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    public static Entry[] Snapshot() {
        var handle=CreateToolhelp32Snapshot(2,0);
        if(handle==new IntPtr(-1)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        try {
            var output=new List<Entry>();
            var entry=new Entry { size=(uint)Marshal.SizeOf(typeof(Entry)) };
            if(!Process32FirstW(handle,ref entry)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            do { output.Add(entry); } while(Process32NextW(handle,ref entry));
            if(Marshal.GetLastWin32Error()!=18) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            return output.ToArray();
        } finally { CloseHandle(handle); }
    }
}
'@

function Get-Identity([int]$ProcessId) {
    $began=[Diagnostics.Stopwatch]::GetTimestamp()
    $process=$null
    try {
        $process=Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        if ($null -eq $process) { return $null }
        if ($process.HasExited) { return $null }
        return [ordered]@{ pid=$ProcessId; start_utc=$process.StartTime.ToUniversalTime(); image=[IO.Path]::GetFullPath($process.MainModule.FileName) }
    } finally {
        if ($null -ne $process) { $process.Dispose() }
        $cost=[Diagnostics.Stopwatch]::GetTimestamp()-$began
        $state.identity_query_calls++
        $state.identity_query_wall_qpc+=$cost
        $state.identity_query_max_wall_qpc=[Math]::Max($state.identity_query_max_wall_qpc,$cost)
    }
}

function Identity-Matches([int]$ProcessId,[DateTime]$StartUtc,[string]$Image) {
    $facts=Get-Identity $ProcessId
    return ($null -ne $facts -and $facts.start_utc -eq $StartUtc -and $facts.image -ieq $Image)
}

function Game-StillMatchesLaunch {
    if ($gameProcessId -le 0 -or $null -eq $gameStartUtc -or $wrapperProcessId -le 0) { return $false }
    return ((Identity-Matches $gameProcessId $gameStartUtc $nativeImage) -and
        (Identity-Matches $wrapperProcessId $wrapperStartUtc $wrapperImage))
}

function Read-RunText {
    return (Get-Content -LiteralPath (Join-Path $runFolder 'stdout.log') -Raw -ErrorAction SilentlyContinue)
}

function Has-Finished([string]$Text) {
    return ($Text -match ('(?m)^'+[Regex]::Escape($FinishMarker)+'\s') -or
        (Test-Path -LiteralPath (Join-Path $runFolder 'validity.json')))
}

function Read-Ready([string]$Text) {
    $pattern='(?m)^'+[Regex]::Escape($ReadyMarker)+' '+[Regex]::Escape($Label)+' (\{[^\r\n]+\})\s*$'
    $matchesFound=[Regex]::Matches($Text,$pattern)
    if ($matchesFound.Count -gt 1) { throw 'Multiple matching READY records; refusing ambiguous process/clock.' }
    if ($matchesFound.Count -eq 0) { return $null }
    return ($matchesFound[0].Groups[1].Value | ConvertFrom-Json)
}

function Validate-Ready($Ready) {
    if ([int]$Ready.details.pid -ne $gameProcessId) { throw 'READY native PID differs from the validated wrapper child.' }
    $anchor=@($Ready.details.clock_anchor)
    if ($anchor.Count -ne 6 -or [long]$anchor[4] -ne [Diagnostics.Stopwatch]::Frequency -or
        [long]$anchor[0] -gt [long]$anchor[3] -or [long]$anchor[5] -le 0) {
        throw 'READY ClockAnchor missing/incompatible; observer-on capture is required.'
    }
    $readyUtc=[DateTime]::FromFileTimeUtc([long]$anchor[2])
    if ($readyUtc -lt $gameStartUtc -or $readyUtc -gt [DateTime]::UtcNow.AddSeconds(2)) {
        throw 'READY UTC precedes native process birth or is in the future.'
    }
    $state['ready_clock_anchor']=$anchor
    $state['ready_engine_usec']=[long]$Ready.engine_usec
    $state['ready_frame']=[long]$Ready.frame
    $state['ready_observed_utc']=[DateTime]::UtcNow.ToString('o')
    $state['ready_observed_anchor']=Get-ClockAnchor
}

if ($ReadyReceipt) {
    $receiptPath=[IO.Path]::GetFullPath($ReadyReceipt)
    $prefix=$auditFolder.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if (-not $receiptPath.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'Receipt must stay inside AuditFolder.' }
    if (-not (Test-Path -LiteralPath ([IO.Path]::GetDirectoryName($receiptPath)) -PathType Container)) { throw 'Receipt parent must already exist.' }
    $receipt=[ordered]@{ helper_pid=$PID; instance=$instance; elevated=$elevated; label=$Label; helper_path=$PSCommandPath;
        process_start_utc=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o'); profile_path=$profilePath;
        profile_sha256=(Get-FileHash -LiteralPath $profilePath -Algorithm SHA256).Hash;
        helper_sha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash; anchor=(Get-ClockAnchor);
        phase='elevated_ready_waiting_for_owned_runner'; recording_started=$false; start_mode=$StartMode; start_delay_seconds=$StartDelaySeconds; capture_seconds=$CaptureSeconds }
    $bytes=[Text.Encoding]::UTF8.GetBytes(($receipt | ConvertTo-Json -Depth 5))
    $stream=[IO.File]::Open($receiptPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    try { $stream.Write($bytes,0,$bytes.Length) } finally { $stream.Dispose() }
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
        output=$etlPath; buffers_mib=1024; mode='Memory'; maximum_capture_seconds=$CaptureSeconds; start_mode=$StartMode; start_delay_seconds=$StartDelaySeconds
        helper_path=$PSCommandPath; helper_sha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash
        recovery_status=('wpr -status -instancename '+$instance)
        recovery_stop=('wpr -stop "'+$etlPath+'" -skipPdbGen -instancename '+$instance)
        recovery_cancel=('wpr -cancel -instancename '+$instance)
        warning='Use only this exact instance for recovery. Memory mode is circular; inspect time coverage/event loss. Forced termination can bypass finally.'
    }
    $ownership | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $captureFolder 'ownership.json') -Encoding UTF8
    $state.phase='waiting_for_ready'
    Save-Status
    while ($true) {
        if ($readyClock.Elapsed.TotalSeconds -ge $ReadyTimeoutSeconds) { throw 'Owned native process/READY did not appear before deadline. No capture started.' }
        $launchPath=Join-Path $runFolder 'launch.json'
        $text=Read-RunText
        if (Has-Finished $text) { throw 'The selected run already finished. No capture started.' }
        if ($wrapperProcessId -eq 0 -and (Test-Path -LiteralPath $launchPath)) {
            # Runner writes this after Process.Start. Refuse old field "time".
            $launch=Get-Content -LiteralPath $launchPath -Raw | ConvertFrom-Json
            if ($null -eq $launch.utc -or $null -eq $launch.engine -or [int]$launch.pid -le 0) { throw 'launch.json lacks pid/utc/engine.' }
            $launchUtc=([DateTime]$launch.utc).ToUniversalTime()
            $wrapper=Get-Identity ([int]$launch.pid)
            if ($null -eq $wrapper) { throw 'Console wrapper already exited.' }
            $expectedConsole='D:/Downloads Chrome/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe'
            if ([IO.Path]::GetFullPath([string]$launch.engine) -ine [IO.Path]::GetFullPath($expectedConsole) -or
                $wrapper.image -ine [IO.Path]::GetFullPath($expectedConsole) -or
                [Math]::Abs(($wrapper.start_utc-$launchUtc).TotalSeconds) -gt 5) {
                throw 'Console wrapper image/start does not match Godot 4.7.2 .NET launch.utc; refusing stale/reused PID.'
            }
            $wrapperProcessId=$wrapper.pid; $wrapperStartUtc=$wrapper.start_utc; $wrapperImage=$wrapper.image
            $nativeImage=$wrapperImage -replace '_console\.exe$','.exe'
            $launchHash=(Get-FileHash -LiteralPath $launchPath -Algorithm SHA256).Hash
            $state['launch_sha256']=$launchHash
            $state['launch_utc']=$launchUtc.ToString('o')
            $state['console_wrapper_pid']=$wrapperProcessId
            $state['console_wrapper_start_utc']=$wrapperStartUtc.ToString('o')
            $state['console_wrapper_image']=$wrapperImage
        }
        if ($wrapperProcessId -gt 0) {
            if (-not (Identity-Matches $wrapperProcessId $wrapperStartUtc $wrapperImage)) { throw 'Console wrapper identity changed/exited before recording.' }
            if ((Get-FileHash -LiteralPath $launchPath -Algorithm SHA256).Hash -ne $launchHash) { throw 'launch.json changed during handshake.' }
            $ready=Read-Ready $text
            $entries=@([GetecoWindowProcesses]::Snapshot() | Where-Object { [int]$_.parent -eq $wrapperProcessId -and $_.image -ieq [IO.Path]::GetFileName($nativeImage) })
            if ($entries.Count -gt 1) { throw 'Multiple native Godot children; refusing ambiguous capture.' }
            if ($entries.Count -eq 1) {
                $native=Get-Identity ([int]$entries[0].pid)
                if ($null -ne $native) {
                    if ($native.image -ine $nativeImage -or $native.start_utc -lt $wrapperStartUtc) { throw 'Native child image/start guard failed.' }
                    if ($gameProcessId -gt 0 -and $gameProcessId -ne $native.pid) { throw 'Native child changed during handshake.' }
                    $gameProcessId=$native.pid; $gameStartUtc=$native.start_utc
                    $state['game_pid']=$gameProcessId; $state['game_start_utc']=$gameStartUtc.ToString('o'); $state['game_image']=$nativeImage
                    $state['native_parent_pid_verified']=$wrapperProcessId
                    if ($null -ne $ready) { Validate-Ready $ready; $readyDetails=$ready }
                    if ($StartMode -eq 'NativeCreated' -or $null -ne $readyDetails) {
                        $triggerAnchor=Get-ClockAnchor
                        $state['trigger_observed_anchor']=$triggerAnchor
                        $state['trigger_kind']=if ($StartMode -eq 'NativeCreated') {'owned_native_child_observed'} else {'ready_record_observed'}
                        break
                    }
                }
            } elseif ($null -ne $ready) {
                throw 'READY appeared without matching live native wrapper child.'
            }
        }
        Start-Sleep -Milliseconds 100
    }
    $state.phase='waiting_for_window'
    Save-Status
    $delayClock=[Diagnostics.Stopwatch]::StartNew()
    while ($delayClock.Elapsed.TotalSeconds -lt $StartDelaySeconds) {
        if (-not (Game-StillMatchesLaunch)) { throw 'Owned game/wrapper exited while waiting for delayed window.' }
        $text=Read-RunText
        if (Has-Finished $text) { throw 'Measurement finished before delayed capture window.' }
        if ($null -eq $readyDetails) {
            $ready=Read-Ready $text
            if ($null -ne $ready) { Validate-Ready $ready; $readyDetails=$ready }
        }
        Start-Sleep -Milliseconds 100
    }
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
    $state['capture_started_anchor']=Get-ClockAnchor
    $state['helper_cpu_at_recording_start']=Get-HelperCpuAnchor
    $state['actual_start_lag_from_trigger_seconds']=($state.capture_started_anchor.qpc_before-$triggerAnchor.qpc_after)/[double][Diagnostics.Stopwatch]::Frequency
    $state['requested_window_is_not_guaranteed']='Use decoded ETL first/last events and READY ClockAnchor to establish actual overlap. Start-command latency and circular eviction may omit intended frames.'
    $state.phase='recording'
    Save-Status
    while ($captureClock.Elapsed.TotalSeconds -lt $CaptureSeconds) {
        if (-not (Game-StillMatchesLaunch)) { $state['stop_reason']='game_exited'; break }
        $text=Read-RunText
        if ($null -eq $readyDetails) {
            $ready=Read-Ready $text
            if ($null -ne $ready) { Validate-Ready $ready; $readyDetails=$ready; Save-Status }
        }
        if (Has-Finished $text) {
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
        $state['stop_requested_anchor']=Get-ClockAnchor
        $state['helper_cpu_at_stop_request']=Get-HelperCpuAnchor
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
    try {
        $finalCpu=Get-HelperCpuAnchor
        $state['helper_cpu_at_exit']=$finalCpu
        $state['helper_cpu_since_entry_ms']=$finalCpu.cpu_total_ms-$helperCpuAtEntryMs
        $state['helper_wall_since_entry_ms']=($finalCpu.qpc-$helperEntryQpc)/[double][Diagnostics.Stopwatch]::Frequency*1000
        $state['identity_query_total_wall_ms']=$state.identity_query_wall_qpc/[double][Diagnostics.Stopwatch]::Frequency*1000
        $state['identity_query_max_wall_ms']=$state.identity_query_max_wall_qpc/[double][Diagnostics.Stopwatch]::Frequency*1000
    } catch { $state['helper_cpu_query_error']=$_.Exception.Message }
    $helperProcess.Dispose()
    $state.phase=if ($started -and $stopSucceeded -and $cleanupVerified -and $state.etl_exists -and $null -eq $failure) {'saved_needs_coverage_review'} else {'failed_or_cleanup_needs_review'}
    if ($ownsCaptureFolder) { Save-Status }
}
if ($null -ne $failure) { throw $failure }
if (-not $started -or -not $stopSucceeded -or -not $cleanupVerified -or -not $state.etl_exists) {
    throw ('Capture or cleanup is unconfirmed; inspect '+$statusPath+' and ownership.json. Never stop/cancel an unnamed or different WPR session.')
}
Write-Output ('Native CPU trace saved: '+$etlPath+'. Verify event loss and overlap with the measurement before drawing conclusions.')
