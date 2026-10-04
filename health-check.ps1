param(
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$Ports = 8765..8785

try {
    $health = $null
    foreach ($port in $Ports) {
        try {
            $response = Invoke-WebRequest -Uri "http://127.0.0.1:$port/api/health" -UseBasicParsing -TimeoutSec 1
            if ($response.StatusCode -eq 200 -and $response.Content -match '"app"\s*:\s*"DastyarKomision"') { $health = $response.Content | ConvertFrom-Json; break }
        } catch {}
    }
    if (-not $health) { throw 'No healthy Dastyar Komision server was found.' }
    if (-not $health.ok) {
        throw 'Server returned ok=false'
    }
    if (-not $Quiet) {
        Write-Host 'Dastyar Komision is running.' -ForegroundColor Green
        Write-Host "Data folder: $($health.dataDir)"
        Write-Host "Database:    $($health.database)"
    }
    exit 0
} catch {
    if (-not $Quiet) {
        Write-Host 'Dastyar Komision is not healthy.' -ForegroundColor Red
        Write-Host $_.Exception.Message
    }
    exit 1
}
