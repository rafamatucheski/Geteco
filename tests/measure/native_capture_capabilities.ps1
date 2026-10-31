# Pré-checagem só leitura de captura nativa. Não inicia WPR/EventPipe, não muda
# privilégios, não suspende threads, não abre Godot, não altera saves nem fontes.
param(
    [string]$OutputPath,
    [string]$EnginePath='D:/Downloads Chrome/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64.exe',
    [string]$ProfilePath='D:/geteco/game/evidence/performance-implementation-20261002/game-cpu.wprp'
)
$ErrorActionPreference='Stop'

function File-Identity([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @{path=$Path;exists=$false} }
    $item=Get-Item -LiteralPath $Path
    $result=@{path=$item.FullName;exists=$true;bytes=$item.Length;sha256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
    if ($item.Extension -eq '.pdb') {
        $pdbStream=[IO.File]::OpenRead($item.FullName)
        try {
            $signature=[byte[]]::new(4)
            $null=$pdbStream.Read($signature,0,4)
            $result['format']=if ([Text.Encoding]::ASCII.GetString($signature) -eq 'BSJB') {'portable_managed'} else {'native_or_unknown_candidate_requires_identity_check'}
        } finally {$pdbStream.Dispose()}
    }
    return $result
}

function Native-CodeView([string]$Path) {
    # Informa a identidade do PDB embutido no motor, se houver. Um PDB com outro
    # GUID/idade ou um Harbor.pdb portátil não simboliza este executável nativo.
    $stream=$null
    try {
        $stream=[IO.File]::OpenRead($Path)
        $reader=[IO.BinaryReader]::new($stream)
        $stream.Position=0x3c
        $pe=[int]$reader.ReadUInt32()
        $stream.Position=$pe
        if ($reader.ReadUInt32() -ne 0x4550) { throw 'PE signature absent' }
        $null=$reader.ReadUInt16()
        $sections=[int]$reader.ReadUInt16()
        $stream.Position=$pe+20
        $optionalBytes=[int]$reader.ReadUInt16()
        $optionalStart=$pe+24
        $stream.Position=$optionalStart
        $magic=$reader.ReadUInt16()
        $dataStart=if ($magic -eq 0x20b) {$optionalStart+112} elseif ($magic -eq 0x10b) {$optionalStart+96} else {throw 'Unknown PE optional header'}
        $stream.Position=$dataStart+6*8
        $debugRva=[long]$reader.ReadUInt32()
        $debugBytes=[int]$reader.ReadUInt32()
        if ($debugRva -eq 0 -or $debugBytes -eq 0) { return @{available=$false;reason='native_image_has_no_debug_directory'} }
        $stream.Position=$optionalStart+$optionalBytes
        $debugOffset=$null
        for ($i=0;$i -lt $sections;$i++) {
            $sectionStart=$stream.Position
            $stream.Position=$sectionStart+8
            $virtualBytes=[long]$reader.ReadUInt32()
            $virtualRva=[long]$reader.ReadUInt32()
            $rawBytes=[long]$reader.ReadUInt32()
            $rawOffset=[long]$reader.ReadUInt32()
            if ($debugRva -ge $virtualRva -and $debugRva -lt $virtualRva+[Math]::Max($virtualBytes,$rawBytes)) {
                $debugOffset=$rawOffset+$debugRva-$virtualRva
            }
            $stream.Position=$sectionStart+40
        }
        if ($null -eq $debugOffset) { throw 'Debug directory RVA not mapped' }
        for ($i=0;$i -lt [int]($debugBytes/28);$i++) {
            $stream.Position=$debugOffset+$i*28+12
            $kind=$reader.ReadUInt32()
            $payloadBytes=[int]$reader.ReadUInt32()
            $null=$reader.ReadUInt32()
            $payloadOffset=[long]$reader.ReadUInt32()
            if ($kind -ne 2 -or $payloadBytes -lt 24) { continue }
            $stream.Position=$payloadOffset
            if ([Text.Encoding]::ASCII.GetString($reader.ReadBytes(4)) -ne 'RSDS') { continue }
            $guid=[Guid]::new($reader.ReadBytes(16))
            $age=$reader.ReadUInt32()
            $embedded=[Text.Encoding]::UTF8.GetString($reader.ReadBytes($payloadBytes-24)).TrimEnd([char]0)
            return @{available=$true;format='RSDS';guid=$guid.ToString();age=$age;embedded_pdb_path=$embedded}
        }
        return @{available=$false;reason='no_RSDS_record'}
    } catch { return @{available=$false;reason=$_.Exception.Message} }
    finally { if ($null -ne $stream) {$stream.Dispose()} }
}

$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$principal=[Security.Principal.WindowsPrincipal]::new($identity)
$elevated=$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$privilegeText=(& (Join-Path $env:WINDIR 'System32/whoami.exe') /priv 2>&1 | Out-String).Trim()
$toolsFound=[ordered]@{}
foreach ($toolName in @('wpr.exe','wpa.exe','xperf.exe','tracerpt.exe','dotnet.exe','dotnet-trace','dotnet-gcdump','PerfView.exe')) {
    $command=Get-Command $toolName -ErrorAction SilentlyContinue | Select-Object -First 1
    $toolsFound[$toolName]=if ($null -ne $command) {$command.Source} else {$null}
}
$wprStatus=$null
$wprExit=$null
if ($null -ne $toolsFound['wpr.exe']) {
    $wprStatus=(& $toolsFound['wpr.exe'] -status 2>&1 | Out-String).Trim()
    $wprExit=$LASTEXITCODE
}
$profileInfo=@{identity=File-Identity $ProfilePath;parsed=$false}
try {
    $profile=[xml](Get-Content -LiteralPath $ProfilePath -Raw)
    $profileInfo.parsed=$true
    $profileInfo['logging_mode']=$profile.WindowsPerformanceRecorder.Profiles.Profile.LoggingMode
    $profileInfo['buffer_kib']=[int]$profile.WindowsPerformanceRecorder.Profiles.SystemCollector.BufferSize.Value
    $profileInfo['buffers']=[int]$profile.WindowsPerformanceRecorder.Profiles.SystemCollector.Buffers.Value
    $profileInfo['keywords']=@($profile.WindowsPerformanceRecorder.Profiles.SystemProvider.Keywords.Keyword.Value)
    $profileInfo['stacks']=@($profile.WindowsPerformanceRecorder.Profiles.SystemProvider.Stacks.Stack.Value)
} catch { $profileInfo['error']=$_.Exception.Message }
$nativePdbs=@()
$engineFolder=Split-Path -Parent $EnginePath
if (Test-Path -LiteralPath $engineFolder -PathType Container) {
    $nativePdbs=@(Get-ChildItem -LiteralPath $engineFolder -Filter '*.pdb' -Recurse -File | ForEach-Object {File-Identity $_.FullName})
}
# Este pacote local QPC/UTC não tem relógio do Godot. O jogo precisa emitir um pacote
# correspondente entre colchetes de ticks do Godot + QPC + UTC na thread principal nativa.
$qpcBefore=[Diagnostics.Stopwatch]::GetTimestamp()
$utc=[DateTime]::UtcNow
$qpcAfter=[Diagnostics.Stopwatch]::GetTimestamp()
$report=[ordered]@{
    schema_version=1;captured_utc=$utc.ToString('o');capture_started=$false
    scope='Read-only capability/token/profile checks; no game run or native/.NET capture'
    token=@{elevated=$elevated;has_SeSystemProfilePrivilege=($privilegeText -match 'SeSystemProfilePrivilege');privileges=$privilegeText}
    tools=$toolsFound;wpr=@{status_exit_code=$wprExit;status=$wprStatus;profile=$profileInfo}
    engine=File-Identity $EnginePath
    native_codeview=Native-CodeView $EnginePath
    engine_directory_pdb_candidates=$nativePdbs
    managed_pdb=File-Identity 'D:/geteco/game/.godot/mono/temp/bin/Debug/Harbor.pdb'
    symbols_compatible_verified=$false
    scheduler_coverage_verified=$false;events_lost_verified=$false;events_lost=$null
    clock=@{qpc_before=$qpcBefore;qpc_after=$qpcAfter;qpc_frequency=[Diagnostics.Stopwatch]::Frequency;utc_filetime=$utc.ToFileTimeUtc();utc=$utc.ToString('o');bracket_usec=1000000.0*($qpcAfter-$qpcBefore)/[Diagnostics.Stopwatch]::Frequency;godot_clock_present=$false}
    limitations=@(
        'ThreadCpuProbe CPU counters cannot separate ready time from waiting; cycles are not milliseconds.'
        'No ETL collected: retained time coverage, kernel stack coverage and event loss remain indeterminate.'
        'Harbor.pdb is managed; it is not compatible native Godot symbols.'
        'EventPipe, if later captured for a demonstrated GC/JIT hypothesis, does not replace native engine/scheduler profiling.'
    )
}
$json=$report | ConvertTo-Json -Depth 10
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $absolute=[IO.Path]::GetFullPath($OutputPath)
    if (Test-Path -LiteralPath $absolute) { throw 'Output already exists; preserve prior evidence and choose an unused path.' }
    $parent=Split-Path -Parent $absolute
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { $null=New-Item -ItemType Directory -Path $parent }
    $json | Set-Content -LiteralPath $absolute -Encoding UTF8
    Write-Output ('Native capture preflight saved: '+$absolute)
} else { Write-Output $json }
