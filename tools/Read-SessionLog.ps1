param([string]$SessionPath, [switch]$SummaryOnly)
$ErrorActionPreference = 'Stop'
if (-not $SessionPath) {
    $latest = Get-ChildItem -LiteralPath (Join-Path $env:APPDATA 'GetecoV2/session-logs') -Directory |
        Sort-Object Name -Descending | Select-Object -First 1
    if (-not $latest) { throw 'Nenhuma sessao registrada.' }
    $SessionPath = $latest.FullName
}
if (Test-Path -LiteralPath $SessionPath -PathType Leaf) { $SessionPath = Split-Path -Parent $SessionPath }
$firstPart = Get-ChildItem -LiteralPath $SessionPath -Filter 'session-*.jsonl' | Sort-Object Name | Select-Object -First 1
if ($firstPart) {
    $firstLine = Get-Content -LiteralPath $firstPart.FullName -TotalCount 1 | ConvertFrom-Json
    if ($firstLine.data.schema -ge 5) {
        # O Python trata contextos exatos por quadro e dicionários com chaves vazias/ambíguas.
        $readerArguments = @((Join-Path $PSScriptRoot 'read_session_log.py'), $SessionPath)
        if ($SummaryOnly) { $readerArguments += '--summary-only' }
        & python @readerArguments
        if ($LASTEXITCODE -ne 0) { throw 'Falha no leitor da sessao.' }
        return
    }
}
$frames = 0L
$duration = 0.0
$maximum = 0.0
$cpuSum = 0.0
$windows = 0
$errors = 0
$ended = $false
$dropped = 0L
$systems = @{}
$operations = @{}
$pending = @{}
$errorSources = @{}
$profileDropped = 0L
$historyFrames = 0L
$lifecycleEvents = 0L
$lifecycleDropped = 0L
Write-Output "Sessao: $SessionPath"
foreach ($part in Get-ChildItem -LiteralPath $SessionPath -Filter 'session-*.jsonl' | Sort-Object Name) {
    $reader = [System.IO.File]::OpenText($part.FullName)
    try {
        while ($null -ne ($line = $reader.ReadLine())) {
            try { $row = $line | ConvertFrom-Json } catch { Write-Warning "Linha incompleta/invalida em $($part.Name)"; continue }
            $data = $row.data
            if ($null -eq $data) { $data = $row }
            # o schema 5 também envelopa eventos do watchdog do gravador; mantém sessões antigas legíveis.
            if ($data.type -eq 'records_dropped' -and $row.type -ne 'records_dropped') { $dropped += $data.count }
            if ($data.type -eq 'main_thread_unresponsive' -and $row.type -ne 'main_thread_unresponsive') {
                Write-Output "[$($row.utc)] Sem novo quadro por $($data.seconds_without_frame)s (inclui cargas/debugger)."
            }
            if ($row.type -eq 'records_dropped') { $dropped += $row.count }
            if ($row.type -eq 'main_thread_unresponsive') {
                Write-Output "[$($row.utc)] Sem novo quadro por $($row.seconds_without_frame)s (inclui cargas/debugger)."
            }
            switch ($data.type) {
                'session_start' { Write-Output "Inicio UTC: $($data.utc) | $($data.engine) | $($data.gpu)" }
                'metrics' {
                    $frames += $data.frames
                    $duration += $data.duration_ms
                    $maximum = [Math]::Max($maximum, $data.max_ms)
                    $cpuSum += $data.context.cpu_percent
                    $windows++
                }
                'error' {
                    $errors++
                    $key = "$($data.file)::$($data.function)"
                    if (-not $errorSources.ContainsKey($key)) { $errorSources[$key] = 0 }
                    $errorSources[$key]++
                    Write-Output "[$($row.utc)] tipo=$($data.error_type) $($data.file):$($data.line) $($data.function)"
                    Write-Output "$($data.code) $($data.rationale)"
                    foreach ($trace in $data.backtraces) { Write-Output $trace }
                    foreach ($active in $data.active_operations) { Write-Output "  Em andamento: $($active.system)/$($active.operation) ($($active.elapsed_ms)ms); correlacao, nao causa comprovada." }
                }
                'system_metrics' {
                    $profileDropped += [long]$data.dropped
                    foreach ($entry in $data.systems.PSObject.Properties) {
                        if (-not $systems.ContainsKey($entry.Name)) { $systems[$entry.Name] = @{ Calls=0L; Total=0.0; Max=0.0; Slow=0L } }
                        $sum = $systems[$entry.Name]
                        $sum.Calls += [long]$entry.Value.calls
                        $sum.Total += [double]$entry.Value.total_ms
                        $sum.Max = [Math]::Max($sum.Max, [double]$entry.Value.max_ms)
                        $sum.Slow += [long]$entry.Value.slow_calls
                    }
                }
                'operation_begin' { $pending[[string]$data.id] = "$($data.system)/$($data.operation)" }
                { $_ -in 'operation_end','operation_timing' } {
                    if ($data.type -eq 'operation_end') { $pending.Remove([string]$data.id) }
                    $key = "$($data.system)/$($data.operation)"
                    if (-not $operations.ContainsKey($key)) { $operations[$key] = @{ Calls=0L; Total=0.0; Max=0.0 } }
                    $sum = $operations[$key]
                    $sum.Calls++
                    $sum.Total += [double]$data.duration_ms
                    $sum.Max = [Math]::Max($sum.Max, [double]$data.duration_ms)
                }
                'operation_tracking_overflow' { Write-Warning 'Limite de operacoes ativas excedido; cobertura incompleta.' }
                'frame_spike' {
                    if ($SummaryOnly) { break }
                    Write-Output ('[{0}] Pico {1:N2}ms | quadro {2} | pausa={3} foco={4} | {5}' -f $row.utc,$data.frame_ms,$data.process_frame,$data.paused,$data.focused,$data.attribution)
                    if ($data.context) { Write-Output "  Contexto: $($data.context | ConvertTo-Json -Compress -Depth 8)" }
                    if ($data.monitor_scope) { Write-Output "  Monitores: $($data.monitor_scope); correlacionar timestamps, nao atribuir automaticamente ao pico." }
                    foreach ($system in $data.systems.PSObject.Properties | Sort-Object { $_.Value.total_ms } -Descending | Select-Object -First 8) {
                        Write-Output ('  {0}: {1:N3}ms inclusivos | {2} chamadas | maior {3:N3}ms' -f $system.Name,$system.Value.total_ms,$system.Value.calls,$system.Value.max_ms)
                    }
                    foreach ($span in $data.slow_spans | Sort-Object ms -Descending | Select-Object -First 4) {
                        Write-Output ('  Trecho {0}: {1:N3}ms | {2} | {3}' -f $span.label,$span.ms,$span.node,$span.script)
                    }
                    if ($data.dropped -gt 0) { Write-Output "  Perfil limitado: $($data.dropped) registros excederam os limites." }
                }
                'frame_history' {
                    $historyFrames += @($data.frames).Count
                    if (-not $SummaryOnly) {
                        Write-Output "  Historico $($data.phase): $(@($data.frames).Count) frames; fila=$($data.runtime.writer_queue), GC=$($data.runtime.gc_collections -join '/'), pausas GC cumulativas=$($data.runtime.gc_pause_ms)ms."
                    }
                }
                'lifecycle_events' {
                    $lifecycleEvents += @($data.events).Count
                    $lifecycleDropped += [long]$data.dropped
                    if (-not $SummaryOnly) {
                        foreach ($event in $data.events) {
                            Write-Output "  Descarte $($event.label) frame=$($event.process_frame) usec=$($event.start_usec)..$($event.end_usec): $($event.details | ConvertTo-Json -Compress -Depth 8)"
                        }
                    }
                }
                'session_end' { $ended = $true }
                'telemetry_error' { Write-Warning $data.error }
                'logger_capture_error' { Write-Warning $data.error }
            }
        }
    } finally { $reader.Dispose() }
}
if ($duration -gt 0) {
    Write-Output ('Janelas completas: {0} quadros / {1:N1}s | FPS medio {2:N2} | pior quadro {3:N2}ms | CPU media {4:N2}%' -f $frames,($duration/1000),($frames*1000/$duration),$maximum,($cpuSum/[Math]::Max(1,$windows)))
}
Write-Output "Erros/avisos: $errors | registros perdidos por saturacao: $dropped | encerramento registrado: $ended"
Write-Output "Historico: $historyFrames frames emitidos (janelas podem se sobrepor) | descarte: $lifecycleEvents eventos | omitidos: $lifecycleDropped"
Write-Output "Perfil: $profileDropped registros excederam limites (totais e detalhes possuem limites independentes)."
Write-Output 'Sistemas por tempo inclusivo total (nao somar pais e filhos; nao determina causa):'
foreach ($entry in $systems.GetEnumerator() | Sort-Object { $_.Value.Total } -Descending) {
    $v = $entry.Value
    Write-Output ('  {0}: {1:N2}ms | {2} chamadas | media {3:N3}ms | maior {4:N3}ms | >=2ms: {5}' -f $entry.Key,$v.Total,$v.Calls,($v.Total/[Math]::Max(1,$v.Calls)),$v.Max,$v.Slow)
}
Write-Output 'Carregamentos/operacoes por maior duracao (tempo de parede, inclui esperas e filhos):'
foreach ($entry in $operations.GetEnumerator() | Sort-Object { $_.Value.Max } -Descending) {
    Write-Output ('  {0}: maior {1:N2}ms | total {2:N2}ms | {3} chamadas' -f $entry.Key,$entry.Value.Max,$entry.Value.Total,$entry.Value.Calls)
}
foreach ($entry in $errorSources.GetEnumerator() | Sort-Object Value -Descending) { Write-Output "Origem de erros/avisos: $($entry.Key) | $($entry.Value) ocorrencias" }
foreach ($entry in $pending.GetEnumerator()) { Write-Output "Sem conclusao registrada: #$($entry.Key) $($entry.Value) (ativa, interrompida ou registro perdido)." }
Write-Output 'Media inclui menu, carga, pausa e falta de foco. Consulte metrics/context para separar cenarios.'
