<#
 preflight.ps1 - Verifica el entorno y genera la evidencia de configuracion (results_B\environment.txt).
 Ejecutar ANTES de cada campania:
   powershell -ExecutionPolicy Bypass -File .\preflight.ps1
#>
$ErrorActionPreference = 'Continue'
$Root = $PSScriptRoot
$outDir = Join-Path $Root 'results_B'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$outFile = Join-Path $outDir 'environment.txt'
$problems = New-Object System.Collections.ArrayList

function Section([string]$t) { Add-Content -Path $outFile -Value ("`r`n===== {0} =====" -f $t) -Encoding UTF8 }
function Put([string]$t) { Add-Content -Path $outFile -Value $t -Encoding UTF8 }
function Problem([string]$t) { [void]$problems.Add($t); Write-Host "  [PROBLEMA] $t" -ForegroundColor Red }
function Ok([string]$t) { Write-Host "  [ok] $t" -ForegroundColor Green }

Set-Content -Path $outFile -Value ("Preflight - {0}" -f (Get-Date -Format 's')) -Encoding UTF8
Write-Host "== Verificando entorno ==" -ForegroundColor Cyan

# --- Ruta del proyecto ---
Section 'Ruta del proyecto'; Put $Root
if ($Root -match ' ') { Problem "La ruta tiene espacios ($Root). Mueve el proyecto a C:\TFG-Concurrencia" } else { Ok 'Ruta sin espacios' }
if ($Root -match 'OneDrive') { Problem "El proyecto esta dentro de OneDrive: la sincronizacion interfiere con la medicion. Mueve el proyecto a C:\TFG-Concurrencia" } else { Ok 'Fuera de OneDrive' }

# --- Herramientas ---
Section 'Versiones'
foreach ($t in @(@('java', '-version'), @('mvn', '-version'), @('k6', 'version'), @('docker', '--version'))) {
    if (Get-Command $t[0] -ErrorAction SilentlyContinue) {
        $v = (& $t[0] $t[1] 2>&1 | Out-String).Trim()
        Put ("{0}: {1}" -f $t[0], $v); Ok ("{0} encontrado" -f $t[0])
    } else { Problem ("No se encontro '{0}' en el PATH" -f $t[0]) }
}
Put ((& docker compose version 2>&1 | Out-String).Trim())

# --- Hardware / SO ---
Section 'Hardware y sistema operativo'
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
Put ("CPU: {0} | nucleos={1} | hilos={2}" -f $cpu.Name, $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors)
$os = Get-CimInstance Win32_OperatingSystem
Put ("SO: {0} {1} build {2}" -f $os.Caption, $os.Version, $os.BuildNumber)
Put ("RAM total GB: {0:N1} | libre GB: {1:N1}" -f ($os.TotalVisibleMemorySize / 1MB), ($os.FreePhysicalMemory / 1MB))
Section 'Plan de energia'
$plan = (& powercfg /getactivescheme 2>&1 | Out-String).Trim(); Put $plan
if ($plan -notmatch '(?i)alto rendimiento|high performance|e9a42b02') { Write-Host "  [aviso] Plan de energia no es 'Alto rendimiento'. Recomendado cambiarlo." -ForegroundColor Yellow }

# --- Procesos que consumen CPU ---
Section 'Procesos con mayor CPU acumulada (top 15)'
Put ((Get-Process | Sort-Object CPU -Descending | Select-Object -First 15 Name, Id, CPU, @{n='WS_MB';e={[int]($_.WorkingSet64/1MB)}} | Format-Table -AutoSize | Out-String))
if (Get-Process -Name OneDrive -ErrorAction SilentlyContinue) { Write-Host "  [aviso] OneDrive esta en ejecucion: pausalo durante la campania." -ForegroundColor Yellow }

# --- Puerto 8080 ---
if (Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue) { Problem 'El puerto 8080 esta ocupado: cierra la aplicacion Java en ejecucion.' } else { Ok 'Puerto 8080 libre' }

# --- JVM huerfanas ---
$orph = @(Get-CimInstance Win32_Process -Filter "Name='java.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like '*concurrencia-*.jar*' })
if ($orph.Count -gt 0) { Problem ('Hay {0} proceso(s) java de la app corriendo. Ejecuta: Get-Process java | Stop-Process -Force' -f $orph.Count) } else { Ok 'Sin JVM huerfanas' }

# --- Jar ---
$jar = Get-ChildItem -Path (Join-Path $Root 'app\target') -Filter 'concurrencia-*.jar' -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike '*original*' } | Select-Object -First 1
if ($jar) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $z = [System.IO.Compression.ZipFile]::OpenRead($jar.FullName)
    $hasNew = (@($z.Entries | Where-Object { $_.FullName -like '*StatsRegistry*.class' }).Count -gt 0); $z.Dispose()
    if (-not $hasNew) { Problem 'El .jar es VIEJO (no tiene StatsRegistry). Recompila: cd app ; mvn clean package -DskipTests' } else { Ok 'El .jar contiene el codigo nuevo' }
    Ok ("Jar encontrado: {0}" -f $jar.Name); Put ("Jar: {0} ({1:N1} MB, {2})" -f $jar.FullName, ($jar.Length / 1MB), $jar.LastWriteTime)
}
else { Problem 'No existe app\target\concurrencia-1.0.0.jar. Ejecuta: cd app ; mvn clean package -DskipTests' }
Section 'application.properties (efectivo)'
Put (Get-Content (Join-Path $Root 'app\src\main\resources\application.properties') -Raw)

# --- PostgreSQL ---
Section 'PostgreSQL'
function Q([string]$sql) { return ((& docker exec tfg_postgres psql -U tfg_user -d tfg_concurrencia -t -A -c $sql 2>&1) | Out-String).Trim() }
$ver = Q 'SELECT version();'
if ($LASTEXITCODE -ne 0 -or -not $ver) { Problem 'No se pudo consultar PostgreSQL. Levanta el contenedor: docker compose up -d' }
else {
    Put $ver
    foreach ($p in 'max_connections', 'default_transaction_isolation', 'shared_buffers', 'synchronous_commit', 'fsync', 'deadlock_timeout', 'log_lock_waits', 'autovacuum', 'checkpoint_timeout', 'max_wal_size') {
        Put ("{0} = {1}" -f $p, (Q "SHOW $p;"))
    }
    $mc = [int](Q 'SHOW max_connections;')
    if ($mc -lt 250) { Problem "max_connections=$mc (< 250). Recrea el contenedor: docker compose up -d --force-recreate" } else { Ok "max_connections=$mc" }
    $iso = Q 'SHOW default_transaction_isolation;'
    if ($iso -ne 'read committed') { Problem "Aislamiento por defecto = '$iso' (se esperaba read committed)" } else { Ok 'Aislamiento read committed' }
    $cnt = Q 'SELECT COUNT(*) FROM inventario_producto;'
    Put ("Filas en inventario_producto: {0}" -f $cnt)
    if ($cnt -ne '10000') { Problem "inventario_producto tiene $cnt filas (se esperaban 10000)" } else { Ok '10000 productos' }
}

# --- Resultado ---
Write-Host ""
if ($problems.Count -eq 0) { Write-Host "PREFLIGHT OK. Evidencia guardada en $outFile" -ForegroundColor Green }
else { Write-Host ("PREFLIGHT CON {0} PROBLEMA(S). Resuelvelos antes de correr la campania." -f $problems.Count) -ForegroundColor Red }
