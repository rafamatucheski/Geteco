# Contrato de despacho compartilhado pelos dois runners. Nao executa processos.
function Get-DispatchManifest {
    return @{
        rules = @{ script = 'test_dispatch_rules'; tag = 'DISPATCH_RULES'; minimum = 35; groups = @('rules','router_grid','router_one_way','router_blocked_and_unreachable','router_spawn_and_departure') }
        police = @{ script = 'test_dispatch_police'; tag = 'DISPATCH_POLICE'; minimum = 46; groups = @('pursuit_and_release','garage_rule_holds','foot_agent_contract','entity_limits','blocked_road','crew_depleted','disable_restores_legacy') }
        emergency = @{ script = 'test_dispatch_emergency'; tag = 'DISPATCH_EMERGENCY'; minimum = 58; groups = @('service_medic','service_fire','service_mortician','crew_limit_and_cooldown','mortician_policy','mortician_wreck') }
        lifecycle = @{ script = 'test_dispatch_lifecycle'; tag = 'DISPATCH_LIFECYCLE'; minimum = 40; groups = @('incident_removed_while_enroute','incident_removed_while_working','cancel_api','suspension_and_resume','suspension_recycles','detour_around_wall','no_road_access','crew_killed','vehicle_wrecked','patient_dies_during_care','suspension_of_people','dismiss_and_wrecks','controller_leaves_tree','no_crime_from_dispatch_vehicle') }
        integration = @{ script = 'test_dispatch_integrated_pursuit'; tag = 'DISPATCH_INTEGRATION'; minimum = 14; groups = @() }
    }
}

function Get-GodotResultProblems([string]$Script, [int]$Code, [string]$Text) {
    $problems = @()
    if ($Code -ne 0) { $problems += "codigo de saida $Code" }
    foreach ($line in ($Text -split "`n")) {
        if ($line -match 'SCRIPT ERROR|Parse Error|Compile Error|Cannot infer|Invalid (call|access|assignment)|Identifier .* not declared|Failed to load script') {
            $problems += "erro de script: $($line.Trim())"
        }
    }
    $name = [IO.Path]::GetFileNameWithoutExtension($Script)
    $contract = @( (Get-DispatchManifest).Values | Where-Object { $_.script -eq $name })
    if ($contract.Count -eq 0) { return $problems }
    $m = $contract[0]
    foreach ($group in $m.groups) {
        if ($Text -notmatch ('(?m)^GROUP_OK ' + [regex]::Escape($group) + '\r?$')) { $problems += "grupo nao concluido: $group" }
    }
    $pattern = if ($m.groups.Count -eq 0) {
        '(?m)^' + $m.tag + ' checks=(\d+) failures=(\d+)\r?$'
    } else {
        '(?m)^' + $m.tag + ' groups=(\d+)/(\d+) checks=(\d+) failures=(\d+)\r?$'
    }
    $summaries = [regex]::Matches($Text, $pattern)
    # Duas conclusoes no mesmo log nao comprovam uma unica execucao completa.
    if ($summaries.Count -ne 1) { $problems += "linha final ausente ou duplicada ($($summaries.Count))"; return $problems }
    $summary = $summaries[0]
    $checksIndex = 1
    if ($m.groups.Count -gt 0) {
        if ([int]$summary.Groups[1].Value -ne $m.groups.Count -or [int]$summary.Groups[2].Value -ne $m.groups.Count) { $problems += "contagem de grupos diferente de $($m.groups.Count)" }
        $checksIndex = 3
    }
    if ([int]$summary.Groups[$checksIndex].Value -lt $m.minimum) { $problems += "verificacoes abaixo do minimo $($m.minimum)" }
    if ([int]$summary.Groups[$checksIndex + 1].Value -ne 0) { $problems += 'falhas declaradas no resumo' }
    return $problems
}

