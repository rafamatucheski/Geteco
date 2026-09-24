param([ValidateSet('all','rules','police','emergency','lifecycle','integration','import','measure')][string]$Suite = 'all', [switch]$AllowConcurrent, [int]$Stars = 4)
# Executa os testes de despacho. Quem coordena as execuções do Godot é o integrador:
# o script se recusa a rodar com outra instância do jogo aberta (o editor pode continuar).
#
# Código de saída zero não basta: um erro de script aborta uma função no meio e o
# teste seguiria adiante. Por isso a saída é lida e o teste só passa se
#   1) não houver SCRIPT ERROR / Parse Error / Compile Error / Invalid / Cannot infer;
#   2) todos os grupos do manifesto abaixo tiverem impresso GROUP_OK;
#   3) a linha final "DISPATCH_X groups=n/n checks=N failures=0" existir, com n = total
#      esperado e N >= o mínimo do manifesto.
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$engine = 'D:\Downloads Chrome\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$running = @(Get-CimInstance Win32_Process -Filter "Name LIKE 'Godot%'" | Where-Object { $_.CommandLine -notmatch '(^|\s)--editor(\s|$)' })
if ($running.Count -gt 0 -and -not $AllowConcurrent) { throw 'Feche as outras instâncias do jogo antes de rodar.' }
if ($Suite -eq 'import') { & $engine --path $project --import; exit $LASTEXITCODE }

$results = Join-Path $PSScriptRoot 'results'
New-Item -ItemType Directory -Force -Path $results | Out-Null

function Invoke-Godot([string]$label, [string[]]$arguments) {
    $out = Join-Path $results "$label.out.log"
    $err = Join-Path $results "$label.err.log"
    $p = Start-Process -FilePath $engine -ArgumentList $arguments -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
    if (-not $p.WaitForExit(900000)) { Stop-Process -Id $p.Id -Force; throw "$label excedeu 15 minutos." }
    $p.WaitForExit()
    return @{ Code = $p.ExitCode; Text = ((Get-Content -LiteralPath $out -Raw -ErrorAction SilentlyContinue) + "`n" + (Get-Content -LiteralPath $err -Raw -ErrorAction SilentlyContinue)) }
}

if ($Suite -eq 'measure') {
    # Cenário fixo: sem save pessoal, sem cinemática de chegada, população e semente fixas.
    # Renderizado (nunca --headless). Compara sempre a mesma procura com e sem o controlador.
    foreach ($mode in @('baseline','dispatch')) {
        $label = "$mode-s$Stars"
        $runArgs = @('--path', ('"' + $project + '"'), '--script', 'res://tests/dispatch/measure_dispatch.gd', '--', "--label=$label", "--stars=$Stars", '--no-save', '--skip-arrival', '--population=24', '--seed=20260921')
        if ($mode -eq 'baseline') { $runArgs += '--baseline' }
        $r = Invoke-Godot "measure-$label" $runArgs
        if ($r.Code -ne 0 -or $r.Text -notmatch 'DISPATCH_MEASURE') { Write-Host $r.Text; throw "Medição $label falhou." }
        Write-Host ($r.Text -split "`n" | Where-Object { $_ -match 'DISPATCH_MEASURE' })
    }
    exit 0
}

if ($Suite -eq 'integration') {
    $r = Invoke-Godot 'test_dispatch_integrated_pursuit' @('--path', ('"' + $project + '"'), '--script', 'res://tests/dispatch/test_dispatch_integrated_pursuit.gd', '--', '--no-save', '--skip-arrival', '--population=24', '--seed=20260921')
    $problems = @()
    if ($r.Code -ne 0) { $problems += "código de saída $($r.Code)" }
    foreach ($line in ($r.Text -split "`n")) {
        if ($line -match 'SCRIPT ERROR|Parse Error|Compile Error|Cannot infer|Invalid (call|access|assignment)|Identifier .* not declared|Failed to load script') { $problems += "erro de script: $($line.Trim())" }
    }
    $summary = [regex]::Match($r.Text, 'DISPATCH_INTEGRATION checks=(\d+) failures=(\d+)')
    if (-not $summary.Success) { $problems += 'linha final ausente (o teste não terminou)' }
    elseif ([int]$summary.Groups[1].Value -lt 14 -or [int]$summary.Groups[2].Value -ne 0) { $problems += $summary.Value }
    if ($problems.Count -gt 0) {
        Write-Host 'REPROVADO: test_dispatch_integrated_pursuit'
        $problems | Select-Object -Unique | ForEach-Object { Write-Host "  - $_" }
        exit 1
    }
    Write-Host "APROVADO: $($summary.Value)"
    exit 0
}

