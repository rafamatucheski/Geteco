param([Parameter(Mandatory = $true)][string]$Out)

$ErrorActionPreference = 'Stop'
$helper = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../tools/UsageMonitorPause.ps1'))
$expectedHash = '307613f60d83d4be8e4d5beec6e39bce7e46c659756a1d9d8b69d9ca7d7799a1'
$actualHash = (Get-FileHash -LiteralPath $helper -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualHash -ne $expectedHash) { throw 'Helper changed: inspect before running these mocks.' }
$expectedPath = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'OpenUsage\openusage.exe'
$expectedSession = [Diagnostics.Process]::GetCurrentProcess().SessionId
$expectedSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$script:Checks = @()
$script:Cases = @()

function Assert-Contract([bool]$Condition, [string]$Label) {
    $script:Checks += [ordered]@{ label = $Label; passed = $Condition }
}
function New-FakeProcess([int]$Id, [string]$Name, [string]$Path, [string]$Sid, [int]$Session, [bool]$WaitResult = $true) {
    $fake = [pscustomobject]@{
        Id = $Id; ProcessName = $Name; Path = $Path; Sid = $Sid; SessionId = $Session
        Handle = [IntPtr]1; HasExited = $false; WaitResult = $WaitResult
        KillCalls = 0; WaitArguments = @(); DisposeCalls = 0
    }
    $fake | Add-Member ScriptMethod Kill { $this.KillCalls++; $this.HasExited = $true }
    $fake | Add-Member ScriptMethod WaitForExit { param([int]$Milliseconds) $this.WaitArguments += $Milliseconds; return $this.WaitResult }
    $fake | Add-Member ScriptMethod Dispose { $this.DisposeCalls++ }
    return $fake
}
function Reset-Scenario([object[]]$Processes) {
    $script:MockProcesses = $Processes
    $script:Starts = @()
    $script:GameCalls = 0
}

# Todo comando que toca processos usado pelo auxiliar inspecionado é interceptado.
# Os objetos de processo abaixo são PSCustomObjects; os métodos deles não controlam processos do SO.
function Get-Process {
    param([string]$Name, [object]$ErrorAction)
    if ($Name -notin @('openusage', 'ccusage')) { throw "Unexpected process lookup: $Name" }
    @($script:MockProcesses | Where-Object { $_.ProcessName -ieq $Name -and -not $_.HasExited })
}
function Get-CimInstance {
    param([string]$ClassName, [string]$Filter)
    if ($ClassName -ne 'Win32_Process' -or $Filter -notmatch '^ProcessId = (\d+)$') { throw 'Unexpected CIM request' }
    $targetId = [int]$Matches[1]
    $found = @($script:MockProcesses | Where-Object { $_.Id -eq $targetId })
    if ($found.Count -ne 1) { throw 'Unknown mock process identity' }
    $found[0]
}
function Invoke-CimMethod {
    param([Parameter(ValueFromPipeline = $true)][object]$InputObject, [string]$MethodName)
    process {
        if ($MethodName -ne 'GetOwnerSid') { throw 'Unexpected CIM method' }
        [pscustomobject]@{ ReturnValue = 0; Sid = $InputObject.Sid }
    }
}
function Start-Process {
    param([string]$FilePath, [string]$WindowStyle)
    $script:Starts += [ordered]@{ path = $FilePath; window_style = $WindowStyle }
}
function Stop-Process { throw 'Unexpected Stop-Process; no real process operation is allowed.' }
. $helper

$wrongPath = New-FakeProcess 901 'openusage' 'C:\other\openusage.exe' $expectedSid $expectedSession
$wrongSid = New-FakeProcess 902 'openusage' $expectedPath 'S-1-5-21-test-other-user' $expectedSession
$wrongSession = New-FakeProcess 903 'openusage' $expectedPath $expectedSid ($expectedSession + 1)
Reset-Scenario @($wrongPath, $wrongSid, $wrongSession)
Invoke-WithUsageMonitorPaused { $script:GameCalls++ }
Assert-Contract ($wrongPath.KillCalls -eq 0) 'Same name with different path is not stopped'
Assert-Contract ($wrongSid.KillCalls -eq 0) 'Different SID is not stopped'
Assert-Contract ($wrongSession.KillCalls -eq 0) 'Different session is not stopped'
Assert-Contract ($script:Starts.Count -eq 0) 'Unselected processes do not trigger a restart'
Assert-Contract ($script:GameCalls -eq 1) 'Game callback runs once without a selected application'
$script:Cases += 'scope_guards'