function Get-ImpactProfiles {
    # Selecao explicita: nao infere cobertura completa a partir de um diff.
    return @{
        dispatch = @('test_dispatch_rules','test_dispatch_police','test_dispatch_emergency','test_dispatch_lifecycle','test_dispatch_integrated_pursuit','test_dispatch_vehicle_theft','test_fire_traffic','test_responder_fire_lifecycle')
        streaming = @('test_regions','test_bridge_approach_terrain','test_admission','test_admission_integration','test_region_vehicle_suspension','test_pursuit_region_seam','test_persistent_vehicle_support')
        'world-contracts' = @('test_city_context_index','test_city_streaming_budget','test_startup_prewarm_contract','test_region_cache_ownership','test_region_cache_piece_variants')
        vehicles = @('test_native_driving','test_vehicle_doors','test_vehicle_floor_contact','test_vehicle_body_transitions','test_seated_driver','test_garage_vehicle_transfer')
        garage = @('test_garage_rewards','test_garage_driver_restore','test_garage_vehicle_transfer','test_maciota_transition_safety')
    }
}

function Get-SelectedTests([string]$Root, [string]$Filter, [string]$Only, [string]$Impact) {
    $catalogue = @(Get-ChildItem -LiteralPath (Join-Path $Root 'tests') -Recurse -Filter 'test_*.gd' | Where-Object { $_.FullName -notmatch '[\\/]tests[\\/](measure|capture)[\\/]' } | Sort-Object FullName)
    $requested = @($Only.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $profileNames = @()
    if ($Impact) {
        $profiles = Get-ImpactProfiles
        if (-not $profiles.ContainsKey($Impact)) { throw "Perfil de impacto desconhecido: $Impact" }
        $profileNames = @($profiles[$Impact])
    }
    foreach ($name in @($requested + $profileNames | Select-Object -Unique)) {
        $matches = @($catalogue | Where-Object BaseName -eq $name)
        if ($matches.Count -ne 1) { throw "Teste solicitado inexistente ou ambiguo: $name ($($matches.Count))" }
    }
    $selected = @($catalogue | Where-Object { $_.Name -like "*$Filter*" -and ($requested.Count -eq 0 -or $requested -contains $_.BaseName) -and ($profileNames.Count -eq 0 -or $profileNames -contains $_.BaseName) })
    if ($selected.Count -eq 0) { throw 'Nenhum teste selecionado. Confira -Filter, -Only e -Impact.' }
    return $selected
}

function Get-TextSHA256([string]$Text) {
    $hash = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','').ToLowerInvariant() }
    finally { $hash.Dispose() }
}

function Get-RunSourceState([string]$Root, [string[]]$Sources) {
    $state = [ordered]@{ Revision = $null; Status = @(); SourceStatus = @(); DiffSHA256 = $null; SourceDiffSHA256 = $null; Sources = @(); GitAvailable = $false; Comparison = 'tracked-source-diff+selected-tests-and-runners'; CoverageComplete = $false }
    if ((Test-Path -LiteralPath (Join-Path $Root '.git')) -and (Get-Command git -ErrorAction SilentlyContinue)) {
        # PS5 transforma stderr nativo em erro, mesmo quando Git sai com zero.
        # Avisos LF/CRLF nao invalidam a consulta; falhas reais usam ExitCode.
        $gitPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            # AGENTS exige status antes de qualquer outra consulta Git.
            $status = @(& git -C $Root status --porcelain=v1 2>$null)
            if ($LASTEXITCODE -eq 0) {
                $state.GitAvailable = $true
                $state.Status = $status
                $state.SourceStatus = @($status | Where-Object { $_.Substring(3) -notmatch '^(evidence/|tests/dispatch/results/|\.godot/|builds/)' })
                $uncovered = @($state.SourceStatus | Where-Object { $_ -like '?? *' -and $Sources -notcontains $_.Substring(3) })
                $state.CoverageComplete = $uncovered.Count -eq 0
                $revision = (& git -C $Root rev-parse HEAD 2>$null)
                if ($LASTEXITCODE -eq 0) { $state.Revision = $revision } else { $state.CoverageComplete = $false }
                $diff = @(& git -C $Root diff --no-ext-diff --binary HEAD -- 2>$null)
                if ($LASTEXITCODE -eq 0) { $state.DiffSHA256 = Get-TextSHA256 ($diff -join "`n") } else { $state.CoverageComplete = $false }
                $sourceDiff = @(& git -C $Root diff --no-ext-diff --binary HEAD -- . ':(exclude)evidence' ':(exclude)tests/dispatch/results' ':(exclude).godot' ':(exclude)builds' 2>$null)
                if ($LASTEXITCODE -eq 0) { $state.SourceDiffSHA256 = Get-TextSHA256 ($sourceDiff -join "`n") } else { $state.CoverageComplete = $false }
            }
        } finally { $ErrorActionPreference = $gitPreference }
    }
    foreach ($relative in @($Sources | Select-Object -Unique)) {
        $path = Join-Path $Root $relative
        if (Test-Path -LiteralPath $path -PathType Leaf) { $state.Sources += [pscustomobject]@{ Path = $relative; SHA256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash } }
    }
    return [pscustomobject]$state
}

