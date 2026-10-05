# Verified ShaderRD cache copies for isolated capture userdata.
# Caller supplies $base and $folder; no personal saves or source caches are written.
# The empty seed keeps cold captures explicit. Copy/hash costs occur before motor launch.
function Assert-ShaderCacheEvidencePath([string]$Path) {
    $resolved=[IO.Path]::GetFullPath($Path).TrimEnd('\','/')
    $evidenceRoot=[IO.Path]::GetFullPath($base).TrimEnd('\','/')
    if(-not $resolved.StartsWith($evidenceRoot+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Cache seed must be inside this evidence directory.' }
    $cursor=$resolved
    while($cursor.Length -gt $evidenceRoot.Length) {
        if(Test-Path -LiteralPath $cursor) {
            if((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Cache seed reparse points are prohibited.' }
        }
        $cursor=[IO.Path]::GetDirectoryName($cursor)
    }
    return $resolved
}
function Read-VerifiedShaderCacheSeed([string]$Path) {
    $seedRoot=Assert-ShaderCacheEvidencePath $Path
    if(-not (Test-Path -LiteralPath $seedRoot -PathType Container)) { throw 'Cache seed directory does not exist.' }
    $manifestPath=Assert-ShaderCacheEvidencePath ($seedRoot+'-manifest.json')
    $manifestHashPath=Assert-ShaderCacheEvidencePath ($seedRoot+'-manifest.sha256')
    $expectedManifestHash=([string](Get-Content -LiteralPath $manifestHashPath -Raw)).Trim().ToUpperInvariant()
    if($expectedManifestHash -notmatch '^[0-9A-F]{64}$') { throw 'Invalid cache manifest hash sidecar.' }
    $actualManifestHash=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash
    if($actualManifestHash -ne $expectedManifestHash) { throw 'Frozen cache manifest changed.' }
    $manifest=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if($manifest.schema_version -ne 2 -or $manifest.cache_kind -ne 'ShaderRD-vulkan' -or $manifest.target_engine_commit -ne 'ed1daf0bf' -or -not $manifest.valid_seed) { throw 'Incompatible ShaderRD seed manifest.' }
    if([IO.Path]::GetFullPath([string]$manifest.root).TrimEnd('\','/') -ne $seedRoot -or [IO.Path]::GetFullPath([string]$manifest.destination).TrimEnd('\','/') -ne $seedRoot) { throw 'Cache seed manifest root mismatch.' }
    $files=@($manifest.files)
    if($files.Count -lt 1 -or $files.Count -gt 4096 -or $files.Count -ne $manifest.file_count) { throw 'Cache seed file count is invalid.' }
    $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $byteTotal=[long]0
    foreach($entry in $files) {
        $relative=[string]$entry.relative_path
        if($relative -notmatch '^[A-Za-z0-9_]+/[0-9a-f]{64}/[0-9a-f]{40}\.vulkan\.cache$' -or -not $names.Add($relative)) { throw 'Invalid or duplicate ShaderRD cache key.' }
        if([string]$entry.sha256 -notmatch '^[0-9A-Fa-f]{64}$' -or [long]$entry.bytes -lt 12 -or [long]$entry.bytes -gt 67108864) { throw 'Invalid ShaderRD cache size/hash.' }
        $filePath=Assert-ShaderCacheEvidencePath (Join-Path $seedRoot $relative)
        $file=Get-Item -LiteralPath $filePath -Force
        if($file.PSIsContainer -or $file.Length -ne [long]$entry.bytes -or (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash -ne $entry.sha256) { throw 'Frozen ShaderRD cache content changed.' }
        $stream=[IO.File]::OpenRead($filePath)
        try {
            $header=[byte[]]::new(8)
            if($stream.Read($header,0,8) -ne 8 -or [Text.Encoding]::ASCII.GetString($header,0,4) -ne 'GDSC' -or [BitConverter]::ToUInt32($header,4) -ne 4) { throw 'Wrong ShaderRD cache header/version.' }
        } finally { $stream.Dispose() }
        $byteTotal += $file.Length
    }
    $tree=@(Get-ChildItem -LiteralPath $seedRoot -Recurse -Force)
    if(@($tree | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count -ne 0 -or @($tree | Where-Object { -not $_.PSIsContainer }).Count -ne $files.Count) { throw 'Unexpected files or links in frozen cache seed.' }
    if($byteTotal -gt 268435456 -or $byteTotal -ne [long]$manifest.total_bytes) { throw 'Cache seed byte total is invalid.' }
    return @{root=$seedRoot; manifest_path=$manifestPath; manifest_sha256=$actualManifestHash; files=$files; file_count=$files.Count; total_bytes=$byteTotal; source_root=$manifest.source}
}
function Prepare-IsolatedShaderCache([string]$Seed,[string]$Destination) {
    $destinationPath=Assert-ShaderCacheEvidencePath $Destination
    $expectedDestination=[IO.Path]::GetFullPath((Join-Path $folder 'user/GetecoV2/shader_cache')).TrimEnd('\','/')
    if($destinationPath -ne $expectedDestination -or (Test-Path -LiteralPath $destinationPath)) { throw 'Shader cache destination must be the new, absent per-run cache directory.' }
    $costProcess=[Diagnostics.Process]::GetCurrentProcess()
    $cpuBefore=$costProcess.TotalProcessorTime.TotalMilliseconds
    $costWatch=[Diagnostics.Stopwatch]::StartNew()
    $result=@{mode='cold_fresh_user'; destination=$destinationPath; destination_absent_before=$true; seed_root=$null; manifest_sha256=$null; keys=@(); file_count=0; total_bytes=0; copied=$false}
    if($Seed) {
        $verified=Read-VerifiedShaderCacheSeed $Seed
        # Windows PowerShell 5.1 Copy-Item uses legacy path limits. Fail before
        # any copy rather than leave a partly seeded capture directory.
        foreach($entry in $verified.files) {
            if((Join-Path $destinationPath $entry.relative_path).Length -ge 260) { throw 'Shader cache destination exceeds the PowerShell 5.1 path limit. Use a shorter capture label.' }
        }
        New-Item -ItemType Directory -Path $destinationPath | Out-Null
        foreach($entry in $verified.files) {
            $target=Join-Path $destinationPath $entry.relative_path
            New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($target)) -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $verified.root $entry.relative_path) -Destination $target
            if((Get-Item -LiteralPath $target).Length -ne [long]$entry.bytes -or (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $entry.sha256) { throw 'Seed copy verification failed before engine launch.' }
        }
        $again=Read-VerifiedShaderCacheSeed $Seed
        if($again.manifest_sha256 -ne $verified.manifest_sha256) { throw 'Shader cache seed changed during preparation.' }
        $result.mode='seeded_shader_rd'
        $result.seed_root=$verified.root
        $result.source_root=$verified.source_root
        $result.manifest_sha256=$verified.manifest_sha256
        $result.keys=$verified.files
        $result.file_count=$verified.file_count
        $result.total_bytes=$verified.total_bytes
        $result.copied=$true
    }
    $costWatch.Stop()
    $costProcess.Refresh()
    $result.preparation_wall_ms=$costWatch.Elapsed.TotalMilliseconds
    $result.preparation_cpu_ms=$costProcess.TotalProcessorTime.TotalMilliseconds-$cpuBefore
    $result.prepared_utc=[DateTime]::UtcNow.ToString('o')
    return $result
}
