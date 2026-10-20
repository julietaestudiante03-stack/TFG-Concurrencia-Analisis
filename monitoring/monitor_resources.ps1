<#
 Monitor de recursos - Campania B
 - CSV con punto decimal (cultura invariante) y coma como separador.
 - Mide el PROCESO de la aplicacion (por PID), k6 y el contenedor de PostgreSQL por separado.
 - Unidades explicitas en los nombres de columna.
#>
param(
    [Parameter(Mandatory = $true)][string]$OutputFile,
    [int]$AppPid = 0,
    [double]$IntervalSec = 2
)

$inv = [System.Globalization.CultureInfo]::InvariantCulture

function N($v) {
    if ($null -eq $v) { return '' }
    return [string]::Format($inv, '{0:0.##}', [double]$v)
}

function ToMB([string]$txt) {
    # Convierte "87.5MiB", "1.2GiB", "512kB" a MB (base 1024)
    if ($txt -match '([\d\.]+)\s*([KMGT]?i?B)') {
        $x = [double]::Parse($matches[1], $inv)
        switch -Regex ($matches[2]) {
            '^[Kk]i?B$' { return $x / 1024 }
            '^Mi?B$'    { return $x }
            '^Gi?B$'    { return $x * 1024 }
            '^Ti?B$'    { return $x * 1024 * 1024 }
            default     { return $x / 1MB }
        }
    }
    return 0
}

$header = 'timestamp_utc,epoch_ms,host_cpu_pct,host_mem_used_gb,host_mem_pct,app_cpu_pct_1core,app_ws_mb,k6_cpu_pct_1core,k6_ws_mb,pg_cpu_pct_1core,pg_mem_mb'
Set-Content -Path $OutputFile -Value $header -Encoding UTF8

while ($true) {
    $t0 = Get-Date

    # CPU total del equipo (clase independiente del idioma de Windows)
    $cpuObj = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'"
    $hostCpu = $cpuObj.PercentProcessorTime

    # Memoria del equipo (KB -> GB)
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $totalGb = $os.TotalVisibleMemorySize / 1MB
    $freeGb  = $os.FreePhysicalMemory / 1MB
    $usedGb  = $totalGb - $freeGb
    $memPct  = ($usedGb / $totalGb) * 100

    # Proceso de la aplicacion (por PID) y k6
    $appCpu = 0; $appWs = 0
    if ($AppPid -gt 0) {
        $a = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfProc_Process -Filter "IDProcess=$AppPid"
        if ($a) { $appCpu = $a.PercentProcessorTime; $appWs = $a.WorkingSet / 1MB }
    }
    $k6Cpu = 0; $k6Ws = 0
    $k = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfProc_Process -Filter "Name='k6'"
    if ($k) {
        $k6Cpu = ($k | Measure-Object -Property PercentProcessorTime -Sum).Sum
        $k6Ws  = (($k | Measure-Object -Property WorkingSet -Sum).Sum) / 1MB
    }

    # PostgreSQL en Docker: CPU (% de UN nucleo, puede superar 100) y memoria en MB
    $pgCpu = 0; $pgMem = 0
    $ds = & docker stats tfg_postgres --no-stream --format "{{.CPUPerc}}|{{.MemUsage}}"
    if ($ds) {
        $parts = ($ds | Select-Object -First 1).ToString().Split('|')
        if ($parts.Count -ge 2) {
            $pgCpu = [double]::Parse(($parts[0] -replace '[^\d\.]', ''), $inv)
            $pgMem = ToMB(($parts[1].Split('/')[0]))
        }
    }

    $ts = [DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss.fff', $inv)
    $epoch = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $line = (@($ts, $epoch, (N $hostCpu), (N $usedGb), (N $memPct), (N $appCpu), (N $appWs), (N $k6Cpu), (N $k6Ws), (N $pgCpu), (N $pgMem)) -join ',')
    Add-Content -Path $OutputFile -Value $line -Encoding UTF8

    $elapsed = ((Get-Date) - $t0).TotalSeconds
    if ($elapsed -lt $IntervalSec) { Start-Sleep -Milliseconds ([int](($IntervalSec - $elapsed) * 1000)) }
}
