# Executa toda a auditoria de gameplay (tests/claude_gameplay_audit/test_audit_*.gd)
# contra o Godot real, headless, e classifica cada teste como:
#   APROVADO      (exit code 0)
#   FALHOU        (exit code 1)
#   NAO_EXECUTADO (qualquer outro codigo -- watchdog/timeout/crash/erro de parse)
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File tests\claude_gameplay_audit\run_all.ps1
#   powershell -ExecutionPolicy Bypass -File tests\claude_gameplay_audit\run_all.ps1 -GodotExe "C:\caminho\Godot.exe"
#
# Nao usa saves reais do jogador: cada teste redireciona o SaveManager para um
# diretorio isolado em OS.get_temp_dir() antes de tocar em qualquer arquivo de save.

param(
    [string]$GodotExe = "D:\Downloads Chrome\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$root = Split-Path -Parent $root
$auditDir = Join-Path $root "tests\claude_gameplay_audit"
$logsDir = Join-Path $auditDir "logs"
New-Item -ItemType Directory -Force -Path $logsDir | Out-Null

if (-not (Test-Path $GodotExe)) {
    Write-Error "Executavel do Godot nao encontrado em: $GodotExe -- passe -GodotExe <caminho> apontando para o Godot 4.7 instalado nesta maquina."
    exit 2
}

$testFiles = Get-ChildItem -Path $auditDir -Filter "test_audit_*.gd" | Sort-Object Name
$results = @()

foreach ($file in $testFiles) {
    $name = $file.BaseName
    $resPath = "res://tests/claude_gameplay_audit/$($file.Name)"
    $logPath = Join-Path $logsDir "$name.stdout.log"
    Write-Host ("==> Executando " + $name + " ...") -ForegroundColor Cyan

    $proc = Start-Process -FilePath $GodotExe `
        -ArgumentList @("--headless", "--path", "`"$root`"", "--script", $resPath) `
        -NoNewWindow -PassThru -Wait `
        -RedirectStandardOutput $logPath -RedirectStandardError "$logPath.err"

    $exitCode = $proc.ExitCode
    $status = "NAO_EXECUTADO"
    if ($exitCode -eq 0) { $status = "APROVADO" }
    elseif ($exitCode -eq 1) { $status = "FALHOU" }
    $color = "Yellow"
    if ($status -eq "APROVADO") { $color = "Green" }
    elseif ($status -eq "FALHOU") { $color = "Red" }
    Write-Host ("    " + $status + " (exit=" + $exitCode + ") -- log: " + $logPath) -ForegroundColor $color
    $results += [PSCustomObject]@{ Test = $name; Status = $status; ExitCode = $exitCode; Log = $logPath }
}

Write-Host ""
Write-Host "================= RESUMO DA AUDITORIA =================" -ForegroundColor Cyan
$results | Format-Table -AutoSize
$approved = @($results | Where-Object { $_.Status -eq "APROVADO" }).Count
$failed = @($results | Where-Object { $_.Status -eq "FALHOU" }).Count
$notRun = @($results | Where-Object { $_.Status -eq "NAO_EXECUTADO" }).Count
Write-Host ("Aprovados: " + $approved + " | Falharam: " + $failed + " | Nao executados: " + $notRun + " | Total: " + $results.Count)

if ($failed -gt 0 -or $notRun -gt 0) { exit 1 }
exit 0