function New-RunnerMetadata([string]$Root, [string]$Engine, [hashtable]$Selection, [string[]]$Sources) {
    $engineInfo = @{ Path = $Engine; Exists = $false; SHA256 = $null }
    if (Test-Path -LiteralPath $Engine -PathType Leaf) { $engineInfo = @{ Path = (Get-Item -LiteralPath $Engine).FullName; Exists = $true; SHA256 = (Get-FileHash -LiteralPath $Engine -Algorithm SHA256).Hash } }
    return [ordered]@{
        SchemaVersion = 1
        RunId = ((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd_HHmmss_fff') + '-' + [guid]::NewGuid().ToString('N'))
        StartedUtc = (Get-Date).ToUniversalTime().ToString('o')
        EndedUtc = $null
        Selection = $Selection
        Environment = @{ PowerShell = $PSVersionTable.PSVersion.ToString(); OS = [Environment]::OSVersion.VersionString; Machine = [Environment]::MachineName; Project = $Root; WorkingDirectory = (Get-Location).Path; Engine = $engineInfo }
        SourceBefore = Get-RunSourceState $Root $Sources
        SourceAfter = $null
        SourceChanged = $null
        Executions = @()
    }
}

function Save-RunnerReport([string]$ReportDir, [object[]]$Results, [System.Collections.IDictionary]$Metadata, [string]$Root, [string[]]$Sources) {
    $Metadata.EndedUtc = (Get-Date).ToUniversalTime().ToString('o')
    $Metadata.SourceAfter = Get-RunSourceState $Root $Sources
    $before = [ordered]@{ Revision = $Metadata.SourceBefore.Revision; Status = $Metadata.SourceBefore.SourceStatus; Diff = $Metadata.SourceBefore.SourceDiffSHA256; Sources = $Metadata.SourceBefore.Sources }
    $after = [ordered]@{ Revision = $Metadata.SourceAfter.Revision; Status = $Metadata.SourceAfter.SourceStatus; Diff = $Metadata.SourceAfter.SourceDiffSHA256; Sources = $Metadata.SourceAfter.Sources }
    $changed = (Get-TextSHA256 ($before | ConvertTo-Json -Depth 8 -Compress)) -ne (Get-TextSHA256 ($after | ConvertTo-Json -Depth 8 -Compress))
    $Metadata.SourceChanged = if ($changed) { $true } elseif ($Metadata.SourceBefore.CoverageComplete -and $Metadata.SourceAfter.CoverageComplete) { $false } else { $null }
    New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
    $path = Join-Path $ReportDir "suite-$($Metadata.RunId).json"
    ConvertTo-Json -InputObject @($Results) -Depth 5 | Set-Content -LiteralPath $path -Encoding UTF8
    $Metadata | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $ReportDir "metadata-$($Metadata.RunId).json") -Encoding UTF8
    Write-Host "Relatorio: $path"
}

function Resolve-GodotEngine([string]$Requested) {
    if ($Requested) { return $Requested }
    $installed = 'D:\Downloads Chrome\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
    if (Test-Path -LiteralPath $installed) { return $installed }
    throw 'Defina GODOT_EXE ou -GodotPath com o caminho do Godot (_console.exe).'
}

function Assert-GodotExclusive([switch]$AllowConcurrent) {
    $running = @(Get-CimInstance Win32_Process -Filter "Name LIKE 'Godot%'" | Where-Object { $_.CommandLine -notmatch '(^|\s)--editor(\s|$)' })
    if ($running.Count -gt 0 -and -not $AllowConcurrent) { throw 'Feche as outras instancias do jogo antes de rodar.' }
    return $running
}

function Stop-OwnedGodot($Process) {
    # Recebe apenas o processo criado pelo proprio runner; falha interrompe o lote.
    try {
        & taskkill /T /F /PID $Process.Id | Out-Null
        if ($LASTEXITCODE -ne 0) { return $false }
        return $Process.WaitForExit(3000)
    } catch { return $false }
}
