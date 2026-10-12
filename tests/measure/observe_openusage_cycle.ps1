param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('before_pause', 'paused', 'after_restore')]
    [string]$Stage,
    [Parameter(Mandatory = $true)]
    [string]$Out
)

# Read-only, one-shot lifecycle evidence. No process control or configuration edits.
$ErrorActionPreference = 'Stop'
$startedUtc = [DateTime]::UtcNow.ToString('O')
$qpcBefore = [Diagnostics.Stopwatch]::GetTimestamp()
$expectedExe = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'OpenUsage/openusage.exe'))
$settingsPath = [IO.Path]::GetFullPath((Join-Path $env:APPDATA 'com.mesomya.openusage/settings.json'))
$processRows = @()
foreach ($processName in @('OpenUsage', 'ccusage')) {
    foreach ($observedProcess in @(Get-Process -Name $processName -ErrorAction SilentlyContinue)) {
        $record = [ordered]@{
            pid = $observedProcess.Id
            name = $observedProcess.ProcessName
            image_path = $null
            creation_utc = $null
            birth_filetime_utc = $null
            identity_stable = $false
            read_error = $null
        }
        try {
            $birth = $observedProcess.StartTime.ToUniversalTime()
            $record.image_path = $observedProcess.MainModule.FileName
            $record.creation_utc = $birth.ToString('O')
            $record.birth_filetime_utc = $birth.ToFileTimeUtc()
            $record.identity_stable = (-not $observedProcess.HasExited) -and ($observedProcess.StartTime.ToUniversalTime() -eq $birth)
        }
        catch {
            $record.read_error = $_.Exception.GetType().FullName
        }
        finally {
            $observedProcess.Dispose()
        }
        $processRows += $record
    }
}

$settings = [ordered]@{ path = $settingsPath; exists = [IO.File]::Exists($settingsPath); sha256 = $null; bytes = $null; stable_during_hash = $null }
if ($settings.exists) {
    $before = Get-Item -LiteralPath $settingsPath
    $settings.sha256 = (Get-FileHash -LiteralPath $settingsPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $after = Get-Item -LiteralPath $settingsPath
    $settings.bytes = $after.Length
    $settings.stable_during_hash = ($before.Length -eq $after.Length) -and ($before.LastWriteTimeUtc -eq $after.LastWriteTimeUtc)
}
$expectedOpenUsage = @($processRows | Where-Object {
    $_.name -ieq 'OpenUsage' -and $_.identity_stable -and $_.image_path -ieq $expectedExe
})
$report = [ordered]@{
    schema = 1
    stage = $Stage
    started_utc = $startedUtc
    finished_utc = [DateTime]::UtcNow.ToString('O')
    qpc_before = $qpcBefore
    qpc_after = [Diagnostics.Stopwatch]::GetTimestamp()
    qpc_frequency = [Diagnostics.Stopwatch]::Frequency
    observer_pid = $PID
    expected_openusage_exe = $expectedExe
    expected_openusage_process_count = $expectedOpenUsage.Count
    ccusage_process_count = @($processRows | Where-Object { $_.name -ieq 'ccusage' }).Count
    processes = @($processRows)
    settings = $settings
    limits = @(
        'One-shot read-only observation, not continuous absence proof. No application was controlled by this script.',
        'PID, path and birth identity may be unavailable for protected or exiting processes; read errors are retained.',
        'Settings are hashed as opaque bytes; their contents, credentials and environment are not exported.',
        'Use the separately recorded 2 Hz ProcessCpuProbe for window coverage; short-lived or inaccessible processes may be missed.'
    )
}
$destination = [IO.Path]::GetFullPath($Out)
$directory = [IO.Path]::GetDirectoryName($destination)
[IO.Directory]::CreateDirectory($directory) | Out-Null
$bytes = [Text.UTF8Encoding]::new($false).GetBytes(($report | ConvertTo-Json -Depth 8))
$stream = [IO.File]::Open($destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
try { $stream.Write($bytes, 0, $bytes.Length) }
finally { $stream.Dispose() }
Write-Output $destination
