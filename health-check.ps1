param(
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$HealthUrl = 'http://127.0.0.1:8765/api/health'

try {
    $response = Invoke-WebRequest -Uri $HealthUrl -UseBasicParsing -TimeoutSec 3
    if ($response.StatusCode -ne 200) {
        throw "Unexpected status code $($response.StatusCode)"
    }
    $health = $response.Content | ConvertFrom-Json
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
