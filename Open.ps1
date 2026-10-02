param([switch]$Editor, [switch]$PrepareOnly, [string]$GodotPath = $env:GODOT_EXE)
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
$arguments = @('--path',('"'+$PSScriptRoot+'"'))
if ($Editor) { $arguments += '--editor' }
$launchPath = $GodotPath -replace '_console\.exe$', '.exe'
if (-not (Test-Path -LiteralPath $launchPath)) { $launchPath = $GodotPath }
Start-Process -FilePath $launchPath -ArgumentList $arguments -WindowStyle Normal
