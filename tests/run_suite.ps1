# Roda a suíte funcional: todo tests/**/test_*.gd, cada um em um processo Godot
# com --no-save (nunca toca o save do jogador). O teste visual usa renderização; os demais rodam headless. Cada teste é um script
# SceneTree que sai com 0 (passou) ou 1 (falhou).
#
# Uso:  powershell -ExecutionPolicy Bypass -File tests/run_suite.ps1 [-Filter texto] [-Only a,b] [-TimeoutSec 600]
# Medições (tests/measure/) e capturas (tests/capture/) ficam de fora: precisam de
# renderização real e não têm PASS/FAIL.
param(
    [string]$Filter = '',
    [string]$Only = '',   # nomes separados por vírgula (sem .gd)
    [int]$TimeoutSec = 600,   # testes de integração (despacho, campanha) levam 4–5 min
    [string]$GodotPath = $env:GODOT_EXE
)
$ErrorActionPreference = 'Stop'
$onlyNames = @($Only.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$root = Split-Path -Parent $PSScriptRoot
$reportDir = Join-Path $root 'evidence\test-suite'
if (-not $GodotPath) {
    $installed = 'D:\Downloads Chrome\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
    if (Test-Path -LiteralPath $installed) { $GodotPath = $installed } else { throw 'Defina GODOT_EXE com o caminho do Godot (_console.exe).' }
}
$running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like 'Godot*' -and $_.MainWindowTitle -notlike '*Godot Engine*' })
if ($running.Count -gt 0) { Write-Warning "Há outra instância do Godot rodando; os resultados podem ser afetados." }

$tests = Get-ChildItem -Path (Join-Path $root 'tests') -Recurse -Filter 'test_*.gd' |
    Where-Object { $_.FullName -notmatch '\\tests\\(measure|capture)\\' -and $_.Name -like "*$Filter*" -and ($onlyNames.Count -eq 0 -or $onlyNames -contains $_.BaseName) } |
    Sort-Object FullName
$results = @()
foreach ($test in $tests) {
    $relative = $test.FullName.Substring($root.Length + 1).Replace('\', '/')
    $started = Get-Date
    $log = [System.IO.Path]::GetTempFileName()
    # Testes de save exigem um diretório único dentro do temp do sistema.
    $saveRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('geteco-suite-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $saveRoot | Out-Null
    $godotArgs = @('--path', ('"' + $root + '"'), '--script', "res://$relative", '--', '--no-save', '--skip-arrival', ('"--isolated-save-root=' + $saveRoot + '"'))
    if ($test.BaseName -eq 'test_android_controls') { $godotArgs += '--touch-controls' }
    if ($test.BaseName -in @('test_harbor_gameplay_acceptance', 'test_urban_asset_library', 'test_vertice_depth', 'test_vertice_site_depth', 'test_vertice_undercroft_geometry', 'test_vertice_packing_depth', 'test_police_frontage_geometry')) {
        $process = Start-Process -FilePath $GodotPath -ArgumentList ($godotArgs + '--population=8') `
            -WindowStyle Hidden -PassThru -RedirectStandardOutput $log -RedirectStandardError "$log.err"
    } else {
        $process = Start-Process -FilePath $GodotPath -ArgumentList (@('--headless') + $godotArgs) `
            -NoNewWindow -PassThru -RedirectStandardOutput $log -RedirectStandardError "$log.err"
    }
    # Sem ler o Handle logo após iniciar, o PowerShell não preenche ExitCode.
    $null = $process.Handle
    if (-not $process.WaitForExit($TimeoutSec * 1000)) {
        # Mata a árvore: o _console.exe do Godot abre o executável real como filho.
        & taskkill /T /F /PID $process.Id | Out-Null
        $null = $process.WaitForExit(3000)
        $status = 'TEMPO'
    } elseif ($process.ExitCode -eq 0) { $status = 'PASSOU' } else { $status = 'FALHOU' }
    $seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
    $tail = (Get-Content $log -ErrorAction SilentlyContinue | Where-Object { $_ -match 'PASS|FAIL|ERROR' } | Select-Object -Last 3) -join ' | '
    $stdoutPath = ''
    $stderrPath = ''
    if ($status -ne 'PASSOU') {
        $logDir = Join-Path $reportDir 'logs'
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null
        $logName = '{0}-{1}' -f $test.BaseName, [guid]::NewGuid().ToString('N')
        $stdoutPath = Join-Path $logDir "$logName.stdout.log"
        $stderrPath = Join-Path $logDir "$logName.stderr.log"
        Move-Item -LiteralPath $log -Destination $stdoutPath
        Move-Item -LiteralPath "$log.err" -Destination $stderrPath
    } else {
        Remove-Item -LiteralPath $log, "$log.err" -ErrorAction SilentlyContinue
    }
    $tempPath = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    $saveRootPath = [System.IO.Path]::GetFullPath($saveRoot)
    if (-not $saveRootPath.StartsWith($tempPath, [System.StringComparison]::OrdinalIgnoreCase) -or
        -not [System.IO.Path]::GetFileName($saveRootPath).StartsWith('geteco-suite-')) {
        throw "Recusando remover diretório fora do temp da suíte: $saveRootPath"
    }
    Remove-Item -LiteralPath $saveRootPath -Recurse -Force -ErrorAction SilentlyContinue
    $results += [pscustomobject]@{ Teste = $relative; Resultado = $status; Segundos = $seconds; Saida = $tail; Stdout = $stdoutPath; Stderr = $stderrPath }
    Write-Host ("{0,-7} {1,6}s  {2}" -f $status, $seconds, $relative)
}
$passed = @($results | Where-Object Resultado -eq 'PASSOU').Count
Write-Host ""
Write-Host "Suíte: $passed de $($results.Count) passaram."
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
$stamp = Get-Date -Format 'yyyy-MM-dd_HHmm'
$results | ConvertTo-Json -Depth 3 | Set-Content -Encoding utf8 (Join-Path $reportDir "suite-$stamp.json")
if ($passed -ne $results.Count) { exit 1 }
