# Gera APK de teste; não certifica estabilidade nem controles de toque.
param(
    [string]$GodotPath = $env:GODOT_EXE,
    [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $GodotPath) {
    $GodotPath = 'D:\Downloads Chrome\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe'
}
if (-not (Test-Path -LiteralPath $GodotPath)) { throw 'Defina GODOT_EXE ou -GodotPath com o executável Godot.' }
$version = (& $GodotPath --version | Select-Object -Last 1).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Não foi possível consultar a versão do Godot.' }
if ($version -notmatch '^4\.7\.2\.stable\.mono\.') { throw 'Use Godot 4.7.2 .NET (mono) para preservar os scripts C#.' }
Write-Host "Godot: $version"
$match = [regex]::Match($version, '^(\d+\.\d+(?:\.\d+)?)\.([^.]+)')
if (-not $match.Success) { throw "Versão não reconhecida: $version" }
$templateVersion = $match.Groups[1].Value + '.' + $match.Groups[2].Value + '.mono'
$template = Join-Path $env:APPDATA "Godot\export_templates\$templateVersion\android_debug.apk"
if (-not (Test-Path -LiteralPath $template)) {
    throw "Template ausente: $template. Instale os templates da MESMA versão do editor pelo gerenciador de templates do Godot."
}
Write-Host "Template: $template"
if ($CheckOnly) { return }
& dotnet build (Join-Path $root 'Harbor.csproj') --nologo -v minimal
if ($LASTEXITCODE -ne 0) { throw 'Compilação C# falhou; exportação cancelada.' }
$projectText = Get-Content -LiteralPath (Join-Path $root 'project.godot') -Raw
$versionMatch = [regex]::Match($projectText, 'config/version="([0-9.]+)"')
if (-not $versionMatch.Success) { throw 'Versão do projeto ausente.' }
$output = Join-Path $root ('builds\android\harbor-' + $versionMatch.Groups[1].Value + '-debug.apk')
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $output) | Out-Null
& $GodotPath --headless --path $root --export-debug 'Harbor Android' $output
if ($LASTEXITCODE -ne 0) { throw "Exportação falhou ($LASTEXITCODE). Consulte os erros do Godot acima." }
if (-not (Test-Path -LiteralPath $output)) { throw 'O Godot não produziu o APK esperado.' }
Write-Host "APK: $output"
Get-FileHash -LiteralPath $output -Algorithm SHA256
