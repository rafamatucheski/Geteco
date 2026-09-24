param([switch]$Editor, [string]$GodotPath = $env:GODOT_EXE)
$ErrorActionPreference = 'Stop'
if (-not $GodotPath) {
    $installed = 'D:\Downloads Chrome\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe'
    if (Test-Path -LiteralPath $installed) { $GodotPath = $installed }
    else {
        $command = Get-Command godot -ErrorAction SilentlyContinue
        if ($command) { $GodotPath = $command.Source }
    }
}
if (-not $GodotPath -or -not (Test-Path -LiteralPath $GodotPath)) {
    throw 'Godot não encontrado. Informe -GodotPath ou abra project.godot no Godot 4.7.'
}
# New scripts can arrive even when the import directory already exists.
$importLog = Join-Path $PSScriptRoot 'startup-import.log'
$import = Start-Process -FilePath $GodotPath -ArgumentList @('--headless','--path',('"'+$PSScriptRoot+'"'),'--editor','--import','--quit','--log-file',('"'+$importLog+'"')) -WindowStyle Hidden -Wait -PassThru
if ($import.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $importLog)) { throw "A preparação do Geteco V2 falhou. Consulte $importLog" }
$importErrors = Select-String -LiteralPath $importLog -Pattern '^SCRIPT ERROR:|^ERROR: Failed to load script|Parse Error:|Compile Error:'
if ($importErrors) { throw "Há erros nos scripts do Geteco V2. Consulte $importLog" }
$arguments = @('--path',('"'+$PSScriptRoot+'"'))
if ($Editor) { $arguments += '--editor' }
Start-Process -FilePath $GodotPath -ArgumentList $arguments -WindowStyle Normal
