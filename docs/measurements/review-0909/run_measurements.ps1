$godot = "D:\Downloads Chrome\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
$project = "D:\geteco\game"
$outDir = "D:\geteco\perf-review-0909"

foreach ($res in @(720, 1080)) {
    for ($sample = 1; $sample -le 3; $sample++) {
        $reportPath = Join-Path $outDir "review0909_res${res}_sample${sample}.txt"
        if (Test-Path $reportPath) {
            Write-Output "SKIP res=$res sample=$sample (already have $reportPath)"
            continue
        }
        $logPath = Join-Path $outDir "run_res${res}_sample${sample}.log"
        Write-Output "RUNNING res=$res sample=$sample -> $logPath"
        $before = Get-Process | Where-Object { $_.ProcessName -like "*Godot*" } | ForEach-Object { "$($_.Id)|$($_.MainWindowTitle)" }
        "CONCURRENT_GODOT_BEFORE_RUN: $($before -join '; ')" | Out-File -FilePath $logPath -Encoding utf8
        $stdout = & $godot --path $project --script res://tests/measure_review_0909.gd -- res=$res sample=$sample out_dir=D:/geteco/perf-review-0909 2>$null
        $stdout | Out-File -FilePath $logPath -Append -Encoding utf8
        Write-Output "DONE res=$res sample=$sample (exit=$LASTEXITCODE)"
        Start-Sleep -Seconds 5
    }
}
Write-Output "ALL_SAMPLES_COMPLETE"
