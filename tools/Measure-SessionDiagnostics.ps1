param([string]$Prefix = ('session-observability-' + [Guid]::NewGuid().ToString('N').Substring(0,8)))
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$engine = 'D:/Downloads Chrome/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe'
if ($Prefix -notmatch '^[a-zA-Z0-9-]+$') { throw 'Prefixo invalido.' }
function Get-Runtimes {
    @(Get-CimInstance Win32_Process -Filter "Name LIKE 'Godot%'" | Where-Object { $_.CommandLine -notmatch '(^|\s)--editor(\s|$)' })
}
if ((Get-Runtimes).Count -gt 0) { throw 'Comparacao pendente: ha runtimes Godot de outras sessoes. Nenhum processo foi encerrado.' }
# Hashes do retrato detectam mudanças concorrentes nas fontes entre as duas rodadas.
$sources = @(Get-ChildItem -LiteralPath (Join-Path $workspace 'runtime'),(Join-Path $workspace 'scripts'),(Join-Path $workspace 'gameplay'),(Join-Path $workspace 'world'),(Join-Path $workspace 'activities') -Recurse -File | Where-Object { $_.Extension -in '.gd','.cs' })
function Get-Revision {
    @(Get-FileHash -LiteralPath $sources.FullName -Algorithm SHA256 | Select-Object Path,Hash) | ConvertTo-Json -Compress
}
$revision = Get-Revision
$originalLog = $env:HARBOR_SESSION_LOG
$originalProfile = $env:HARBOR_SESSION_PROFILE
$originalStall = $env:HARBOR_STALL_LOG
$originalSteps = $env:HARBOR_MAX_PHYSICS_STEPS
try {
    & dotnet build (Join-Path $workspace 'Harbor.csproj') --no-restore -v quiet
    if ($LASTEXITCODE -ne 0) { throw 'Build .NET falhou.' }
    $reports = @{}
    foreach ($mode in @('detailed','essential')) {
        if ((Get-Runtimes).Count -gt 0) { throw 'Outro runtime iniciou; nao medir em concorrencia.' }
        $env:HARBOR_SESSION_LOG = '1'
        $env:HARBOR_SESSION_PROFILE = if ($mode -eq 'detailed') {'1'} else {'0'}
        $env:HARBOR_STALL_LOG = if ($mode -eq 'detailed') {'1'} else {'0'}
        $env:HARBOR_MAX_PHYSICS_STEPS = '3'
        $label = "$Prefix-$mode"
        if (Test-Path -LiteralPath (Join-Path $workspace "evidence/$label.json")) { throw 'Prefixo ja possui evidencia; use um prefixo novo.' }
        $stdout = Join-Path $workspace "evidence/$label.log"
        $stderr = Join-Path $workspace "evidence/$label.err"
        $process = Start-Process -FilePath $engine -ArgumentList @('--path',('"'+$workspace+'"'),'--script','res://tests/measure/measure_session_diagnostics.gd','--','--no-save',"--label=$label") -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
        $watch = [Diagnostics.Stopwatch]::StartNew()
        try {
            while (-not $process.HasExited) {
                $foreign = @(Get-Runtimes | Where-Object { $_.ProcessId -ne $process.Id -and $_.ParentProcessId -ne $process.Id })
                if ($foreign.Count -gt 0 -or $watch.Elapsed.TotalSeconds -gt 180) { throw 'Medicao interrompida: concorrencia ou timeout. Somente o processo deste benchmark sera encerrado.' }
                Start-Sleep -Milliseconds 500
                $process.Refresh()
            }
            $process.WaitForExit()
            if ($process.ExitCode -ne 0) { throw "Falha no benchmark $label; consulte $stdout e $stderr" }
        } finally {
            if (-not $process.HasExited) {
                $owned = @(Get-CimInstance Win32_Process | Where-Object ParentProcessId -eq $process.Id)
                foreach ($child in $owned) { Stop-Process -Id $child.ProcessId -ErrorAction SilentlyContinue }
                Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
            }
        }
        $reports[$mode] = Get-Content -LiteralPath (Join-Path $workspace "evidence/$label.json") -Raw | ConvertFrom-Json
    }
    $unchanged = (Get-Revision) -eq $revision
    $comparison = @{ baseline=$reports.detailed; current=$reports.essential; source_unchanged=$unchanged;
        p95_change_percent=100*($reports.essential.summary.p95_ms/$reports.detailed.summary.p95_ms-1);
        p99_change_percent=100*($reports.essential.summary.p99_ms/$reports.detailed.summary.p99_ms-1);
        budget_ms=16.67; confirmation_threshold_percent=5;
        interpretation='Paired stationary Main samples; population can vary. >5% requires confirmation; no automatic global approval.' }
    $comparison | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $workspace "evidence/$Prefix-comparison.json") -Encoding UTF8
    if (-not $unchanged) { throw 'Comparacao inconclusiva: fontes mudaram durante as rodadas.' }
    Write-Output ($comparison | Select-Object p95_change_percent,p99_change_percent,source_unchanged | ConvertTo-Json)
} finally {
    $env:HARBOR_SESSION_LOG = $originalLog
    $env:HARBOR_SESSION_PROFILE = $originalProfile
    $env:HARBOR_STALL_LOG = $originalStall
    $env:HARBOR_MAX_PHYSICS_STEPS = $originalSteps
}
