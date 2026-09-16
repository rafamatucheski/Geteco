<#
GETECO-PERF-03A-R2 — execução de um teste Godot com exclusão mútua atômica
entre processos (mesma máquina/sessão de desenvolvimento, inclusive entre
cópias A/B em worktrees diferentes) e timeout externo ao motor.

Por que existe: nesta rodada, duas baterias de teste em segundo plano
correram ao mesmo tempo por engano e travaram a máquina do usuário; um
processo anterior entrou num loop de erro e não conseguiu terminar por
conta própria, precisando ser encerrado manualmente. Este script fecha os
dois buracos: (1) um Mutex nomeado do Windows (não um arquivo de lock —
não precisa de limpeza manual se o processo cair, o sistema libera
sozinho) garante que nenhum segundo processo Godot de teste comece
enquanto um já está rodando, em QUALQUER cópia do projeto que use este
mesmo nome de mutex; (2) o processo Godot é iniciado com
Start-Process/-PassThru e monitorado com um timeout PRÓPRIO deste
script — funciona mesmo se o jogo entrar num loop de erro que nunca
retorna ao chamador sozinho — e ao expirar, só o PID iniciado por ESTE
script (e os processos filhos diretos dele) são finalizados; nunca por
nome de processo.

Uso:
  ./Invoke-GodotTestLocked.ps1 -ScriptPath res://tests/test_south_port.gd -Path D:/geteco/game -Run meu_teste -TimeoutSec 120
  ./Invoke-GodotTestLocked.ps1 -Command "--path D:/geteco/game --script res://tests/x.gd -- run=y" -Run y -TimeoutSec 180
  ./Invoke-GodotTestLocked.ps1 -ScriptPath res://tests/x.gd -Run y -NoWait   # só para verificar rejeição (seção 3 da entrega)

Saída: $OutDir/$Run.txt (log deduplicado) e um registro JSON acrescentado
em $OutDir/runner_log.jsonl com pid, comando, criado-em, início, fim,
exit code, timeout(bool), lock_wait_s.
#>
param(
    [string]$ScriptPath,
    [string]$Path = "D:/geteco/game",
    [Parameter(Mandatory=$true)][string]$Run,
    [string]$OutDir = "D:/geteco/game/tests/perf_audit_claude/results/runner_locked",
    [string]$Godot = 'D:/Downloads Chrome/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe',
    [string[]]$ExtraArgs = @(),
    [string[]]$RawArgList,  # só para verificação do mecanismo (seção 3): substitui a montagem --path/--script,
                             # permitindo testar com um executável leve (ex.: cmd.exe) em vez do Godot real.
    [int]$TimeoutSec = 120,
    [int]$LockWaitSec = 600,
    [switch]$NoWait   # não espera o lock; falha imediatamente se ocupado (uso: verificação da seção 3)
)

$MutexName = "Global\GETECO_GODOT_TEST_LOCK"
New-Item -ItemType Directory -Force $OutDir | Out-Null
$appdataDir = "$OutDir/${Run}_appdata"
New-Item -ItemType Directory -Force $appdataDir | Out-Null
$outFile = "$OutDir/$Run.txt"
$rawFile = "$OutDir/${Run}_raw.txt"
$logFile = "$OutDir/runner_log.jsonl"

$mutex = New-Object System.Threading.Mutex($false, $MutexName)
$lockWaitStart = Get-Date
$acquired = $false
try {
    if ($NoWait.IsPresent) {
        $acquired = $mutex.WaitOne(0)
    } else {
        $acquired = $mutex.WaitOne([TimeSpan]::FromSeconds($LockWaitSec))
    }
} catch [System.Threading.AbandonedMutexException] {
    # Dono anterior encerrou sem liberar (ex.: crash) — o .NET já nos deu a
    # posse do mutex ao lançar esta exceção; registramos e seguimos.
    $acquired = $true
}
$lockWaitSec = [math]::Round(((Get-Date) - $lockWaitStart).TotalSeconds, 2)

if (-not $acquired) {
    $result = [pscustomobject]@{
        run = $Run; rejected = $true; reason = "lock ocupado por outro processo Godot de teste"
        lock_wait_s = $lockWaitSec; timestamp = (Get-Date -Format o)
    }
    $result | ConvertTo-Json -Compress | Add-Content -Encoding utf8 $logFile
    "REJECTED run=$Run motivo=lock_ocupado lock_wait_s=$lockWaitSec" | Tee-Object -FilePath $outFile
    return $result
}

