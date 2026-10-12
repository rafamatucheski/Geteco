param(
    [ValidateSet('legacy','directed')][string[]]$Modes = @('legacy','directed'),
    [string]$Output = '',
    [int]$DeadlineSeconds = 300
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $Output) { $Output = Join-Path $projectRoot ('evidence/voice-direction-20261012/rendered-' + (Get-Date -Format 'HHmmss')) }
$Output = [IO.Path]::GetFullPath($Output)
[IO.Directory]::CreateDirectory($Output) | Out-Null
. (Join-Path $projectRoot 'tools/Godot.ps1')
$engine = Resolve-ProjectGodot
Build-ProjectCSharp -Root $projectRoot -Engine $engine
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class DirectedVoiceWindow {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int mode);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint id);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
}
'@
$previousMode = $env:GETECO_DIRECTED_VOICES
$previousAppData = $env:APPDATA
$settingsSnapshot = Join-Path $Output 'settings-before.cfg'
$settingsSource = Join-Path $previousAppData 'GetecoV2/settings.cfg'
if (Test-Path -LiteralPath $settingsSource) {
    Copy-Item -LiteralPath $settingsSource -Destination $settingsSnapshot
}
function Get-VoiceSourceSnapshot {
    $rows = [ordered]@{}
    $sourceFiles = @(& rg --files $projectRoot -g '*.gd' -g '*.cs' -g 'project.godot' -g '!evidence/**' -g '!tools/**' -g '!tests/**' -g '!.godot/**')
    $sourceFiles += @('measure_directed_voice.gd', 'measure_performance_plan.gd', 'NativePresentationGate.gd') | ForEach-Object { Join-Path $PSScriptRoot $_ }
    foreach ($path in ($sourceFiles | Sort-Object -Unique)) {
        $rows[$path] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }
    return $rows
}
$sourceSnapshot = Get-VoiceSourceSnapshot
$sourceSnapshot | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $Output 'source-before.json')
try {
    foreach ($mode in $Modes) {
        $initial = @(Get-CimInstance Win32_Process -Filter "Name LIKE 'Godot%'" | Select-Object ProcessId,ParentProcessId,CommandLine)
        $foreign = @($initial | Where-Object { $_.CommandLine -notmatch '(^|\s)--editor(\s|$)' })
        if ($foreign.Count) { throw 'Another Godot run is active. Preserve it and measure in a quiet window.' }
        # Equal initial preferences in isolated user data; never touch player saves.
        $env:APPDATA = Join-Path $Output ($mode + '-appdata')
        $isolatedUser = Join-Path $env:APPDATA 'GetecoV2'
        [IO.Directory]::CreateDirectory($isolatedUser) | Out-Null
        if (Test-Path -LiteralPath $settingsSnapshot) {
            Copy-Item -LiteralPath $settingsSnapshot -Destination (Join-Path $isolatedUser 'settings.cfg')
        }
        $env:GETECO_DIRECTED_VOICES = if ($mode -eq 'legacy') { '0' } else { '1' }
        $label = 'voice-' + $mode
        $log = Join-Path $Output ($label + '.log')
        $err = Join-Path $Output ($label + '.err')
        $arguments = @('--path', ('"' + $projectRoot + '"'), '--script', 'res://tests/measure/measure_directed_voice.gd', '--',
                       '--no-save', '--skip-arrival', '--benchmark', ('--label=' + $label), ('--out="' + $Output.Replace('\','/') + '"'))
        $run = Start-Process -FilePath $engine -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $log -RedirectStandardError $err
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $samples = [Collections.Generic.List[object]]::new()
        $shown = $false
        $ownedChildren = @()
        while (-not $run.HasExited) {
            $active = @(Get-CimInstance Win32_Process -Filter "Name LIKE 'Godot%'" | Select-Object ProcessId,ParentProcessId,CommandLine)
            $ownedChildren = @($active | Where-Object { $_.ParentProcessId -eq $run.Id -and $_.CommandLine -match 'measure_directed_voice.gd' })
            $others = @($active | Where-Object { $_.ProcessId -ne $run.Id -and $_.ParentProcessId -ne $run.Id -and $_.CommandLine -notmatch '(^|\s)--editor(\s|$)' })
            $windowRows = @()
            foreach ($child in $ownedChildren) {
                $native = Get-Process -Id $child.ProcessId -ErrorAction SilentlyContinue
                if (-not $native) { continue }
                $handle = $native.MainWindowHandle
                if ($handle -eq [IntPtr]::Zero) { continue }
                if (-not $shown) {
                    [DirectedVoiceWindow]::ShowWindow($handle, 5) | Out-Null
                    [DirectedVoiceWindow]::SetForegroundWindow($handle) | Out-Null
                    $shown = $true
                }
                [uint32]$foregroundPid = 0
                [DirectedVoiceWindow]::GetWindowThreadProcessId([DirectedVoiceWindow]::GetForegroundWindow(), [ref]$foregroundPid) | Out-Null
                $windowRows += @{pid=$child.ProcessId; foreground_pid=$foregroundPid; visible=[DirectedVoiceWindow]::IsWindowVisible($handle); minimized=[DirectedVoiceWindow]::IsIconic($handle)}
            }
            $samples.Add(@{elapsed=$watch.Elapsed.TotalSeconds; utc=[DateTime]::UtcNow.ToString('o'); others=$others; windows=$windowRows})
            if ($watch.Elapsed.TotalSeconds -gt $DeadlineSeconds) {
                # Only the exact launcher/children created by this invocation.
                foreach ($child in $ownedChildren) { Stop-Process -Id $child.ProcessId -Force -ErrorAction SilentlyContinue }
                Stop-Process -Id $run.Id -Force -ErrorAction SilentlyContinue
                $samples | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $Output ($label + '-processes.json'))
                throw 'Directed voice measurement reached its finite deadline.'
            }
            Start-Sleep -Seconds 1
            $run.Refresh()
        }
        $run.WaitForExit()
        $samples | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $Output ($label + '-processes.json'))
        Get-Content -LiteralPath $log -Tail 3
        if ($run.ExitCode -ne 0) {
            Get-Content -LiteralPath $err -Tail 15
            throw "Directed voice measurement failed: $mode (exit $($run.ExitCode))"
        }
        if (@($samples | Where-Object { $_.others.Count -gt 0 }).Count) {
            throw 'Concurrent Godot process observed; preserve the report but do not approve this comparison.'
        }
        $sourceAfter = Get-VoiceSourceSnapshot
        $sourceAfter | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $Output ($label + '-source-after.json'))
        $changed = @($sourceSnapshot.Keys | Where-Object { $sourceAfter[$_] -ne $sourceSnapshot[$_] })
        $added = @($sourceAfter.Keys | Where-Object { -not $sourceSnapshot.Contains($_) })
        if ($changed.Count -or $added.Count) {
            @{changed=$changed; added=$added} | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $Output 'concurrent-source-changes.json')
            throw 'Production source changed during the comparison; preserve these results without approving them.'
        }
    }
} finally {
    $env:GETECO_DIRECTED_VOICES = $previousMode
    $env:APPDATA = $previousAppData
}
