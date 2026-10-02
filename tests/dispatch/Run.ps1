param(
    [ValidateSet('all','rules','police','emergency','lifecycle','integration','import','measure')][string]$Suite = 'all',
    [switch]$AllowConcurrent,
    [int]$Stars = 4,
    [string]$GodotPath = $env:GODOT_EXE,
    [ValidateRange(1,2147483)][int]$TimeoutSec = 900
)
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Runner.Common.ps1')
$project = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$engine = Resolve-GodotEngine $GodotPath
$running = @(Assert-GodotExclusive -AllowConcurrent:$AllowConcurrent)
$manifest = Get-DispatchManifest
$names = if ($Suite -eq 'all') { @('rules','police','emergency','lifecycle') } elseif ($Suite -in @('import','measure')) { @() } else { @($Suite) }
$selected = @($names | ForEach-Object { "tests/dispatch/$($manifest[$_].script).gd" })
if ($Suite -eq 'measure') { $selected = @('tests/dispatch/measure_dispatch.gd') }
foreach ($relative in $selected) { if (-not (Test-Path -LiteralPath (Join-Path $project $relative))) { throw "Teste solicitado inexistente: $relative" } }
$sources = @('tests/dispatch/Run.ps1','tests/Runner.Common.ps1') + $selected
$metadata = New-RunnerMetadata $project $engine @{ Runner = 'dispatch'; Suite = $Suite; Stars = $Stars; TimeoutSec = $TimeoutSec; AllowConcurrent = [bool]$AllowConcurrent; ConcurrentProcessIds = @($running | ForEach-Object ProcessId); Selected = $selected } $sources
$reportDir = Join-Path $project 'evidence\test-suite'
$results = Join-Path $PSScriptRoot ("results\" + $metadata.RunId)
New-Item -ItemType Directory -Force -Path $results | Out-Null
$records = @()
$failed = 0
$abortRemaining = $false

function Invoke-Godot([string]$label,[string]$testScript,[string[]]$arguments,[switch]$Measure) {
    $out = Join-Path $results "$label.out.log"
    $err = Join-Path $results "$label.err.log"
    $started = Get-Date
    $code = $null
    $problems = @()
    $status = 'PASSOU'
    $p = $null
    try {
        $p = Start-Process -FilePath $engine -ArgumentList $arguments -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
        $null = $p.Handle
        if (-not $p.WaitForExit($TimeoutSec * 1000)) {
            # _console.exe pode deixar o executavel filho ativo se so o pai morrer.
            if (-not (Stop-OwnedGodot $p)) { $script:abortRemaining = $true; $problems += 'encerramento do processo nao confirmado; lote interrompido' }
            $status = 'TEMPO'
            $problems += "timeout de $TimeoutSec segundos"
        } else { $null = $p.WaitForExit(); $code = $p.ExitCode }
    } catch {
        $status = 'FALHOU'; $problems += $_.Exception.Message
        if ($null -ne $p -and -not (Stop-OwnedGodot $p)) { $script:abortRemaining = $true; $problems += 'encerramento do processo nao confirmado; lote interrompido' }
    }
    foreach ($logPath in @($out,$err)) { if (-not (Test-Path -LiteralPath $logPath)) { Set-Content -LiteralPath $logPath -Value '' } }
    $text = (Get-Content -LiteralPath $out -Raw -ErrorAction SilentlyContinue) + "`n" + (Get-Content -LiteralPath $err -Raw -ErrorAction SilentlyContinue)
    if ($status -eq 'PASSOU') {
        if ($null -eq $code) { $problems += 'codigo de saida indisponivel' }
        else { $problems += @(Get-GodotResultProblems $testScript $code $text) }
        if ($Measure -and $text -notmatch 'DISPATCH_MEASURE') { $problems += 'resumo de medicao ausente' }
        if ($problems.Count -gt 0) { $status = 'FALHOU' }
    }
    $seconds = [math]::Round(((Get-Date) - $started).TotalSeconds,1)
    $script:records += [pscustomobject]@{ Teste = $testScript; Resultado = $status; Segundos = $seconds; Saida = (($text -split "`n" | Where-Object { $_ -match 'DISPATCH_|ERROR|FAIL' } | Select-Object -Last 3) -join ' | '); Stdout = $out; Stderr = $err }
    $metadata.Executions += [pscustomobject]@{ Script = $testScript; Label = $label; Arguments = $arguments; Code = $code; Problems = $problems; Result = $status; Stdout = $out; Stderr = $err }
    Write-Host "$status : $label"
    $problems | ForEach-Object { Write-Host "  - $_" }
    if ($status -ne 'PASSOU') { $script:failed++ }
}

if ($Suite -eq 'import') {
    Invoke-Godot 'import' '' @('--path',('"' + $project + '"'),'--import')
} elseif ($Suite -eq 'measure') {
    # Renderizado, carga fixa e sem save pessoal; baseline e dispatch sequenciais.
    foreach ($mode in @('baseline','dispatch')) {
        $label = "$mode-s$Stars"
        $runArgs = @('--path',('"' + $project + '"'),'--script','res://tests/dispatch/measure_dispatch.gd','--',"--label=$label","--stars=$Stars",'--no-save','--skip-arrival','--population=24','--seed=20260921')
        if ($mode -eq 'baseline') { $runArgs += '--baseline' }
        Invoke-Godot "measure-$label" 'tests/dispatch/measure_dispatch.gd' $runArgs -Measure
        if ($abortRemaining) { break }
    }
} else {
    foreach ($name in $names) {
        $relative = "tests/dispatch/$($manifest[$name].script).gd"
        $runArgs = @('--path',('"' + $project + '"'),'--script',"res://$relative")
        if ($name -eq 'integration') { $runArgs += @('--','--no-save','--skip-arrival','--population=24','--seed=20260921') }
        Invoke-Godot $manifest[$name].script $relative $runArgs
        if ($abortRemaining) { break }
    }
}
$metadata['Aborted'] = $abortRemaining
Save-RunnerReport $reportDir $records $metadata $project $sources
if ($metadata.SourceChanged) { Write-Warning 'Fontes mudaram durante a execucao; revise a evidencia.'; $failed++ }
exit $failed
