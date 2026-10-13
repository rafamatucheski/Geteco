param([string[]]$Scripts = @(
    'tests/test_regions.gd',
    'tests/test_native_driving.gd',
    'tests/cold/test_admission.gd',
    'tests/test_bridge_approach_terrain.gd',
    'tests/urban_detail/test_urban_building_factory.gd',
    'tests/urban_detail/test_harbor_building_source_fidelity.gd',
    'tests/urban_detail/test_harbor_building_batch.gd',
    'tests/urban_detail/test_harbor_access_exteriors.gd',
    'tests/test_harbor_building_access.gd',
    'tests/test_tunnel_cutaway.gd'
), [int]$TimeoutSeconds = 600, [switch]$Append)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$godotPath = 'D:/Downloads Chrome/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe'
$logRoot = Join-Path $PSScriptRoot 'logs'
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
$results = @()
if ($Append -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'checks.json'))) {
    $results = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'checks.json') -Raw | ConvertFrom-Json)
}

function Invoke-Check([string]$Script, [bool]$Enabled) {
    $label = $Script.Replace('/', '_').Replace('.gd', '') + $(if ($Enabled) { '_ligado' } else { '_desligado' })
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $godotPath
    $info.WorkingDirectory = $projectRoot
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    foreach ($arg in @('--headless', '--path', '.', '--script', "res://$Script", '--', '--no-save')) {
        $info.ArgumentList.Add($arg)
    }
    $info.Environment['GETECO_BAKED_BUILDINGS'] = $(if ($Enabled) { '1' } else { '0' })
    $process = [Diagnostics.Process]::Start($info)
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $timedOut = $false
    while (-not $process.WaitForExit(30000)) {
        if ([DateTime]::UtcNow -ge $deadline) {
            # Mata somente a árvore iniciada por esta execução.
            $process.Kill($true)
            $process.WaitForExit()
            $timedOut = $true
            break
        }
    }
    $output = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
    [IO.File]::WriteAllText((Join-Path $logRoot "$label.log"), $output)
    $row = [ordered]@{ script = $Script; baked_enabled = $Enabled; exit_code = $process.ExitCode; timeout = $timedOut; log = "tools/building_bake/logs/$label.log" }
    Write-Output "P6_CHECK $label código=$($row.exit_code) timeout=$timedOut"
    $process.Dispose()
    return $row
}

foreach ($script in $Scripts) {
    $messages = @(Invoke-Check $script $true)
    $row = $messages[-1]
    $messages[0..($messages.Count - 2)] | Write-Host
    $results += $row
    if ($row.exit_code -ne 0) {
        $messages = @(Invoke-Check $script $false)
        $results += $messages[-1]
        $messages[0..($messages.Count - 2)] | Write-Host
    }
    [IO.File]::WriteAllText((Join-Path $PSScriptRoot 'checks.json'), (ConvertTo-Json -InputObject @($results) -Depth 8))
}
