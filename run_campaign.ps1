<#
 run_campaign.ps1  -  Campania B del TFG (OCC vs PCC)

 Uso (desde PowerShell, dentro de la carpeta del proyecto):
   powershell -ExecutionPolicy Bypass -File .\run_campaign.ps1 -Campaign SMOKE
   powershell -ExecutionPolicy Bypass -File .\run_campaign.ps1 -Campaign B2
   powershell -ExecutionPolicy Bypass -File .\run_campaign.ps1 -Campaign B1
   powershell -ExecutionPolicy Bypass -File .\run_campaign.ps1 -Campaign B3

 Si se interrumpe, volver a ejecutar el MISMO comando: retoma desde la primera corrida faltante.

 Campanias:
   SMOKE : 5 corridas cortas para validar todo el circuito (~12 min)
   B1    : diseno principal 2x3 (occ/pcc x 100/500/1000 VUs), 10 repeticiones   (60 corridas, ~2 h 15 min)
   B2    : consistencia bajo alta contencion y stock escaso (stock 800) (occ, occretry, pcc, none), 500 VUs, 10 rep (40 corridas, ~1 h 20 min)
   B3    : modelo abierto (llegadas constantes 2000 y 4000 req/s) occ/pcc, 6 repeticiones (24 corridas, ~55 min)

 Cada corrida: reinicia la app -> calentamiento (no medido) -> reset de BD + VACUUM -> medicion con k6
 -> auditoria por producto -> guarda evidencia en results_B\<campania>\raw\<run_id>\
 El orden de las corridas es ALEATORIO por bloques (cada repeticion es un bloque con todas las celdas).
#>
param(
    [ValidateSet('SMOKE', 'B1', 'B2', 'B3')][string]$Campaign = 'SMOKE',
    [int]$Reps = 0,
    [int]$Seed = 20261016,
    [string]$BaseUrl = 'http://localhost:8080'
)

$ErrorActionPreference = 'Continue'
$Root = $PSScriptRoot
$inv = [System.Globalization.CultureInfo]::InvariantCulture

function F($v) {
    if ($null -eq $v) { return '' }
    if ($v -is [double] -or $v -is [single] -or $v -is [decimal]) { return [string]::Format($inv, '{0:0.######}', $v) }
    return [string]$v
}
function NowMs { return [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() }

# ----------------------------- Definicion de la campania -----------------------------
$cells = New-Object System.Collections.ArrayList
switch ($Campaign) {
    'SMOKE' {
        $defReps = 1; $ramp = 5; $hold = 15; $down = 3
        foreach ($s in 'occ', 'occretry', 'pcc', 'none') {
            [void]$cells.Add(@{ strategy = $s; vus = 100; rate = 0; stock = 1500; hot = 100; hotRatio = 0.8 })
        }
        [void]$cells.Add(@{ strategy = 'occ'; vus = 0; rate = 1000; stock = 1000; hot = 2000; hotRatio = 0.8 })
    }
    'B1' {
        $defReps = 10; $ramp = 10; $hold = 60; $down = 5
        foreach ($s in 'occ', 'pcc') { foreach ($v in 100, 500, 1000) {
            [void]$cells.Add(@{ strategy = $s; vus = $v; rate = 0; stock = 1000; hot = 2000; hotRatio = 0.8 })
        } }
    }
    'B2' {
        $defReps = 10; $ramp = 10; $hold = 45; $down = 5
        foreach ($s in 'occ', 'occretry', 'pcc', 'none') {
            [void]$cells.Add(@{ strategy = $s; vus = 500; rate = 0; stock = 800; hot = 100; hotRatio = 0.8 })
        }
    }
    'B3' {
        $defReps = 6; $ramp = 10; $hold = 60; $down = 5
        foreach ($s in 'occ', 'pcc') { foreach ($r in 2000, 4000) {
            [void]$cells.Add(@{ strategy = $s; vus = 0; rate = $r; stock = 1000; hot = 2000; hotRatio = 0.8 })
        } }
    }
}
if ($Reps -le 0) { $Reps = $defReps }

# ----------------------------- Carpetas de salida -----------------------------
$OutRoot = Join-Path $Root "results_B\$Campaign"
$raw = Join-Path $OutRoot 'raw'
New-Item -ItemType Directory -Force -Path $raw | Out-Null
$runsCsv = Join-Path $OutRoot 'runs.csv'
$planCsv = Join-Path $OutRoot 'plan.csv'
$errLog = Join-Path $OutRoot 'errores.txt'
Start-Transcript -Path (Join-Path $OutRoot ("transcript_{0}.txt" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))) -Append | Out-Null

