param([string]$Label = 'final', [string]$PresetsPath = '')
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/Runner.Common.ps1"
$projectRoot = Split-Path $PSScriptRoot -Parent
$null = Assert-GodotExclusive
$engine = Resolve-GodotEngine ''
Build-ProjectCSharp $projectRoot $engine
function Invoke-OwnedEngine([string[]]$EngineArgs, [string]$Log, [int]$TimeoutMs) {
    $start = [System.Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $engine
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in $EngineArgs) { $start.ArgumentList.Add($argument) }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $start
    $null = $process.Start()
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutMs)) {
        $stopped = Stop-OwnedGodot $process
        throw "Owned export probe timed out; stopped=$stopped; PID=$($process.Id)"
    }
    [System.IO.File]::WriteAllText($Log,$stdout.Result+$stderr.Result)
    $code = $process.ExitCode
    $process.Dispose()
    return $code
}
$output = Join-Path $projectRoot "evidence/export-mountain-dialogue-20261007/$Label"
New-Item -ItemType Directory -Force -Path $output | Out-Null
$fixture = Join-Path ([System.IO.Path]::GetTempPath()) ('geteco-dialogue-export-' + [guid]::NewGuid().ToString('N'))
$runRoot = Join-Path $fixture 'run-empty'
New-Item -ItemType Directory -Force -Path $fixture,$runRoot,(Join-Path $fixture 'data/campaign') | Out-Null
$relativeJson = 'data/campaign/mountain-story-dialogue.json'
Copy-Item -LiteralPath (Join-Path $projectRoot $relativeJson) -Destination (Join-Path $fixture $relativeJson)
$sourceHash = (Get-FileHash -LiteralPath (Join-Path $projectRoot $relativeJson) -Algorithm SHA256).Hash.ToLowerInvariant()
if ($PresetsPath -eq '') { $PresetsPath = Join-Path $projectRoot 'export_presets.cfg' }
$presets = Get-Content -LiteralPath $PresetsPath -Raw
[System.IO.File]::WriteAllText((Join-Path $output 'export_presets.snapshot.cfg'),$presets)
$coverage = @()
foreach ($match in [regex]::Matches($presets,'(?ms)^\[preset\.(\d+)\]\s*(.*?)(?=^\[|\z)')) {
    $section = $match.Groups[2].Value
    $include = [regex]::Match($section,'(?m)^include_filter="([^"]*)"').Groups[1].Value
    $exclude = [regex]::Match($section,'(?m)^exclude_filter="([^"]*)"').Groups[1].Value
    $included = @($include.Split(',') | Where-Object { $relativeJson -like $_.Trim() }).Count -gt 0
    $excluded = @($exclude.Split(',') | Where-Object { $_.Trim() -ne '' -and $relativeJson -like $_.Trim() }).Count -gt 0
    $coverage += [pscustomobject]@{Preset=$match.Groups[1].Value;Included=$included;Excluded=$excluded}
}
# O exportador real do Windows recebe o texto do preset de produção sem mudança.
# O fixture tem só o JSON de runtime e uma sonda, nunca o mundo do jogo.
[System.IO.File]::WriteAllText((Join-Path $fixture 'export_presets.cfg'),$presets)
[System.IO.File]::WriteAllText((Join-Path $fixture 'project.godot'),"config_version=5`n[application]`nconfig/name=`"Mountain dialogue export probe`"`n[rendering]`nrenderer/rendering_method=`"gl_compatibility`"`n")
$probe = @'
extends SceneTree
func _initialize() -> void:
    var path := "res://data/campaign/mountain-story-dialogue.json"
    if not FileAccess.file_exists(path):
        print("DIALOGUE_PACK FAIL missing mountain story JSON")
        quit(1)
        return
    var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    var valid := data is Dictionary
    for key in ["cargo_identified","cargo_manifest","cave_shelter","vicente_note"]:
        valid = valid and data.get(key) is Array and not data[key].is_empty()
    var digest := FileAccess.get_sha256(path)
    print("DIALOGUE_PACK ", "PASS" if valid and digest == "EXPECTED_HASH" else "FAIL", " sha256=", digest)
    quit(0 if valid and digest == "EXPECTED_HASH" else 1)
'@
[System.IO.File]::WriteAllText((Join-Path $fixture 'probe.gd'),$probe.Replace('EXPECTED_HASH',$sourceHash))
$pack = Join-Path $output 'dialogue.pck'
$exportCode = Invoke-OwnedEngine @('--headless','--path',$fixture,'--export-pack','Geteco V2 Windows',$pack) (Join-Path $output 'export.log') 60000
if ($exportCode -ne 0) { throw "Mini export failed ($exportCode): $output/export.log" }
$null = Assert-GodotExclusive
# Não há JSON do projeto abaixo desta pasta de trabalho: só o PCK pode fornecê-lo.
$probeCode = Invoke-OwnedEngine @('--headless','--path',$runRoot,'--main-pack',$pack,'--script','res://probe.gd') (Join-Path $output 'probe.log') 15000
$report = [pscustomobject]@{Coverage=$coverage;ExportExit=$exportCode;ProbeExit=$probeCode;SourceHash=$sourceHash;Fixture=$fixture;Pack=$pack}
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $output 'report.json')
$report | ConvertTo-Json -Depth 5
Get-Content -LiteralPath (Join-Path $output 'probe.log')
# include_filter não é a política de export inteira: all_resources no Godot 4.7.2
# também empacota este JSON sem filtro explícito. Valem os bytes empacotados de fato.
if ($probeCode -ne 0) { exit 1 }
