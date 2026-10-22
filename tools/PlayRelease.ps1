# Joga pelo export release em vez do binário do editor (22/10/2026).
# Por quê: o binário do editor roda o GDScript com as verificações de depuração; na mesma rota, com
# as opções do jogador a 3440x1440, mediu p50 8,95 ms contra 6,40-6,57 ms no release (+38 %), e um
# salvamento 34,3 contra 22,5 ms (docs/perf-playthrough-20261021.md). Save e opções são os mesmos
# (user://, pasta GetecoV2), então trocar de lançador não perde progresso.
# Exporta para builds\jogar\ só quando algum arquivo do jogo é mais novo que o pacote; senão abre direto.
# O export é feito numa pasta ao lado e só substitui o jogo anterior se terminar inteiro.
# -NoLaunch só prepara/exporta (para conferir o lançador sem abrir o jogo).
param([string]$GodotPath = $env:GODOT_EXE, [switch]$ForceExport, [switch]$PauseUsageMonitor, [switch]$NoLaunch)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'Godot.ps1')
$GodotPath = Resolve-ProjectGodot $GodotPath

# C# e importação (mesma preparação do Open.ps1; falha de script interrompe aqui).
& (Join-Path $root 'Open.ps1') -PrepareOnly -GodotPath $GodotPath

$out = Join-Path $root 'builds\jogar'
$exe = Join-Path $out 'GetecoV2.exe'
$pck = Join-Path $out 'GetecoV2.pck'
$needsExport = $ForceExport -or -not (Test-Path -LiteralPath $exe) -or -not (Test-Path -LiteralPath $pck)
if (-not $needsExport) {
    $packed = (Get-Item -LiteralPath $pck).LastWriteTimeUtc
    $sources = @('activities','addons','assets','audio','cutscenes','data','gameplay','migration','runtime','scripts','systems','ui','world') |
        ForEach-Object { Join-Path $root $_ } | Where-Object { Test-Path -LiteralPath $_ }
    $rootFiles = Get-ChildItem -LiteralPath $root -File | Where-Object { $_.Extension -in '.godot','.cfg','.csproj','.tres','.tscn' }
    $changed = @($rootFiles) + @(Get-ChildItem -LiteralPath $sources -Recurse -File -ErrorAction SilentlyContinue) |
        Where-Object { $_.LastWriteTimeUtc -gt $packed } | Select-Object -First 1
    $needsExport = $null -ne $changed
    if ($needsExport) { Write-Host "Jogo mudou desde o último pacote ($($changed.FullName)); exportando o release." }
}

if ($needsExport) {
    $staging = Join-Path $root 'builds\jogar-export'
    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $staging | Out-Null
    $stagedExe = Join-Path $staging 'GetecoV2.exe'
    $stagedPck = Join-Path $staging 'GetecoV2.pck'
    $log = Join-Path $root 'builds\jogar-export.log'
    Write-Host 'Exportando o release (alguns minutos na primeira vez)...'
    $started = Get-Date
    $export = Start-Process -FilePath $GodotPath -WindowStyle Hidden -PassThru -ArgumentList @(
        '--headless','--path',('"'+$root+'"'),'--export-release','"Geteco V2 Windows"',('"'+$stagedExe+'"'),'--log-file',('"'+$log+'"'))
    # O export às vezes não sai sozinho depois de gravar o pacote (CLAUDE.md): espera o processo OU
    # pacote e log parados por 20 s, e encerra a árvore se sobrar.
    $stable = $false
    while (-not $export.HasExited) {
        Start-Sleep -Seconds 2
        if ((Test-Path -LiteralPath $stagedPck) -and (Test-Path -LiteralPath $stagedExe) -and (Test-Path -LiteralPath $log)) {
            $pckIdle = ((Get-Date) - (Get-Item -LiteralPath $stagedPck).LastWriteTime).TotalSeconds
            $logIdle = ((Get-Date) - (Get-Item -LiteralPath $log).LastWriteTime).TotalSeconds
            if ($pckIdle -ge 20 -and $logIdle -ge 20) { $stable = $true; break }
        }
        if (((Get-Date) - $started).TotalMinutes -ge 20) { break }
    }
    if (-not $export.HasExited) { & taskkill.exe /F /T /PID $export.Id | Out-Null }
    elseif ($export.ExitCode -ne 0 -and -not $stable) { throw "O export do release falhou (código $($export.ExitCode)). Consulte $log" }
    if (-not (Test-Path -LiteralPath $stagedPck) -or (Get-Item -LiteralPath $stagedPck).LastWriteTime -lt $started -or (Get-Item -LiteralPath $stagedPck).Length -lt 1MB) {
        throw "O export do release não gerou o pacote. Consulte $log"
    }
    if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force }
    Move-Item -LiteralPath $staging -Destination $out
    Write-Host "Release pronto em $out ($([int]((Get-Date) - $started).TotalSeconds) s)."
}

if ($NoLaunch) { return }
# Mesmo ajuste do Open.ps1: DirectInput re-enumerado na thread principal travava 80-94 ms.
if (-not $env:SDL_JOYSTICK_DIRECTINPUT) { $env:SDL_JOYSTICK_DIRECTINPUT = '0' }
if ($PauseUsageMonitor) {
    . (Join-Path $PSScriptRoot 'UsageMonitorPause.ps1')
    Invoke-WithUsageMonitorPaused {
        $gameProcess = Start-Process -FilePath $exe -WorkingDirectory $out -WindowStyle Normal -PassThru
        try { $gameProcess.WaitForExit() } finally { $gameProcess.Dispose() }
    }
    return
}
Start-Process -FilePath $exe -WorkingDirectory $out -WindowStyle Normal
