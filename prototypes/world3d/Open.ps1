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
# Initial import belongs exclusively to this nested project's own cache.
if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot '.godot/imported'))) {
    $import = Start-Process -FilePath $GodotPath -ArgumentList @('--headless','--path',('"'+$PSScriptRoot+'"'),'--editor','--import','--quit') -WindowStyle Hidden -Wait -PassThru
    if ($import.ExitCode -ne 0) { throw 'A importação do protótipo falhou.' }
}
$arguments = @('--path',('"'+$PSScriptRoot+'"'))
if ($Editor) { $arguments += '--editor' }
Start-Process -FilePath $GodotPath -ArgumentList $arguments -WindowStyle Normal
