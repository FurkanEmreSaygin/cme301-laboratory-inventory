param(
    [ValidateSet('start', 'stop', 'status')]
    [string]$Action = 'status'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$clusterPath = Join-Path $projectRoot '.local\postgres-data'
$pgCtlPath = Join-Path $projectRoot '.local\postgres-runtime\pgsql\bin\pg_ctl.exe'
$serverLogPath = Join-Path $projectRoot '.local\postgres.log'

if (-not (Test-Path -LiteralPath $pgCtlPath)) {
    throw 'Proje içindeki taşınabilir PostgreSQL programları bulunamadı. Normal PostgreSQL kurulumunu kullanabilir veya yerel runtime dosyalarını hazırlayabilirsiniz.'
}
if (-not (Test-Path -LiteralPath (Join-Path $clusterPath 'PG_VERSION'))) {
    throw 'Bu proje için PostgreSQL veri klasörü henüz oluşturulmamış.'
}

$projectPort = '54329'
$envPath = Join-Path $projectRoot '.env'
if (Test-Path -LiteralPath $envPath) {
    foreach ($line in Get-Content -LiteralPath $envPath) {
        if ($line -match '^PGPORT=(\d+)$') { $projectPort = $Matches[1] }
    }
}

switch ($Action) {
    'status' { & $pgCtlPath -D $clusterPath status }
    'start' {
        & $pgCtlPath -D $clusterPath status *> $null
        if ($LASTEXITCODE -eq 0) { Write-Output 'PostgreSQL zaten çalışıyor.'; exit 0 }
        & $pgCtlPath -D $clusterPath -l $serverLogPath -o "-h 127.0.0.1 -p $projectPort" -w start
    }
    'stop' { & $pgCtlPath -D $clusterPath -m fast -w stop }
}
exit $LASTEXITCODE
