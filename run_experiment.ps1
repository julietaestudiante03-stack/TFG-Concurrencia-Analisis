$strategies = @("occ", "pcc")
$vusLevels = @(100, 500, 1000)
$repetitions = 5

Write-Host "=== INICIANDO EXPERIMENTO TFG ===" -ForegroundColor Green

foreach ($strategy in $strategies) {

    foreach ($vus in $vusLevels) {

        $outputDir = "results\$strategy\$vus"

        if (!(Test-Path -Path $outputDir)) {
            New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
        }

        for ($i = 1; $i -le $repetitions; $i++) {

            Write-Host ""
            Write-Host "==================================================" -ForegroundColor Cyan
            Write-Host "ESTRATEGIA : $strategy"
            Write-Host "VUs        : $vus"
            Write-Host "REPETICION : $i / $repetitions"
            Write-Host "==================================================" -ForegroundColor Cyan

            # -------------------------------------------------
            # 1. Restaurar base de datos
            # -------------------------------------------------

            Write-Host "-> Restaurando base de datos..."

            Get-Content .\scripts\reset_database.sql |
                docker exec -i tfg_postgres psql -U tfg_user -d tfg_concurrencia

            if ($LASTEXITCODE -ne 0) {
                Write-Host "ERROR: No se pudo restaurar la base de datos." -ForegroundColor Red
                Write-Host "El experimento se detendra para evitar datos invalidos." -ForegroundColor Red
                exit 1
            }

Write-Host "-> Base de datos restaurada correctamente." -ForegroundColor Green

            # -------------------------------------------------
            # 2. Archivos de salida
            # -------------------------------------------------

            $jsonFile = "$outputDir\summary_run_$i.json"
            $monitorFile = "$outputDir\resources_run_$i.csv"

            # -------------------------------------------------
            # 3. Iniciar monitoreo
            # -------------------------------------------------

            Write-Host "-> Iniciando monitoreo de recursos..."

            $monitorProcess = Start-Process powershell `
                -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File .\monitoring\monitor_resources.ps1 -OutputFile `"$monitorFile`"" `
                -PassThru `
                -WindowStyle Minimized

            Start-Sleep -Seconds 3

            # -------------------------------------------------
            # 4. Ejecutar k6
            # -------------------------------------------------

            Write-Host "-> Ejecutando k6..." -ForegroundColor Yellow

            k6 run `
                -e STRATEGY=$strategy `
                -e VUS=$vus `
                --summary-export=$jsonFile `
                load-tests/inventory.js

            $k6ExitCode = $LASTEXITCODE

            # -------------------------------------------------
            # 5. Detener monitoreo
            # -------------------------------------------------

            Write-Host "-> Deteniendo monitoreo..."

            Write-Host "-> Esperando liberacion de conexiones..."
            Start-Sleep -Seconds 15

            Stop-Process -Id $monitorProcess.Id -Force -ErrorAction SilentlyContinue

            # -------------------------------------------------
            # 6. Verificar resultados
            # -------------------------------------------------

            if ($k6ExitCode -ne 0) {

                Write-Host "ERROR: k6 finalizó con código $k6ExitCode" -ForegroundColor Red

            } else {

                Write-Host "-> Corrida finalizada correctamente." -ForegroundColor Green
                Write-Host "   k6      : $jsonFile"
                Write-Host "   recursos: $monitorFile"
            }

            # -------------------------------------------------
            # 7. Enfriamiento
            # -------------------------------------------------

            Write-Host "-> Esperando 10 segundos..."

            Start-Sleep -Seconds 10
        }
    }
}

Write-Host ""
Write-Host "==================================================" -ForegroundColor Green
Write-Host "=== EXPERIMENTO FINALIZADO ==="
Write-Host "==================================================" -ForegroundColor Green