# ----------------------------- Funciones auxiliares -----------------------------
function Invoke-Psql([string]$sql) {
    $out = & docker exec tfg_postgres psql -U tfg_user -d tfg_concurrencia -v ON_ERROR_STOP=1 -t -A -c $sql
    if ($LASTEXITCODE -ne 0) { throw "psql fallo (codigo $LASTEXITCODE) con: $sql" }
    return (($out | Out-String).Trim())
}

function Get-PgStats {
    $o = Invoke-Psql "SELECT deadlocks || ',' || xact_commit || ',' || xact_rollback FROM pg_stat_database WHERE datname='tfg_concurrencia';"
    $line = ($o -split "`n" | Where-Object { $_ -match '^\d+,\d+,\d+$' } | Select-Object -Last 1)
    if (-not $line) { throw "No se pudo leer pg_stat_database: $o" }
    $p = $line.Trim().Split(',')
    return @{ deadlocks = [int64]$p[0]; commits = [int64]$p[1]; rollbacks = [int64]$p[2] }
}

function Stop-ProcessSafe($p) {
    if ($null -ne $p) {
        try { if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } } catch {}
    }
}

function Resolve-JavaExe {
    # En Windows, el 'java' del PATH suele ser un lanzador (javapath) que crea un proceso HIJO:
    # al matar el lanzador la JVM real sigue viva y ocupa el puerto 8080. Por eso se usa el java.exe real del JDK.
    $props = (& java -XshowSettings:properties -version 2>&1 | Out-String)
    if ($props -match 'java\.home\s*=\s*([^\r\n]+)') {
        $exe = Join-Path $matches[1].Trim() 'bin\java.exe'
        if (Test-Path $exe) { return $exe }
    }
    return (Get-Command java).Source
}

function Stop-AppTree($p) {
    if ($null -ne $p) { try { & taskkill /PID $p.Id /T /F 2>&1 | Out-Null } catch {} }
    # barrido de seguridad: cualquier JVM que este ejecutando NUESTRO jar
    Get-CimInstance Win32_Process -Filter "Name='java.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*concurrencia-*.jar*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    $t = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $t) {
        if (-not (Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue)) { return }
        Start-Sleep -Milliseconds 500
    }
}

function Test-JarNewCode([string]$jarPath) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $z = [System.IO.Compression.ZipFile]::OpenRead($jarPath)
    try { return (@($z.Entries | Where-Object { $_.FullName -like '*StatsRegistry*.class' }).Count -gt 0) }
    finally { $z.Dispose() }
}

function Show-LogTail([string]$base) {
    foreach ($ext in 'err', 'out') {
        $f = "$base.$ext.log"
        if (Test-Path $f) {
            $tail = (Get-Content $f -Tail 25 | Out-String)
            Write-Host "--- ultimas lineas de $f ---" -ForegroundColor Yellow
            Write-Host $tail
            Add-Content -Path $errLog -Value "--- $f ---`r`n$tail"
        }
    }
}

function Get-AppJar {
    $jar = Get-ChildItem -Path (Join-Path $Root 'app\target') -Filter 'concurrencia-*.jar' -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -notlike '*original*' } | Select-Object -First 1
    if (-not $jar) { throw "No se encontro el .jar en app\target. Ejecuta: cd app ; mvn clean package -DskipTests" }
    if (-not (Test-JarNewCode $jar.FullName)) {
        throw "El .jar de app\target es VIEJO (no contiene StatsRegistry). Recompila: cd app ; mvn clean package -DskipTests"
    }
    return $jar
}

