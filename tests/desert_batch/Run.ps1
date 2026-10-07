param([string]$Script,[string]$Label,[switch]$Headless,[string[]]$UserArgs=@('--no-save','--skip-arrival'),[int]$Timeout=360)
$ErrorActionPreference='Stop'
$root='D:/geteco/game'
$engine='D:/Downloads Chrome/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe'
$folder=Join-Path $root ('evidence/desert-batch-'+$Label+'-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $folder | Out-Null
$deadline=[DateTime]::UtcNow.AddMinutes(12)
do {
    $busy=@(Get-CimInstance Win32_Process -Filter "Name LIKE 'Godot%'" | Where-Object { $_.CommandLine -notmatch '(^|\s)--editor(\s|$)' })
    if ($busy.Count -eq 0) { break }
    if ([DateTime]::UtcNow -gt $deadline) { throw 'Outro jogo ainda em execução; nenhum processo alheio foi interrompido.' }
    Start-Sleep -Seconds 2
} while ($true)
$argsList=@('--path','D:/geteco/game','--script',$Script)
if ($Headless) { $argsList=@('--headless')+$argsList }
$argsList+=@('--')+$UserArgs
$proc=Start-Process -FilePath $engine -ArgumentList $argsList -WindowStyle Hidden -RedirectStandardOutput "$folder/out.log" -RedirectStandardError "$folder/err.log" -PassThru
Write-Output "START $($proc.Id) $folder"
$watch=[Diagnostics.Stopwatch]::StartNew()
$snapshots=[Collections.Generic.List[object]]::new()
$overlap=$false
while (-not $proc.HasExited) {
    $all=@(Get-CimInstance Win32_Process -Filter "Name LIKE 'Godot%'" | Select-Object ProcessId,ParentProcessId,CommandLine)
    $other=@($all | Where-Object { $_.ProcessId -ne $proc.Id -and $_.ParentProcessId -ne $proc.Id -and $_.CommandLine -notmatch '(^|\s)--editor(\s|$)' })
    if ($other.Count -gt 0) { $overlap=$true }
    $snapshots.Add(@{utc=[DateTime]::UtcNow.ToString('o');other=$other})
    if ($watch.Elapsed.TotalSeconds -gt $Timeout) {
        foreach ($child in @($all | Where-Object ParentProcessId -eq $proc.Id)) { Stop-Process -Id $child.ProcessId -Force -ErrorAction SilentlyContinue }
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        throw "Tempo esgotado somente no processo desta rodada: $folder"
    }
    Start-Sleep -Seconds 2
    $proc.Refresh()
}
$proc.WaitForExit()
@{exit_code=$proc.ExitCode;overlap=$overlap;script=$Script;seconds=$watch.Elapsed.TotalSeconds;processes=$snapshots} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath "$folder/runner.json"
Get-Content -LiteralPath "$folder/out.log" -Tail 12
Get-Content -LiteralPath "$folder/err.log" -Tail 18
Write-Output "END exit=$($proc.ExitCode) overlap=$overlap $folder"
exit $proc.ExitCode
