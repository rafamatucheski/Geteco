param([switch]$Editor, [switch]$PrepareOnly, [string]$GodotPath = $env:GODOT_EXE, [switch]$PauseUsageMonitor)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'tools\Godot.ps1')
$GodotPath = Resolve-ProjectGodot $GodotPath
Build-ProjectCSharp $PSScriptRoot $GodotPath
# New scripts can arrive even when the import directory already exists.
$importLog = Join-Path $PSScriptRoot 'startup-import.log'
$import = Start-Process -FilePath $GodotPath -ArgumentList @('--headless','--path',('"'+$PSScriptRoot+'"'),'--editor','--import','--quit','--log-file',('"'+$importLog+'"')) -WindowStyle Hidden -Wait -PassThru
if ($import.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $importLog)) { throw "A preparação do Geteco V2 falhou. Consulte $importLog" }
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
