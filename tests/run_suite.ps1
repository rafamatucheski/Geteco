# Cada teste roda uma vez, com save temporario isolado; medicoes ficam fora.
param(
    [string]$Filter = '',
    [string]$Only = '',
    [ValidateRange(1,2147483)][int]$TimeoutSec = 600,
    [string]$GodotPath = $env:GODOT_EXE,
    [string]$Impact = '',
    [switch]$AllowConcurrent
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Runner.Common.ps1')
$root = Split-Path -Parent $PSScriptRoot
$reportDir = Join-Path $root 'evidence\test-suite'
$tests = @(Get-SelectedTests $root $Filter $Only $Impact)
$GodotPath = Resolve-GodotEngine $GodotPath
$running = @(Assert-GodotExclusive -AllowConcurrent:$AllowConcurrent)
$selected = @($tests | ForEach-Object { $_.FullName.Substring($root.Length + 1).Replace('\','/') })
$sources = @('tests/run_suite.ps1','tests/Runner.Common.ps1') + $selected
$metadata = New-RunnerMetadata $root $GodotPath @{ Runner = 'suite'; Filter = $Filter; Only = $Only; Impact = $Impact; TimeoutSec = $TimeoutSec; AllowConcurrent = [bool]$AllowConcurrent; ConcurrentProcessIds = @($running | ForEach-Object ProcessId); Selected = $selected } $sources
$results = @()
$abortRemaining = $false
foreach ($test in $tests) {
    $relative = $test.FullName.Substring($root.Length + 1).Replace('\','/')
    $started = Get-Date
    $log = [IO.Path]::GetTempFileName()
    $saveRoot = Join-Path ([IO.Path]::GetTempPath()) ('geteco-suite-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $saveRoot | Out-Null
    $godotArgs = @('--path', ('"' + $root + '"'), '--script', "res://$relative", '--', '--no-save', '--skip-arrival', ('"--isolated-save-root=' + $saveRoot + '"'))
    if ($test.BaseName -eq 'test_android_controls') { $godotArgs += '--touch-controls' }
    $rendered = $test.BaseName -in @('test_harbor_gameplay_acceptance','test_urban_asset_library','test_vertice_depth','test_vertice_site_depth','test_vertice_undercroft_geometry','test_vertice_packing_depth','test_police_frontage_geometry')
    $effectiveArgs = if ($rendered) { @($godotArgs + '--population=8') } else { @('--headless') + $godotArgs }
    $process = $null
    $problems = @()
    $status = 'PASSOU'
    $code = $null
    try {
        if ($rendered) {
            $process = Start-Process -FilePath $GodotPath -ArgumentList $effectiveArgs -WindowStyle Hidden -PassThru -RedirectStandardOutput $log -RedirectStandardError "$log.err"
        } else {
            $process = Start-Process -FilePath $GodotPath -ArgumentList $effectiveArgs -NoNewWindow -PassThru -RedirectStandardOutput $log -RedirectStandardError "$log.err"
        }
        # O Handle garante que ExitCode seja preenchido no Windows PowerShell.
        $null = $process.Handle
        if (-not $process.WaitForExit($TimeoutSec * 1000)) {
            if (-not (Stop-OwnedGodot $process)) { $abortRemaining = $true; $problems += 'encerramento do processo nao confirmado; lote interrompido' }
            $status = 'TEMPO'
            $problems += "timeout de $TimeoutSec segundos"
        } else { $null = $process.WaitForExit(); $code = $process.ExitCode }
    } catch {
        $status = 'FALHOU'; $problems += $_.Exception.Message
        if ($null -ne $process -and -not (Stop-OwnedGodot $process)) { $abortRemaining = $true; $problems += 'encerramento do processo nao confirmado; lote interrompido' }
    }
    $text = (Get-Content -LiteralPath $log -Raw -ErrorAction SilentlyContinue) + "`n" + (Get-Content -LiteralPath "$log.err" -Raw -ErrorAction SilentlyContinue)
    if ($status -eq 'PASSOU') {
        if ($null -eq $code) { $problems += 'codigo de saida indisponivel' }
        else { $problems += @(Get-GodotResultProblems $relative $code $text) }
        if ($problems.Count -gt 0) { $status = 'FALHOU' }
    }
    $seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
    $tail = (($text -split "`n") | Where-Object { $_ -match 'PASS|FAIL|ERROR|DISPATCH_|GROUP_OK' } | Select-Object -Last 3) -join ' | '
    $stdoutPath = ''
    $stderrPath = ''
    if ($status -ne 'PASSOU') {
        $logDir = Join-Path $reportDir 'logs'
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null
        $logName = "$($metadata.RunId)-$($test.BaseName)"
        $stdoutPath = Join-Path $logDir "$logName.stdout.log"
        $stderrPath = Join-Path $logDir "$logName.stderr.log"
        foreach ($pair in @(@($log,$stdoutPath),@("$log.err",$stderrPath))) {
            if (Test-Path -LiteralPath $pair[0]) { Move-Item -LiteralPath $pair[0] -Destination $pair[1] }
            else { Set-Content -LiteralPath $pair[1] -Value '' }
        }
    } else { Remove-Item -LiteralPath $log,"$log.err" -ErrorAction SilentlyContinue }
    $tempPath = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    $saveRootPath = [IO.Path]::GetFullPath($saveRoot)
    if (-not $saveRootPath.StartsWith($tempPath,[StringComparison]::OrdinalIgnoreCase) -or -not [IO.Path]::GetFileName($saveRootPath).StartsWith('geteco-suite-')) { throw "Recusando remover diretorio fora do temp da suite: $saveRootPath" }
    if (-not $abortRemaining) { Remove-Item -LiteralPath $saveRootPath -Recurse -Force -ErrorAction SilentlyContinue }
    $results += [pscustomobject]@{ Teste = $relative; Resultado = $status; Segundos = $seconds; Saida = $tail; Stdout = $stdoutPath; Stderr = $stderrPath }
    $metadata.Executions += [pscustomobject]@{ Script = $relative; Arguments = $effectiveArgs; Code = $code; Problems = $problems; Result = $status; Stdout = $stdoutPath; Stderr = $stderrPath }
    Write-Host ("{0,-7} {1,6}s  {2}" -f $status,$seconds,$relative)
    $problems | ForEach-Object { Write-Host "  - $_" }
    if ($abortRemaining) { break }
}
$passed = @($results | Where-Object Resultado -eq 'PASSOU').Count
Write-Host "Suite: $passed de $($results.Count) passaram."
$metadata['Aborted'] = $abortRemaining
Save-RunnerReport $reportDir $results $metadata $root $sources
if ($metadata.SourceChanged) { Write-Warning 'Fontes mudaram durante a execucao; revise a evidencia.' }
if ($passed -ne $results.Count -or $metadata.SourceChanged) { exit 1 }
exit 0
