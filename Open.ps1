param([switch]$Editor, [switch]$PrepareOnly, [string]$GodotPath = $env:GODOT_EXE, [switch]$PauseUsageMonitor)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'tools\Godot.ps1')
$GodotPath = Resolve-ProjectGodot $GodotPath
Build-ProjectCSharp $PSScriptRoot $GodotPath
# New scripts can arrive even when the import directory already exists.
$importLog = Join-Path $PSScriptRoot 'startup-import.log'
$import = Start-Process -FilePath $GodotPath -ArgumentList @('--headless','--path',('"'+$PSScriptRoot+'"'),'--editor','--import','--quit','--log-file',('"'+$importLog+'"')) -WindowStyle Hidden -PassThru
# Em 16/10 o Godot headless terminou a importação (o log chega a "loading_editor_layout DONE") e o
# lançador _console.exe ficou vivo, sem filho e sem CPU: `-Wait` esperava para sempre e o jogo nunca
# abria. Agora espera o processo OU o fim do log parado por 20 s, e encerra a árvore se sobrar.
$importFinished = $false
$importStarted = Get-Date
while (-not $import.HasExited) {
    Start-Sleep -Seconds 2
    if (Test-Path -LiteralPath $importLog) {
        $logFile = Get-Item -LiteralPath $importLog
        $idle = ((Get-Date) - $logFile.LastWriteTime).TotalSeconds
        if ($idle -ge 20 -and (Select-String -LiteralPath $importLog -Pattern 'DONE \] loading_editor_layout' -Quiet)) { $importFinished = $true; break }
    }
    if (((Get-Date) - $importStarted).TotalMinutes -ge 15) { break }
}
if (-not $import.HasExited) {
    & taskkill.exe /F /T /PID $import.Id | Out-Null
    if (-not $importFinished) { throw "A preparação do Geteco V2 passou de 15 minutos sem terminar. Consulte $importLog" }
} elseif ($import.ExitCode -ne 0) { throw "A preparação do Geteco V2 falhou. Consulte $importLog" }
if (-not (Test-Path -LiteralPath $importLog)) { throw "A preparação do Geteco V2 não gerou log. Consulte $importLog" }
$importErrors = Select-String -LiteralPath $importLog -Pattern '^SCRIPT ERROR:|^ERROR: Failed to load script|Parse Error:|Compile Error:'
if ($importErrors) { throw "Há erros nos scripts do Geteco V2. Consulte $importLog" }
if ($PrepareOnly) { return }
# O SDL re-enumera dispositivos DirectInput na thread principal a cada aviso de mudança HID
# (qualquer HID, não só controles) — engasgos de 80–94 ms antes da física na captura rec2.
# Desligar o DirectInput mantém XInput/HIDAPI (Xbox, DualSense, DualShock, Switch), mas perde
# gamepads genéricos só-DirectInput, volantes, manches e force feedback por DirectInput.
# Para voltar: defina SDL_JOYSTICK_DIRECTINPUT=1 antes de rodar. Ver docs/reviews/sdl-input-stalls-20261005.md.
# O editor também herda a variável, então F5 roda nas mesmas condições.
if (-not $env:SDL_JOYSTICK_DIRECTINPUT) { $env:SDL_JOYSTICK_DIRECTINPUT = '0' }
$arguments = @('--path',('"'+$PSScriptRoot+'"'))
if ($Editor) { $arguments += '--editor' }
$launchPath = $GodotPath -replace '_console\.exe$', '.exe'
if (-not (Test-Path -LiteralPath $launchPath)) { $launchPath = $GodotPath }
if ($PauseUsageMonitor -and -not $Editor) {
    . (Join-Path $PSScriptRoot 'tools\UsageMonitorPause.ps1')
    Invoke-WithUsageMonitorPaused {
        $gameProcess = Start-Process -FilePath $launchPath -ArgumentList $arguments -WindowStyle Normal -PassThru
        try { $gameProcess.WaitForExit() } finally { $gameProcess.Dispose() }
    }
    return
}
Start-Process -FilePath $launchPath -ArgumentList $arguments -WindowStyle Normal
