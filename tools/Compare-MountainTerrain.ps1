param([ValidateSet('Antes','Depois')][string]$Variant = 'Depois')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'Godot.ps1')
$enginePath = Resolve-ProjectGodot
Build-ProjectCSharp $projectRoot $enginePath
& $enginePath --headless --path $projectRoot --editor --import --quit
if ($LASTEXITCODE -ne 0) { throw 'Falha ao preparar os recursos do terreno.' }
if (-not $env:SDL_JOYSTICK_DIRECTINPUT) { $env:SDL_JOYSTICK_DIRECTINPUT = '0' }
$launchArgs = @('--path', ('"'+$projectRoot+'"'), '--script', 'res://tests/measure/measure_terrain3d_mountain.gd', '--', '--no-save', '--skip-arrival', '--interactive')
if ($Variant -eq 'Antes') { $launchArgs += '--terrain3d-baseline' }
# Comparação interativa explícita pedida pelo jogador.
Start-Process -FilePath $enginePath -ArgumentList $launchArgs -WindowStyle Normal
