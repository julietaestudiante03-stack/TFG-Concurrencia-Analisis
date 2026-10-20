$outputCsv = "dataset_experimental.csv"

$strategies = @("occ", "pcc")
$vusLevels = @(100, 500, 1000)
$repetitions = 10

$csvData = @()

Write-Host "=== EXTRACCION DE DATOS ===" -ForegroundColor Cyan

foreach ($strategy in $strategies) {
    foreach ($vus in $vusLevels) {
        for ($i = 1; $i -le $repetitions; $i++) {

            $jsonFile = "results\$strategy\$vus\summary_run_$i.json"

            if (!(Test-Path $jsonFile)) {
                Write-Host "FALTA: $jsonFile" -ForegroundColor Red
                continue
            }

            $json = Get-Content $jsonFile -Raw | ConvertFrom-Json

            $obj = [PSCustomObject]@{
                Run_ID = "${strategy}_${vus}_${i}"
                Strategy = $strategy.ToUpper()
                VUs = $vus
                Repetition = $i

                Throughput_req_sec = [math]::Round(
                    $json.metrics.http_reqs.rate, 2
                )

                Latency_avg_ms = [math]::Round(
                    $json.metrics.http_req_duration.avg, 2
                )

                Latency_med_ms = [math]::Round(
                    $json.metrics.http_req_duration.med, 2
                )

                Latency_p95_ms = [math]::Round(
                    $json.metrics.http_req_duration.'p(95)', 2
                )

                Total_Success = if ($null -ne $json.metrics.app_success) {
                    $json.metrics.app_success.count
                } else { 0 }

                Total_Conflicts = if ($null -ne $json.metrics.app_conflict) {
                    $json.metrics.app_conflict.count
                } else { 0 }

                Total_Out_Of_Stock = if ($null -ne $json.metrics.app_out_of_stock) {
                    $json.metrics.app_out_of_stock.count
                } else { 0 }

                Total_Errors = if ($null -ne $json.metrics.app_error) {
                    $json.metrics.app_error.count
                } else { 0 }

                Total_Requests = $json.metrics.http_reqs.count
            }

            $csvData += $obj
        }
    }
}

$csvData |
    Export-Csv -Path $outputCsv -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "Dataset generado: $outputCsv" -ForegroundColor Green
Write-Host "Registros: $($csvData.Count)" -ForegroundColor Green