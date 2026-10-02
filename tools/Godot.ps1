# Motor e compilacao compartilhados pelo editor, jogo e verificacoes.
function Resolve-ProjectGodot([string]$Requested = $env:GODOT_EXE) {
    if (-not $Requested) {
        $Requested = 'D:\Downloads Chrome\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe'
    }
    if (-not (Test-Path -LiteralPath $Requested -PathType Leaf)) {
        throw 'Godot .NET nao encontrado. Informe -GodotPath ou GODOT_EXE com a instalacao mono.'
    }
    $version = (& $Requested --version | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $version -notmatch '(^|\.)mono(\.|$)') {
        throw "O projeto requer Godot .NET (mono), com suporte a C#. Motor informado: $Requested ($version)"
    }
    return $Requested
}

function Build-ProjectCSharp([string]$Root, [string]$Engine) {
    Push-Location -LiteralPath $Root
    try {
        $packages = Join-Path (Split-Path -Parent $Engine) 'GodotSharp\Tools\nupkgs'
        & dotnet restore Harbor.csproj --source $packages --source https://api.nuget.org/v3/index.json
        if ($LASTEXITCODE -ne 0) { throw 'A preparacao das dependencias C# falhou.' }
        & dotnet build Harbor.csproj --no-restore
        if ($LASTEXITCODE -ne 0) { throw 'A compilacao C# falhou; o jogo nao sera iniciado com uma DLL antiga.' }
    } finally {
        Pop-Location
    }
}
