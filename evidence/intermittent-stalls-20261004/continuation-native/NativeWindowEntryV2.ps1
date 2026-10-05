param(
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9-]+$')][string]$Label,
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9_.-]+\.ps1$')][string]$HelperName,
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedSha256,
    [ValidateSet('NativeCreated','Ready')][string]$StartMode='NativeCreated',
    [ValidateRange(30,55)][int]$CaptureSeconds=55,
    [ValidateRange(0,90)][int]$StartDelaySeconds=0
)
$ErrorActionPreference='Stop'
$taskDirectory='D:/geteco/game/evidence/intermittent-stalls-20261004/continuation-native'
$taskEntry=Join-Path $taskDirectory ($Label+'-entry.json')
$taskError=Join-Path $taskDirectory ($Label+'-entry-error.json')
$taskBoot=Join-Path $taskDirectory ($Label+'-boot.json')
$taskHelper=Join-Path $taskDirectory $HelperName
try {
    if((Test-Path -LiteralPath $taskEntry) -or (Test-Path -LiteralPath $taskBoot) -or (Test-Path -LiteralPath $taskError)) { throw 'Entry evidence already exists.' }
    $taskActualHash=(Get-FileHash -LiteralPath $taskHelper -Algorithm SHA256).Hash
    if($taskActualHash -ne $ExpectedSha256) { throw 'Helper differs from the reviewed hash.' }
    $taskPrincipal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    [ordered]@{pid=$PID; utc=[DateTime]::UtcNow.ToString('o'); label=$Label;
        elevated=$taskPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator);
        powershell_version=$PSVersionTable.PSVersion.ToString(); helper=$taskHelper; helper_sha256=$taskActualHash;
        start_mode=$StartMode; capture_seconds=$CaptureSeconds; start_delay_seconds=$StartDelaySeconds
    } | ConvertTo-Json | Set-Content -LiteralPath $taskEntry -Encoding UTF8
    & $taskHelper -Label $Label -StartMode $StartMode -CaptureSeconds $CaptureSeconds -StartDelaySeconds $StartDelaySeconds -BootStatusPath $taskBoot
} catch {
    [ordered]@{pid=$PID; utc=[DateTime]::UtcNow.ToString('o'); label=$Label; failure=$_.Exception.Message;
        error_id=$_.FullyQualifiedErrorId; script_stack=$_.ScriptStackTrace
    } | ConvertTo-Json | Set-Content -LiteralPath $taskError -Encoding UTF8
    throw
}