$target = New-FakeProcess 904 'openusage' $expectedPath $expectedSid $expectedSession
Reset-Scenario @($target)
Invoke-WithUsageMonitorPaused { $script:GameCalls++ }
Assert-Contract ($target.KillCalls -eq 1) 'Success stops the selected object once'
Assert-Contract ($target.WaitArguments.Count -eq 1 -and $target.WaitArguments[0] -eq 10000) 'Success waits for the selected pinned object'
Assert-Contract ($script:GameCalls -eq 1) 'Success launches one game callback'
Assert-Contract ($script:Starts.Count -eq 1) 'Success restores once'
Assert-Contract ($script:Starts[0].path -eq $expectedPath -and $script:Starts[0].window_style -eq 'Hidden') 'Restoration uses the exact path in a hidden launch'
Assert-Contract ($target.DisposeCalls -eq 1) 'Selected object is disposed'
$script:Cases += 'success'

$target = New-FakeProcess 905 'openusage' $expectedPath $expectedSid $expectedSession
Reset-Scenario @($target)
$failure = $null
try { Invoke-WithUsageMonitorPaused { $script:GameCalls++; throw 'mock-game-failed' } }
catch { $failure = $_.Exception.Message }
Assert-Contract ($failure -eq 'mock-game-failed') 'Callback failure propagates unchanged'
Assert-Contract ($script:GameCalls -eq 1) 'Failing callback is invoked only once'
Assert-Contract ($script:Starts.Count -eq 1) 'Callback failure still restores once'
Assert-Contract ($target.KillCalls -eq 1 -and $target.DisposeCalls -eq 1) 'Callback failure preserves target lifecycle'
$script:Cases += 'callback_failure'

$target = New-FakeProcess 906 'openusage' $expectedPath $expectedSid $expectedSession
$worker = New-FakeProcess 907 'ccusage' 'C:\mock\ccusage.exe' $expectedSid $expectedSession $false
Reset-Scenario @($target, $worker)
$failure = $null
try { Invoke-WithUsageMonitorPaused { $script:GameCalls++ } }
catch { $failure = $_.Exception.Message }
Assert-Contract ($failure -like 'ccusage ainda esta ativo*') 'Worker timeout is propagated'
Assert-Contract ($script:GameCalls -eq 0) 'Worker timeout prevents game launch'
Assert-Contract ($worker.KillCalls -eq 0) 'Worker timeout never stops ccusage'
Assert-Contract ($worker.WaitArguments.Count -eq 1 -and $worker.WaitArguments[0] -gt 0 -and $worker.WaitArguments[0] -le 30000) 'Worker wait has one finite deadline'
Assert-Contract ($script:Starts.Count -eq 1) 'Worker timeout restores OpenUsage once'
Assert-Contract ($worker.DisposeCalls -eq 1 -and $target.DisposeCalls -eq 1) 'Worker timeout disposes mock handles'
$script:Cases += 'worker_timeout'

$failed = @($script:Checks | Where-Object { -not $_.passed })
$report = [ordered]@{
    schema = 1; helper = $helper; helper_sha256 = $actualHash
    cases = $script:Cases; checks = $script:Checks; passed = ($failed.Count -eq 0)
    scope = 'Four isolated scenarios with process commands mocked and PSCustomObject process methods. No real application was stopped, started or queried.'
    limitations = @('This tests control flow, not OS process permissions, real wait timings, restoration readiness or gameplay performance.')
}
$destination = [IO.Path]::GetFullPath($Out)
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
$bytes = [Text.UTF8Encoding]::new($false).GetBytes(($report | ConvertTo-Json -Depth 8))
$stream = [IO.File]::Open($destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
try { $stream.Write($bytes, 0, $bytes.Length) }
finally { $stream.Dispose() }
Write-Output "$($script:Checks.Count - $failed.Count)/$($script:Checks.Count) checks passed; $destination"
if ($failed.Count -gt 0) { exit 1 }
