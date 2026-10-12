param(
    [Parameter(Mandatory = $true)][ValidateSet('Start', 'Watch')][string]$Mode,
    [Parameter(Mandatory = $true)][ValidateRange(1, 2147483647)][int]$EditorPid,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-fA-F]{32}$')][string]$Token,
    [Parameter(Mandatory = $true)][string]$EditorExe,
    [Parameter(Mandatory = $true)][string]$ProjectRoot
)

$ErrorActionPreference = 'Stop'
$Token = $Token.ToLowerInvariant()
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\', '/')
$expectedRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\', '/')
if (-not [string]::Equals($ProjectRoot, $expectedRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'ProjectRoot nao corresponde ao projeto deste supervisor.'
}
$EditorExe = [IO.Path]::GetFullPath($EditorExe)
$stateDir = Join-Path $ProjectRoot ('.godot\usage-monitor\' + $Token)
$readyPath = Join-Path $stateDir 'ready.json'
$errorPath = Join-Path $stateDir 'error.json'
$cancelPath = Join-Path $stateDir 'cancel'
$requestPath = Join-Path $stateDir 'request.json'
$helperPath = Join-Path $PSScriptRoot 'UsageMonitorPause.ps1'
$currentSession = [Diagnostics.Process]::GetCurrentProcess().SessionId
$currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value

function Write-UsageState([string]$Name, [object]$Value) {
    $destination = Join-Path $stateDir $Name
    $temporary = $destination + '.tmp.' + $PID
    [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $destination -Force
}

function Get-UsageProcessRecord([int]$ProcessId) {
    Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -OperationTimeoutSec 2
}

function Assert-UsageOwner([object]$Record) {
    if ($null -eq $Record) { throw 'O processo terminou antes da verificacao de identidade.' }
    $owner = $Record | Invoke-CimMethod -MethodName GetOwnerSid -OperationTimeoutSec 2
    if ($null -eq $owner -or $owner.ReturnValue -ne 0 -or $owner.Sid -ne $currentSid) {
        throw 'O processo nao pertence ao usuario atual, ou sua identidade nao pode ser confirmada.'
    }
}

function Open-UsageEditor {
    $editor = [Diagnostics.Process]::GetProcessById($EditorPid)
    try {
        $null = $editor.Handle
        if ($editor.SessionId -ne $currentSession -or
            -not [string]::Equals($editor.MainModule.FileName, $EditorExe, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'PID, sessao ou executavel do editor nao correspondem ao pedido.'
        }
        Assert-UsageOwner (Get-UsageProcessRecord $EditorPid)
        return $editor
    }
    catch { $editor.Dispose(); throw }
}

function Quote-UsageArgument([string]$Value) {
    if ($Value.IndexOf('"') -ge 0 -or $Value.IndexOf("`r") -ge 0 -or $Value.IndexOf("`n") -ge 0) {
        throw 'Argumento de caminho invalido para o supervisor.'
    }
    return '"' + $Value + '"'
}

if ($Mode -eq 'Start') {
    $editor = $null
    $worker = $null
    $createdState = $false
    $readyConfirmed = $false
    $startExitCode = 0
    try {
        if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) { throw 'UsageMonitorPause.ps1 nao foi encontrado.' }
        if (Test-Path -LiteralPath $stateDir) { throw 'Token de sessao ja utilizado; gere outro token.' }
        $editor = Open-UsageEditor
        $null = New-Item -ItemType Directory -Path $stateDir
        $createdState = $true
        Write-UsageState 'request.json' @{
            schema = 1; token = $Token; editor_pid = $EditorPid
            editor_birth_ticks = $editor.StartTime.ToUniversalTime().Ticks.ToString()
            requested_utc = [DateTime]::UtcNow.ToString('o')
        }
        $workerArgs = @(
            '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
            '-File', (Quote-UsageArgument $PSCommandPath), '-Mode', 'Watch',
            '-EditorPid', $EditorPid.ToString(), '-Token', $Token,
            '-EditorExe', (Quote-UsageArgument $EditorExe),
            '-ProjectRoot', (Quote-UsageArgument $ProjectRoot)
        )
        $powershellPath = Join-Path ([Environment]::GetFolderPath('System')) 'WindowsPowerShell\v1.0\powershell.exe'
        # ShellExecute desacopla o worker dos pipes de OS.execute no editor.
        # O estado e os erros persistem em JSON; nao redirecionar estes streams.
        $workerStart = [Diagnostics.ProcessStartInfo]::new()
        $workerStart.FileName = $powershellPath
        $workerStart.Arguments = $workerArgs -join ' '
        $workerStart.WorkingDirectory = $ProjectRoot
        $workerStart.UseShellExecute = $true
        $workerStart.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
        $workerStart.RedirectStandardInput = $false
        $workerStart.RedirectStandardOutput = $false
        $workerStart.RedirectStandardError = $false
        $worker = [Diagnostics.Process]::Start($workerStart)
        if ($null -eq $worker) { throw 'O Windows nao retornou o processo do supervisor.' }
        $deadline = [Diagnostics.Stopwatch]::StartNew()
        while ($deadline.Elapsed.TotalSeconds -lt 45) {
            if (Test-Path -LiteralPath $errorPath) {
                $failure = [IO.File]::ReadAllText($errorPath) | ConvertFrom-Json
                throw [string]$failure.message
            }
            if (Test-Path -LiteralPath $readyPath) {
                $ready = [IO.File]::ReadAllText($readyPath) | ConvertFrom-Json
                if ($ready.token -ne $Token -or $ready.worker_pid -ne $worker.Id -or $ready.status -ne 'ready') {
                    throw 'Resposta de prontidao nao corresponde ao supervisor iniciado.'
                }
                $readyConfirmed = $true
                $ready | ConvertTo-Json -Compress
                break
            }
            if ($editor.HasExited) { throw 'O editor encerrou antes da prontidao.' }
            if ($worker.HasExited) { throw "O supervisor encerrou antes da prontidao (codigo $($worker.ExitCode))." }
            [Threading.Thread]::Sleep(50)
        }
        if (-not $readyConfirmed) { throw 'Tempo limite de 45 segundos aguardando a pausa do OpenUsage.' }
    }
    catch {
        $startExitCode = 1
        if ($createdState) {
            # O worker deve sair pelo finally; nunca e encerrado a forca.
            [IO.File]::WriteAllText($cancelPath, 'start_failed', [Text.UTF8Encoding]::new($false))
        }
        [Console]::Error.WriteLine($_.Exception.Message)
    }
    finally {
        if ($null -ne $worker) { $worker.Dispose() }
        if ($null -ne $editor) { $editor.Dispose() }
    }
    exit $startExitCode
}

$editor = $null
$mutex = $null
$mutexOwned = $false
$watchExitCode = 0
$outcome = @{
    schema = 1; token = $Token; editor_pid = $EditorPid; worker_pid = $PID
    status = 'waiting'; reason = ''; game_pid = $null; game_exit_code = $null
}
try {
    if (-not (Test-Path -LiteralPath $requestPath -PathType Leaf)) { throw 'Pedido de sessao nao encontrado.' }
    $request = [IO.File]::ReadAllText($requestPath) | ConvertFrom-Json
    if ($request.token -ne $Token -or $request.editor_pid -ne $EditorPid) { throw 'Pedido de sessao invalido.' }
    $editor = Open-UsageEditor
    if ($editor.StartTime.ToUniversalTime().Ticks.ToString() -ne $request.editor_birth_ticks) {
        throw 'O PID do editor foi reutilizado desde o pedido.'
    }
    $mutex = [Threading.Mutex]::new($false, "Local\GetecoEditorUsageMonitor_${currentSession}_${currentSid}")
    try { $mutexOwned = $mutex.WaitOne(10000) }
    catch [Threading.AbandonedMutexException] { $mutexOwned = $true }
    if (-not $mutexOwned) { throw 'Outra sessao do editor ainda esta restaurando o OpenUsage (limite de 10 segundos).' }
    if ($editor.HasExited -or (Test-Path -LiteralPath $cancelPath)) { throw 'Sessao cancelada antes da pausa.' }
    . $helperPath
    Invoke-WithUsageMonitorPaused {
        if ($editor.HasExited -or (Test-Path -LiteralPath $cancelPath)) {
            $outcome.status = 'cancelled'
            $outcome.reason = 'cancelled_before_ready'
            return
        }
        $readyUtc = [DateTime]::UtcNow
        Write-UsageState 'ready.json' @{
            schema = 1; status = 'ready'; token = $Token; editor_pid = $EditorPid
            worker_pid = $PID; ready_utc = $readyUtc.ToString('o')
        }
        $attachDeadline = [Diagnostics.Stopwatch]::StartNew()
        $noncePattern = '(?:^|\s)"?--geteco-usage-session=' + [regex]::Escape($Token) + '"?(?=\s|$)'
        while ($attachDeadline.Elapsed.TotalSeconds -lt 30) {
            if ($editor.HasExited -or (Test-Path -LiteralPath $cancelPath)) {
                $outcome.status = 'cancelled'
                $outcome.reason = 'editor_exited_or_cancelled_before_attach'
                return
            }
            $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId = $EditorPid" -OperationTimeoutSec 2)
            foreach ($child in $children) {
                if (-not [string]::Equals($child.ExecutablePath, $EditorExe, [StringComparison]::OrdinalIgnoreCase) -or
                    [string]$child.CommandLine -notmatch $noncePattern) { continue }
                $game = $null
                try {
                    try { $game = [Diagnostics.Process]::GetProcessById([int]$child.ProcessId) }
                    catch [ArgumentException] { continue }
                    $null = $game.Handle
                    if ($game.HasExited) { continue }
                    # Confirma novamente depois de fixar o handle contra reutilizacao de PID.
                    $record = Get-UsageProcessRecord $game.Id
                    if ($null -eq $record -or $record.ParentProcessId -ne $EditorPid -or
                        $game.SessionId -ne $currentSession -or
                        $game.StartTime.ToUniversalTime() -lt $readyUtc -or
                        -not [string]::Equals($game.MainModule.FileName, $EditorExe, [StringComparison]::OrdinalIgnoreCase) -or
                        [string]$record.CommandLine -notmatch $noncePattern) { continue }
                    Assert-UsageOwner $record
                    $outcome.game_pid = $game.Id
                    $outcome.game_birth_ticks = $game.StartTime.ToUniversalTime().Ticks.ToString()
                    $outcome.attached_utc = [DateTime]::UtcNow.ToString('o')
                    $outcome.status = 'attached'
                    Write-UsageState 'attached.json' $outcome
                    $self = [Diagnostics.Process]::GetCurrentProcess()
                    try { $cpuBefore = $self.TotalProcessorTime.TotalMilliseconds } finally { $self.Dispose() }
                    $waitClock = [Diagnostics.Stopwatch]::StartNew()
                    # Sem polling de processos/CPU depois de identificar o jogo.
                    $game.WaitForExit()
                    $waitClock.Stop()
                    $self = [Diagnostics.Process]::GetCurrentProcess()
                    try { $cpuAfter = $self.TotalProcessorTime.TotalMilliseconds } finally { $self.Dispose() }
                    $outcome.worker_cpu_ms_before_wait = $cpuBefore
                    $outcome.worker_cpu_ms_after_wait = $cpuAfter
                    $outcome.worker_wait_cpu_ms = $cpuAfter - $cpuBefore
                    $outcome.game_wait_seconds = $waitClock.Elapsed.TotalSeconds
                    $outcome.game_exit_code = $game.ExitCode
                    $outcome.status = 'finished'
                    $outcome.reason = 'game_exited'
                    return
                }
                finally { if ($null -ne $game) { $game.Dispose() } }
            }
            [Threading.Thread]::Sleep(200)
        }
        throw 'Nenhum filho Godot desta sessao iniciou em 30 segundos; restaurando OpenUsage.'
    }
}
catch {
    $watchExitCode = 1
    $outcome.status = 'error'
    $outcome.reason = $_.Exception.Message
    if (Test-Path -LiteralPath $stateDir -PathType Container) {
        Write-UsageState 'error.json' @{
            schema = 1; status = 'error'; token = $Token; worker_pid = $PID
            message = $_.Exception.Message; failed_utc = [DateTime]::UtcNow.ToString('o')
        }
    }
    [Console]::Error.WriteLine($_.Exception.Message)
}
finally {
    # Invoke-WithUsageMonitorPaused restaura antes de liberar a proxima sessao.
    if ($mutexOwned) { $mutex.ReleaseMutex() }
    if ($null -ne $mutex) { $mutex.Dispose() }
    if ($null -ne $editor) { $editor.Dispose() }
    $outcome.completed_utc = [DateTime]::UtcNow.ToString('o')
    if (Test-Path -LiteralPath $stateDir -PathType Container) { Write-UsageState 'result.json' $outcome }
}
exit $watchExitCode
