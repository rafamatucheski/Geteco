# Gera APK de teste; não certifica estabilidade nem controles de toque.
param(
    [string]$GodotPath = $env:GODOT_EXE,
    [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $GodotPath) {
    $GodotPath = 'D:\Downloads Chrome\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
}
if (-not (Test-Path -LiteralPath $GodotPath)) { throw 'Defina GODOT_EXE ou -GodotPath com o executável Godot.' }
$version = (& $GodotPath --version | Select-Object -Last 1).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Não foi possível consultar a versão do Godot.' }
Write-Host "Godot: $version"
$match = [regex]::Match($version, '^(\d+\.\d+(?:\.\d+)?)\.([^.]+)')
if (-not $match.Success) { throw "Versão não reconhecida: $version" }
$templateVersion = $match.Groups[1].Value + '.' + $match.Groups[2].Value
$template = Join-Path $env:APPDATA "Godot\export_templates\$templateVersion\android_debug.apk"
if (-not (Test-Path -LiteralPath $template)) {
    throw "Template ausente: $template. Instale os templates da MESMA versão do editor pelo gerenciador de templates do Godot."
}
Write-Host "Template: $template"
if ($CheckOnly) { return }
$output = Join-Path $root 'builds\android\harbor-0.3.1-debug.apk'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $output) | Out-Null
& $GodotPath --headless --path $root --export-debug 'Harbor Android' $output
if ($LASTEXITCODE -ne 0) { throw "Exportação falhou ($LASTEXITCODE). Consulte os erros do Godot acima." }
if (-not (Test-Path -LiteralPath $output)) { throw 'O Godot não produziu o APK esperado.' }
Write-Host "APK: $output"
Get-FileHash -LiteralPath $output -Algorithm SHA256