function Start-App([string]$logBase) {
    $jar = Get-AppJar
    $javaExe = Resolve-JavaExe
    $argList = @('-Xms1g', '-Xmx1g', '-jar', ('"{0}"' -f $jar.FullName))
    $p = Start-Process -FilePath $javaExe -ArgumentList $argList -PassThru -WindowStyle Hidden `
         -RedirectStandardOutput "$logBase.out.log" -RedirectStandardError "$logBase.err.log"
    $deadline = (Get-Date).AddSeconds(120)
    $notFound = 0
    while ((Get-Date) -lt $deadline) {
        if ($p.HasExited) {
            Show-LogTail $logBase
            throw "La aplicacion termino al iniciar (codigo $($p.ExitCode)). Revisa $logBase.err.log"
        }
        try {
            $r = Invoke-WebRequest -Uri "$BaseUrl/inventory/stats" -UseBasicParsing -TimeoutSec 2
            if ($r.StatusCode -eq 200) { return $p }
        } catch {
            $code = 0
            if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
            if ($code -eq 404) { $notFound++ }
            if ($notFound -ge 6) {
                Stop-AppTree $p
                throw "El servidor responde 404 en /inventory/stats: lo que escucha en el puerto 8080 NO es la aplicacion nueva. Recompila (cd app ; mvn clean package -DskipTests) y cerra cualquier otra app en el puerto 8080."
            }
        }
        Start-Sleep -Milliseconds 500
    }
    Show-LogTail $logBase
    Stop-AppTree $p
    throw "La aplicacion no respondio en 120 s. Revisa $logBase.err.log"
}

$script:K6Exit = 0
function Invoke-K6($cell, [string]$jsonFile, [string]$consoleLog, [bool]$warm) {
    $a = @('run', '--quiet')
    if ($jsonFile) { $a += "--summary-export=$jsonFile" }
    $a += @('-e', "STRATEGY=$($cell.strategy)", '-e', "BASE_URL=$BaseUrl", '-e', 'TOTAL_PRODUCTS=10000',
            '-e', "HOT_PRODUCTS=$($cell.hot)", '-e', ("HOT_RATIO=" + (F ([double]$cell.hotRatio))))
    if ($warm) {
        $a += @('-e', 'VUS=50', '-e', 'RATE=0', '-e', 'RAMP=3s', '-e', 'HOLD=12s', '-e', 'DOWN=2s')
    } else {
        $a += @('-e', "VUS=$($cell.vus)", '-e', "RATE=$($cell.rate)", '-e', "RAMP=${ramp}s", '-e', "HOLD=${hold}s", '-e', "DOWN=${down}s")
    }
    $a += (Join-Path $Root 'load-tests\inventory.js')
    if ($warm) { & k6 @a | Out-Null } else { & k6 @a | Tee-Object -FilePath $consoleLog | Out-Host }
    $script:K6Exit = $LASTEXITCODE
}

function MCount($m, [string]$name) {
    if ($m.PSObject.Properties.Name -contains $name) { return [double]$m.$name.count }
    return 0.0
}

# ----------------------------- Verificaciones previas -----------------------------
foreach ($c in 'java', 'k6', 'docker') {
    if (-not (Get-Command $c -ErrorAction SilentlyContinue)) { throw "No se encontro '$c' en el PATH." }
}
if ($Root -match ' ' -or $Root -match 'OneDrive') {
    Write-Warning "El proyecto esta en una ruta con espacios u OneDrive ($Root). Se recomienda C:\TFG-Concurrencia para evitar errores y sincronizaciones durante la medicion."
}
Stop-AppTree $null   # elimina JVM huerfanas de corridas anteriores (solo las que ejecutan nuestro jar)
if (Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue) {
    throw "El puerto 8080 esta ocupado. Cierra la aplicacion Java que este corriendo (la campania la inicia sola en cada corrida)."
}
[void](Get-AppJar)   # falla ahora (y no en cada corrida) si el .jar falta o es viejo
$maxc = Invoke-Psql 'SHOW max_connections;'
if ([int]$maxc -lt 250) { throw "PostgreSQL tiene max_connections=$maxc. Recrea el contenedor con el docker-compose.yml nuevo: docker compose up -d --force-recreate" }

# ----------------------------- Plan aleatorizado por bloques -----------------------------
$plan = New-Object System.Collections.ArrayList
for ($rep = 1; $rep -le $Reps; $rep++) {
    $rng = New-Object System.Random -ArgumentList ($Seed + $rep)
    $idx = @(0..($cells.Count - 1))
    for ($i = $idx.Count - 1; $i -gt 0; $i--) {
        $j = $rng.Next($i + 1); $t = $idx[$i]; $idx[$i] = $idx[$j]; $idx[$j] = $t
    }
    foreach ($i in $idx) { [void]$plan.Add(@{ cell = $cells[$i]; rep = $rep }) }
}

$done = @{}
if (Test-Path $runsCsv) { Import-Csv $runsCsv | ForEach-Object { $done[$_.run_id] = $true } }

$planRows = @()
$n = 0
foreach ($it in $plan) {
    $n++
    $c = $it.cell
    $label = if ($c.rate -gt 0) { "r$($c.rate)" } else { "v$($c.vus)" }
    $planRows += [pscustomobject]@{ order = $n; run_id = ("{0}_{1}_{2}_{3}" -f $Campaign, $c.strategy, $label, $it.rep); rep = $it.rep; strategy = $c.strategy; load = $label }
}
$planRows | Export-Csv -Path $planCsv -NoTypeInformation -Encoding UTF8

$total = $plan.Count
$pending = $total - $done.Count
Write-Host ""
Write-Host "=== CAMPANIA $Campaign : $total corridas ($pending pendientes). Tiempo estimado: ~$([math]::Round($pending * ((($ramp + $hold + $down) + 60) / 60.0), 0)) min ===" -ForegroundColor Green
Write-Host "No uses la PC mientras corre. Resultados en: $OutRoot" -ForegroundColor Yellow
$script:Failed = 0

# ----------------------------- Una corrida -----------------------------
function Invoke-Run($item, [int]$order) {
    $cell = $item.cell; $rep = $item.rep; $s = $cell.strategy
    $label = if ($cell.rate -gt 0) { "r$($cell.rate)" } else { "v$($cell.vus)" }
    $runId = "{0}_{1}_{2}_{3}" -f $Campaign, $s, $label, $rep
    if ($done.ContainsKey($runId)) { Write-Host "[$order/$total] $runId ya registrada, se omite."; return }

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "[$order/$total] $runId   (estrategia=$s, carga=$label, stock=$($cell.stock), conjunto caliente=$($cell.hot))" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan

    $dir = Join-Path $raw $runId
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $app = $null; $mon = $null
    try {
        Write-Host "-> Iniciando aplicacion (JVM nueva, -Xms1g -Xmx1g)..."
        $app = Start-App (Join-Path $dir 'app')

        Write-Host "-> Calentamiento (no medido)..."
        Invoke-K6 $cell $null $null $true

        Write-Host "-> Restaurando BD (stock=$($cell.stock), version=0), VACUUM y CHECKPOINT..."
        Invoke-Psql "UPDATE inventario_producto SET stock = $($cell.stock), version = 0;" | Out-Null
        Invoke-Psql 'VACUUM (ANALYZE) inventario_producto;' | Out-Null
        Invoke-Psql 'CHECKPOINT;' | Out-Null
        Invoke-RestMethod -Method Post -Uri "$BaseUrl/inventory/stats/reset" | Out-Null
        Start-Sleep -Seconds 3
        $pg0 = Get-PgStats

        $monFile = Join-Path $dir 'resources.csv'
        $monScript = Join-Path $Root 'monitoring\monitor_resources.ps1'
        $mon = Start-Process -FilePath 'powershell' -PassThru -WindowStyle Hidden -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $monScript),
            '-OutputFile', ('"{0}"' -f $monFile), '-AppPid', $app.Id)
        Start-Sleep -Seconds 4

        Write-Host "-> Midiendo con k6..." -ForegroundColor Yellow
        $jsonFile = Join-Path $dir 'summary.json'
        $tStart = NowMs
        Invoke-K6 $cell $jsonFile (Join-Path $dir 'k6_console.txt') $false
        $tEnd = NowMs
        $k6Exit = $script:K6Exit

        Start-Sleep -Seconds 4
        Stop-ProcessSafe $mon; $mon = $null
        $pg1 = Get-PgStats

        Write-Host "-> Auditando estado final del inventario..."
        $audit = Invoke-RestMethod -Uri "$BaseUrl/inventory/audit?initialStock=$($cell.stock)" -TimeoutSec 120
        $st = Invoke-RestMethod -Uri "$BaseUrl/inventory/stats"
        $audit | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $dir 'audit.json') -Encoding UTF8
        $st | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $dir 'app_stats.json') -Encoding UTF8

        $j = Get-Content $jsonFile -Raw | ConvertFrom-Json
        $m = $j.metrics
        $kSucc = MCount $m 'app_success'; $kConf = MCount $m 'app_conflict'
        $kOos = MCount $m 'app_out_of_stock'; $kErr = MCount $m 'app_error'
        $reqs = [double]$m.http_reqs.count
        $unacc = $reqs - $kSucc - $kConf - $kOos - $kErr
        $failRate = if ($m.PSObject.Properties.Name -contains 'http_req_failed') { [double]$m.http_req_failed.value } else { 0.0 }

        $row = [ordered]@{
            run_id = $runId; campaign = $Campaign; run_order = $order; rep = $rep; strategy = $s; load_label = $label
            vus = $cell.vus; rate = $cell.rate; stock = $cell.stock; hot_products = $cell.hot; hot_ratio = [double]$cell.hotRatio
            ramp_s = $ramp; hold_s = $hold; down_s = $down
            k6_start_epoch_ms = $tStart; k6_end_epoch_ms = $tEnd; k6_exit = $k6Exit
            requests = $reqs; throughput_rps = [double]$m.http_reqs.rate
            lat_avg_ms = [double]$m.http_req_duration.avg; lat_med_ms = [double]$m.http_req_duration.med
            lat_p90_ms = [double]$m.http_req_duration.'p(90)'; lat_p95_ms = [double]$m.http_req_duration.'p(95)'
            lat_max_ms = [double]$m.http_req_duration.max
            k6_success = $kSucc; k6_conflict = $kConf; k6_oos = $kOos; k6_error = $kErr
            k6_dropped_iter = (MCount $m 'dropped_iterations'); http_failed_rate = $failRate; k6_unaccounted = $unacc
            app_success = $st.success_total; app_conflict_attempts = $st.conflicts_internal_attempts
            app_retries = $st.retries; app_conflicts_returned = $st.conflicts_returned
            app_oos = $st.out_of_stock; app_errors = $st.errors
            app_errors_by_type = ($st.errors_by_type | ConvertTo-Json -Compress)
            audit_total_success = $audit.total_success_app; audit_total_sold_db = $audit.total_sold_db
            audit_sum_version = $audit.sum_version; audit_lost_units = $audit.lost_update_units
            audit_products_lost = $audit.products_with_lost_updates; audit_oversold_units = $audit.oversold_units
            audit_products_oversold = $audit.products_oversold; audit_products_negative = $audit.products_negative_stock
            audit_min_stock = $audit.min_stock; audit_consistent = ([string]$audit.consistent).ToLower()
            k6_vs_app_success_diff = ($kSucc - [double]$st.success_total)
            pg_deadlocks_delta = ($pg1.deadlocks - $pg0.deadlocks); pg_rollbacks_delta = ($pg1.rollbacks - $pg0.rollbacks)
            pg_commits_delta = ($pg1.commits - $pg0.commits)
            run_valid = (($k6Exit -eq 0) -and ([math]::Abs($unacc) -lt 1)).ToString().ToLower()
        }
        $out = [ordered]@{}
        foreach ($k in $row.Keys) { $out[$k] = F $row[$k] }
        [pscustomobject]$out | Export-Csv -Path $runsCsv -Append -NoTypeInformation -Encoding UTF8
        $done[$runId] = $true

        Write-Host ("OK  req={0}  thr={1} req/s  lat_media={2} ms  409={3}  400={4}  errores={5}  auditoria_consistente={6}" -f `
            (F $reqs), (F ([math]::Round([double]$m.http_reqs.rate, 1))), (F ([math]::Round([double]$m.http_req_duration.avg, 2))), `
            (F $kConf), (F $kOos), (F $kErr), $audit.consistent) -ForegroundColor Green
    }
    catch {
        $script:Failed++
        $msg = "[{0}] {1} FALLO: {2}" -f (Get-Date -Format 's'), $runId, $_
        Write-Host $msg -ForegroundColor Red
        Add-Content -Path $errLog -Value $msg
    }
    finally {
        Stop-ProcessSafe $mon
        Stop-AppTree $app
        Start-Sleep -Seconds 12   # enfriamiento
    }
}

try {
    $order = 0
    foreach ($it in $plan) { $order++; Invoke-Run $it $order }
}
finally {
    Write-Host ""
    Write-Host "=== FIN. Corridas registradas: $($done.Count) / $total ; fallidas en esta sesion: $($script:Failed) ===" -ForegroundColor Green
    if ($script:Failed -gt 0) { Write-Host "Revisa $errLog y vuelve a ejecutar el mismo comando para reintentar las faltantes." -ForegroundColor Yellow }
    Write-Host "Datos: $runsCsv"
    Stop-Transcript | Out-Null
}
