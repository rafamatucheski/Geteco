# Roda a suíte funcional: todo tests/**/test_*.gd, cada um em um processo Godot
# headless com --no-save (nunca toca o save do jogador). Cada teste é um script
# SceneTree que sai com 0 (passou) ou 1 (falhou).
#
# Uso:  powershell -ExecutionPolicy Bypass -File tests/run_suite.ps1 [-Filter texto] [-Only a,b] [-TimeoutSec 300]
# Medições (tests/measure/) e capturas (tests/capture/) ficam de fora: precisam de
# renderização real e não têm PASS/FAIL.
param(
    [string]$Filter = '',
    [string]$Only = '',   # nomes separados por vírgula (sem .gd)
    [int]$TimeoutSec = 300,
    [string]$GodotPath = $env:GODOT_EXE
)
$ErrorActionPreference = 'Stop'
$onlyNames = @($Only.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$root = Split-Path -Parent $PSScriptRoot
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
    $process = Start-Process -FilePath $GodotPath -ArgumentList @('--headless', '--path', ('"' + $root + '"'), '--script', "res://$relative", '--', '--no-save', '--skip-arrival', ('"--isolated-save-root=' + $saveRoot + '"')) `
        -NoNewWindow -PassThru -RedirectStandardOutput $log -RedirectStandardError "$log.err"
    # Sem ler o Handle logo após iniciar, o PowerShell não preenche ExitCode.
    $null = $process.Handle
    if (-not $process.WaitForExit($TimeoutSec * 1000)) {
        # Mata a árvore: o _console.exe do Godot abre o executável real como filho.
        & taskkill /T /F /PID $process.Id | Out-Null
        $status = 'TEMPO'
    } elseif ($process.ExitCode -eq 0) { $status = 'PASSOU' } else { $status = 'FALHOU' }
    $seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
    $tail = (Get-Content $log -ErrorAction SilentlyContinue | Where-Object { $_ -match 'PASS|FAIL|ERROR' } | Select-Object -Last 3) -join ' | '
    Remove-Item $log, "$log.err" -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $saveRoot -ErrorAction SilentlyContinue
    $results += [pscustomobject]@{ Teste = $relative; Resultado = $status; Segundos = $seconds; Saida = $tail }
    Write-Host ("{0,-7} {1,6}s  {2}" -f $status, $seconds, $relative)
}
$passed = @($results | Where-Object Resultado -eq 'PASSOU').Count
Write-Host ""
Write-Host "Suíte: $passed de $($results.Count) passaram."
$reportDir = Join-Path $root 'evidence\test-suite'
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
$stamp = Get-Date -Format 'yyyy-MM-dd_HHmm'
$results | ConvertTo-Json -Depth 3 | Set-Content -Encoding utf8 (Join-Path $reportDir "suite-$stamp.json")
if ($passed -ne $results.Count) { exit 1 }
