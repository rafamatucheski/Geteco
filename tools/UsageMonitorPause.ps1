function Invoke-WithUsageMonitorPaused {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][scriptblock]$LaunchGame)

    $ErrorActionPreference = 'Stop'
    # Opt-in: somente esta instalacao, nesta sessao e sob o mesmo usuario.
    $usagePath = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'OpenUsage\openusage.exe'
    if (-not (Test-Path -LiteralPath $usagePath -PathType Leaf)) {
        & $LaunchGame
        return
    }
    $usageSession = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
    $usageSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $usageProcesses = @()
    $usageWorkers = @()
    $usageRestore = $false
    try {
        $usageProcesses = @(Get-Process -Name 'openusage' -ErrorAction SilentlyContinue)
        $usageTargets = @()
        foreach ($usageProcess in $usageProcesses) {
            # Manter o handle evita encerrar outro processo por reutilizacao do PID.
            $null = $usageProcess.Handle
            if ($usageProcess.SessionId -ne $usageSession -or
                -not [string]::Equals($usageProcess.Path, $usagePath, [StringComparison]::OrdinalIgnoreCase)) { continue }
            $usageOwner = Get-CimInstance Win32_Process -Filter "ProcessId = $($usageProcess.Id)" |
                Invoke-CimMethod -MethodName GetOwnerSid
            if ($null -eq $usageOwner -or $usageOwner.ReturnValue -ne 0) {
                throw 'Nao foi possivel confirmar o usuario do OpenUsage; nenhum novo encerramento sera feito.'
            }
            if ($usageOwner.Sid -eq $usageSid) { $usageTargets += $usageProcess }
        }
        foreach ($usageProcess in $usageTargets) {
            if ($usageProcess.HasExited) { continue }
            $usageProcess.Kill()
            $usageRestore = $true
            if (-not $usageProcess.WaitForExit(10000)) { throw 'O OpenUsage nao encerrou no prazo.' }
        }
        # Nao encerra ccusage: aguarda apenas os processos encontrados neste momento.
        $usageWorkers = @(Get-Process -Name 'ccusage' -ErrorAction SilentlyContinue)
        $usageDeadline = [DateTime]::UtcNow.AddSeconds(30)
        foreach ($usageWorker in $usageWorkers) {
            if ($usageWorker.HasExited) { continue }
            $null = $usageWorker.Handle
        }
        foreach ($usageWorker in $usageWorkers) {
            if ($usageWorker.HasExited) { continue }
            $remainingMs = [int][Math]::Max(1, ($usageDeadline - [DateTime]::UtcNow).TotalMilliseconds)
            if (-not $usageWorker.WaitForExit($remainingMs)) {
                throw 'ccusage ainda esta ativo apos 30 segundos. O jogo nao foi iniciado; nenhum ccusage foi encerrado.'
            }
        }
        & $LaunchGame
    }
    finally {
        foreach ($usageWorker in $usageWorkers) { $usageWorker.Dispose() }
        foreach ($usageProcess in $usageProcesses) { $usageProcess.Dispose() }
        if ($usageRestore) {
            try {
                $usageRunning = @(Get-Process -Name 'openusage' -ErrorAction SilentlyContinue |
                    Where-Object { $_.SessionId -eq $usageSession -and
                        [string]::Equals($_.Path, $usagePath, [StringComparison]::OrdinalIgnoreCase) })
                if ($usageRunning.Count -eq 0) {
                    Start-Process -FilePath $usagePath -WindowStyle Hidden
                }
            }
            catch { Write-Warning "Nao foi possivel reabrir o OpenUsage. Abra manualmente: $usagePath. $($_.Exception.Message)" }
        }
    }
}
