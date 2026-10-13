param(
    [string[]]$Labels = @(),
    [switch]$SkipBuild
)

# Uma instância por vez evita contaminar a CPU/GPU das rodadas comparáveis.
$ErrorActionPreference = 'Stop'
$projectPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$evidencePath = Join-Path $projectPath 'evidence/profile-west-cpu-20261013'
$godotPath = 'D:/Downloads Chrome/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe'
New-Item -ItemType Directory -Path $evidencePath -Force | Out-Null
Set-Location -LiteralPath $projectPath

function Assert-NoOtherGame {
    $active = @(Get-CimInstance Win32_Process -Filter "name LIKE '%Godot%'" | Where-Object {
        $_.CommandLine -and $_.CommandLine -notmatch '(?i)(--editor|\s-e\s)'
    })
    if ($active.Count -gt 0) {
        $active | Select-Object ProcessId, CommandLine | ConvertTo-Json -Depth 3 | Write-Output
        throw 'Existe outro jogo/benchmark Godot ativo. A bateria foi suspensa sem terminar processos alheios.'
    }
}

$configurations = @(
    @{ Label='base_1'; Args=@() },
    @{ Label='population0_1'; Args=@('--population=0') },
    @{ Label='no_traffic_1'; Args=@('--no-traffic') },
    @{ Label='no_traffic_yield_1'; Args=@('--no-traffic-yield') },
    @{ Label='no_roadside_parking_1'; Args=@('--no-roadside-parking') },
    @{ Label='no_density_1'; Args=@('--no-density') },
    @{ Label='base_2'; Args=@() },
    @{ Label='no_density_2'; Args=@('--no-density') },
    @{ Label='no_roadside_parking_2'; Args=@('--no-roadside-parking') },
    @{ Label='no_traffic_yield_2'; Args=@('--no-traffic-yield') },
    @{ Label='no_traffic_2'; Args=@('--no-traffic') },
    @{ Label='population0_2'; Args=@('--population=0') },
    @{ Label='session_profile0_1'; Args=@(); SessionProfile='0' },
    @{ Label='session_profile0_2'; Args=@(); SessionProfile='0' },
    @{ Label='instrumentation0_1'; Args=@(); Trace='0'; Spans='0' },
    @{ Label='instrumentation0_2'; Args=@(); Trace='0'; Spans='0' }
)

Assert-NoOtherGame
if (-not $SkipBuild) {
    & dotnet build Harbor.csproj --no-restore
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao compilar Harbor.csproj.' }
}

$spanEnvironment = [Environment]::GetEnvironmentVariable('HARBOR_WEST_CPU_SPANS', 'Process')
$sessionEnvironment = [Environment]::GetEnvironmentVariable('HARBOR_SESSION_PROFILE', 'Process')
$traceEnvironment = [Environment]::GetEnvironmentVariable('HARBOR_WEST_CPU_TRACE', 'Process')
try {
    $env:HARBOR_WEST_CPU_SPANS = '1'
    foreach ($configuration in $configurations) {
        if ($Labels.Count -gt 0 -and $configuration.Label -notin $Labels) { continue }
        Assert-NoOtherGame
        $outputPath = Join-Path $evidencePath ($configuration.Label + '.json')
        if (Test-Path -LiteralPath $outputPath) { throw "Evidência já existe: $outputPath" }
        & python tests/measure/record_west_cpu_inputs.py $configuration.Label
        if ($LASTEXITCODE -ne 0) { throw 'Falha ao registrar entradas da rodada.' }
        $env:HARBOR_WEST_CPU_SPANS = if ($configuration.ContainsKey('Spans')) { $configuration.Spans } else { '1' }
        $env:HARBOR_WEST_CPU_TRACE = if ($configuration.ContainsKey('Trace')) { $configuration.Trace } else { '1' }
        if ($configuration.ContainsKey('SessionProfile')) {
            $env:HARBOR_SESSION_PROFILE = $configuration.SessionProfile
        } else {
            [Environment]::SetEnvironmentVariable('HARBOR_SESSION_PROFILE', $null, 'Process')
        }
        $arguments = @('--path', $projectPath, '--script', 'res://tests/measure/profile_west_cpu.gd',
            '--log-file', (Join-Path $evidencePath ($configuration.Label + '.engine.log')), '--',
            '--no-save', '--benchmark', '--no-dispatch', '--play-at=harbor,64,82',
            ('--label=' + $configuration.Label)) + $configuration.Args
        $started = [DateTimeOffset]::UtcNow
        Write-Output ("INÍCIO {0} {1:o}" -f $configuration.Label, $started)
        & $godotPath @arguments *> (Join-Path $evidencePath ($configuration.Label + '.console.log'))
        $runExitCode = $LASTEXITCODE
        $finished = [DateTimeOffset]::UtcNow
        $record = [ordered]@{
            label=$configuration.Label; started_utc=$started.ToString('o'); finished_utc=$finished.ToString('o')
            elapsed_seconds=($finished-$started).TotalSeconds; exit_code=$runExitCode
            arguments=$arguments; HARBOR_WEST_CPU_SPANS=$env:HARBOR_WEST_CPU_SPANS
            HARBOR_SESSION_PROFILE=$env:HARBOR_SESSION_PROFILE
            HARBOR_WEST_CPU_TRACE=$env:HARBOR_WEST_CPU_TRACE
        }
        $record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $evidencePath ($configuration.Label + '.run.json')) -Encoding utf8
        if ($runExitCode -ne 0 -or -not (Test-Path -LiteralPath $outputPath)) {
            Get-Content -LiteralPath (Join-Path $evidencePath ($configuration.Label + '.console.log')) -Tail 50
            throw "Rodada $($configuration.Label) falhou (código $runExitCode)."
        }
        $report = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json
        Write-Output ("FIM {0}: {1:N1}s, evidência {2}" -f $configuration.Label, ($finished-$started).TotalSeconds, $outputPath)
    }
} finally {
    [Environment]::SetEnvironmentVariable('HARBOR_WEST_CPU_SPANS', $spanEnvironment, 'Process')
    [Environment]::SetEnvironmentVariable('HARBOR_SESSION_PROFILE', $sessionEnvironment, 'Process')
    [Environment]::SetEnvironmentVariable('HARBOR_WEST_CPU_TRACE', $traceEnvironment, 'Process')
}