try {
    $env:APPDATA = (Resolve-Path $appdataDir).Path -replace '/', '\'
    if ($RawArgList) {
        $argList = $RawArgList
    } else {
        $argList = @('--path', $Path, '--script', $ScriptPath)
        if ($ExtraArgs.Count -gt 0) { $argList += '--'; $argList += $ExtraArgs }
    }
    $commandLine = "$Godot $($argList -join ' ')"

    # Process direto (não o cmdlet Start-Process): neste ambiente,
    # Start-Process -PassThru não expõe ExitCode de forma confiável mesmo
    # depois do processo terminar (verificado na seção 3 da entrega) — a
    # API .NET abaixo é a que de fato retorna o código de saída real.
    $quotedArgs = $argList | ForEach-Object { if ($_ -match '[\s]') { '"' + $_ + '"' } else { $_ } }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Godot
    $psi.Arguments = ($quotedArgs -join ' ')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $startTime = Get-Date
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $outBuilder = New-Object System.Text.StringBuilder
    $errBuilder = New-Object System.Text.StringBuilder
    $outAction = { if ($null -ne $EventArgs.Data) { [void]$Event.MessageData.AppendLine($EventArgs.Data) } }
    Register-ObjectEvent -InputObject $proc -EventName OutputDataReceived -Action $outAction -MessageData $outBuilder | Out-Null
    Register-ObjectEvent -InputObject $proc -EventName ErrorDataReceived -Action $outAction -MessageData $errBuilder | Out-Null
    [void]$proc.Start()
    $proc.BeginOutputReadLine()
    $proc.BeginErrorReadLine()
    $creationTime = try { $proc.StartTime } catch { $startTime }

    $finishedInTime = $proc.WaitForExit($TimeoutSec * 1000)
    $endTime = Get-Date
    $timedOut = -not $finishedInTime
    $exitCode = -1

    if ($timedOut) {
        # Encerra só o que este script iniciou: o PID do próprio processo e
        # seus filhos diretos (o console.exe do Godot normalmente inicia um
        # processo motor filho) — nunca por nome de processo.
        try {
            $children = Get-CimInstance Win32_Process -Filter "ParentProcessId=$($proc.Id)" -ErrorAction SilentlyContinue
            foreach ($c in $children) { Stop-Process -Id $c.ProcessId -Force -ErrorAction SilentlyContinue }
        } catch {}
        try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
        Start-Sleep -Milliseconds 500
    } else {
        $proc.WaitForExit()  # garante que os eventos assíncronos de stdout/stderr já foram entregues
        $exitCode = $proc.ExitCode
    }
    Get-EventSubscriber | Where-Object { $_.SourceObject -eq $proc } | Unregister-Event -ErrorAction SilentlyContinue
    ($outBuilder.ToString() + $errBuilder.ToString()) | Out-File -Encoding utf8 $rawFile

    # Deduplica linhas repetidas consecutivas (o loop de erro que travou a
    # máquina do usuário reimprimia a mesma linha centenas de vezes) —
    # preserva a primeira ocorrência de cada assinatura e uma contagem.
    if (Test-Path $rawFile) {
        $lines = Get-Content -Path $rawFile -ErrorAction SilentlyContinue
        $dedup = @()
        $prev = $null; $count = 0
        foreach ($line in $lines) {
            if ($line -eq $prev) { $count++ }
            else {
                if ($prev -ne $null -and $count -gt 1) { $dedup[-1] = "$prev  (repetida x$count)" }
                $dedup += $line
                $prev = $line; $count = 1
            }
        }
        if ($prev -ne $null -and $count -gt 1) { $dedup[-1] = "$prev  (repetida x$count)" }
        $dedup | Out-File -Encoding utf8 $outFile
    }
    if ($timedOut) {
        "--- TIMEOUT: processo (pid=$($proc.Id)) e filhos diretos finalizados após ${TimeoutSec}s sem retornar ---" | Add-Content -Encoding utf8 $outFile
    }

    $result = [pscustomobject]@{
        run = $Run; rejected = $false; pid = $proc.Id; command = $commandLine
        created_at = $creationTime.ToString("o"); started_at = $startTime.ToString("o"); ended_at = $endTime.ToString("o")
        wall_s = [math]::Round(($endTime - $startTime).TotalSeconds, 2)
        exit_code = $exitCode; timed_out = $timedOut; lock_wait_s = $lockWaitSec
        timeout_sec_param = $TimeoutSec
    }
    $result | ConvertTo-Json -Compress | Add-Content -Encoding utf8 $logFile
    return $result
} finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
