param([int]$Seconds = 8)
$m = New-Object System.Threading.Mutex($false, "Global\GETECO_GODOT_TEST_LOCK")
$got = $m.WaitOne(5000)
Write-Output "HOLDER_ACQUIRED=$got"
Start-Sleep -Seconds $Seconds
if ($got) { $m.ReleaseMutex() }