$manifest = @{
    rules     = @{ script = 'test_dispatch_rules';     tag = 'DISPATCH_RULES';     minimum = 35; groups = @('rules','router_grid','router_one_way','router_blocked_and_unreachable','router_spawn_and_departure') }
    police    = @{ script = 'test_dispatch_police';    tag = 'DISPATCH_POLICE';    minimum = 46; groups = @('pursuit_and_release','garage_rule_holds','foot_agent_contract','entity_limits','blocked_road','crew_depleted','disable_restores_legacy') }
    emergency = @{ script = 'test_dispatch_emergency'; tag = 'DISPATCH_EMERGENCY'; minimum = 40; groups = @('service_medic','service_fire','service_mortician','crew_limit_and_cooldown') }
    lifecycle = @{ script = 'test_dispatch_lifecycle'; tag = 'DISPATCH_LIFECYCLE'; minimum = 40; groups = @('incident_removed_while_enroute','incident_removed_while_working','cancel_api','suspension_and_resume','suspension_recycles','detour_around_wall','no_road_access','crew_killed','vehicle_wrecked','patient_dies_during_care','suspension_of_people','dismiss_and_wrecks','controller_leaves_tree','no_crime_from_dispatch_vehicle') }
}
$names = if ($Suite -eq 'all') { @('rules','police','emergency','lifecycle') } else { @($Suite) }
$failed = 0
foreach ($name in $names) {
    $m = $manifest[$name]
    Write-Host "== $($m.script)"
    $r = Invoke-Godot $m.script @('--path', ('"' + $project + '"'), '--script', "res://tests/dispatch/$($m.script).gd")
    $problems = @()
    if ($r.Code -ne 0) { $problems += "código de saída $($r.Code)" }
    foreach ($line in ($r.Text -split "`n")) {
        if ($line -match 'SCRIPT ERROR|Parse Error|Compile Error|Cannot infer|Invalid (call|access|assignment)|Identifier .* not declared|Failed to load script') { $problems += "erro de script: $($line.Trim())" }
    }
    foreach ($group in $m.groups) {
        if ($r.Text -notmatch "GROUP_OK $group\b") { $problems += "grupo não concluído: $group" }
    }
    $summary = [regex]::Match($r.Text, "$($m.tag) groups=(\d+)/(\d+) checks=(\d+) failures=(\d+)")
    if (-not $summary.Success) { $problems += 'linha final ausente (o teste não terminou)' }
    else {
        if ([int]$summary.Groups[1].Value -ne $m.groups.Count -or [int]$summary.Groups[2].Value -ne $m.groups.Count) { $problems += "grupos $($summary.Groups[1].Value)/$($summary.Groups[2].Value), esperado $($m.groups.Count)" }
        if ([int]$summary.Groups[3].Value -lt $m.minimum) { $problems += "apenas $($summary.Groups[3].Value) verificações, mínimo $($m.minimum)" }
        if ([int]$summary.Groups[4].Value -ne 0) { $problems += "$($summary.Groups[4].Value) falhas" }
    }
    if ($problems.Count -gt 0) {
        $failed++
        Write-Host "REPROVADO: $($m.script)"
        $problems | Select-Object -Unique | ForEach-Object { Write-Host "  - $_" }
        Write-Host "  (saída completa em tests/dispatch/results/$($m.script).out.log e .err.log)"
    } else { Write-Host "APROVADO: $($summary.Value)" }
}
exit $failed
