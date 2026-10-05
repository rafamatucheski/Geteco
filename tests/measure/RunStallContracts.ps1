param(
    [string]$Project='D:/geteco/game/evidence/intermittent-stalls-20261004/cpu-box',
    [ValidatePattern('^[a-zA-Z0-9-]+$')][string]$Label='contracts',
    [string[]]$Tests=@('test_stall_log_intervals','test_terminal_lifecycle','test_terminal_gates','test_biarticulated_lifecycle')
)
$ErrorActionPreference='Stop'
foreach($test in $Tests) {
    if($test -notmatch '^test_[a-zA-Z0-9_]+$'){throw 'Invalid test name.'}
    if(-not (Test-Path -LiteralPath (Join-Path $Project "tests/$test.gd"))){throw "Test file not found before engine launch: $test"}
}
$base=Join-Path 'D:/geteco/game/evidence/intermittent-stalls-20261004' $Label
$engine='D:/Downloads Chrome/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe'
if(Test-Path -LiteralPath $base){throw 'Preserve prior contract evidence; use a new directory.'}
New-Item -ItemType Directory -Path $base | Out-Null
function Games { @(Get-CimInstance Win32_Process -Filter "Name LIKE 'Godot%'" | Where-Object { $_.CommandLine -notmatch '(^|\s)--editor(\s|$)' }) }
if(@(Games).Count){throw 'Another game/test is active.'}
$intervalSource='D:/geteco/game/tests/test_stall_log_intervals.gd'
$intervalTarget=Join-Path $Project 'tests/test_stall_log_intervals.gd'
if([IO.Path]::GetFullPath($intervalSource) -ne [IO.Path]::GetFullPath($intervalTarget)) {
    Copy-Item -LiteralPath $intervalSource -Destination $intervalTarget
}
Push-Location -LiteralPath $Project
try { & dotnet build Harbor.csproj --no-restore *> (Join-Path $base 'build.log'); if($LASTEXITCODE -ne 0){throw 'C# build failed'} } finally {Pop-Location}
$savedApp=$env:APPDATA
$savedLocal=$env:LOCALAPPDATA
$results=@()
try {
    $env:APPDATA=Join-Path $base 'user'
    $env:LOCALAPPDATA=Join-Path $base 'local'
    New-Item -ItemType Directory -Path $env:APPDATA,$env:LOCALAPPDATA -Force | Out-Null
    $env:HARBOR_NO_CSHARP=$null
    $env:HARBOR_STALL_LOG='0'
    foreach($test in $Tests) {
        if($test -notmatch '^test_[a-zA-Z0-9_]+$'){throw 'Invalid test name.'}
        if(@(Games).Count){throw 'Another game/test appeared; preserve its work.'}
        $proc=Start-Process -FilePath $engine -ArgumentList @('--headless','--path',$Project,'--script',"res://tests/$test.gd",'--','--no-save','--skip-arrival') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $base "$test.stdout.log") -RedirectStandardError (Join-Path $base "$test.stderr.log")
        $null=$proc.Handle
        $timer=[Diagnostics.Stopwatch]::StartNew()
        $invalid=''
        while(-not $proc.HasExited) {
            $active=@(Games)
            $foreign=@($active | Where-Object { $_.ProcessId -ne $proc.Id -and $_.ParentProcessId -ne $proc.Id })
            if($foreign.Count -or $timer.Elapsed.TotalSeconds -gt 120) {
                $invalid=if($foreign.Count){'concurrent_process'}else{'timeout'}
                foreach($owned in @($active | Where-Object { $_.ProcessId -eq $proc.Id -or $_.ParentProcessId -eq $proc.Id })) {Stop-Process -Id $owned.ProcessId -Force -ErrorAction SilentlyContinue}
                break
            }
            Start-Sleep -Milliseconds 500
            $proc.Refresh()
        }
        $proc.WaitForExit()
        $errors=@(Select-String -LiteralPath (Join-Path $base "$test.stderr.log") -Pattern 'SCRIPT ERROR|Parse Error|^ERROR:' | ForEach-Object {$_.Line})
        $results+=@{test=$test; exit_code=$proc.ExitCode; errors=$errors; invalid=$invalid; seconds=$timer.Elapsed.TotalSeconds}
        $results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $base 'results.json')
        Get-Content -LiteralPath (Join-Path $base "$test.stdout.log") -Tail 2
        if($invalid -or $proc.ExitCode -ne 0 -or $errors.Count){throw "Contract failed: $test"}
    }
} finally {$env:APPDATA=$savedApp; $env:LOCALAPPDATA=$savedLocal}
