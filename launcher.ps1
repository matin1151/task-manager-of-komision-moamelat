param(
    [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Runtime = Join-Path $Root 'runtime\pythonw.exe'
$Server = Join-Path $Root 'server.py'
$DataDir = Join-Path $env:LOCALAPPDATA 'DastyarKomisionData'
$LogDir = Join-Path $DataDir 'logs'
$LogPath = Join-Path $LogDir 'launcher.log'
$PortFile = Join-Path $DataDir 'server.port'
$PortRange = 8765..8785

function Test-Healthy($Port) {
    try {
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/api/health" -UseBasicParsing -TimeoutSec 1
        return $response.StatusCode -eq 200 -and $response.Content -match '"app"\s*:\s*"DastyarKomision"'
    } catch {
        return $false
    }
}

function Test-Listening($Port) {
    $client = New-Object Net.Sockets.TcpClient
    try {
        $result = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
        if (-not $result.AsyncWaitHandle.WaitOne(150)) { return $false }
        $client.EndConnect($result)
        return $true
    } catch {
        return $false
    } finally {
        $client.Dispose()
    }
}

function Get-HealthyPort {
    if (Test-Path -LiteralPath $PortFile) {
        $savedPort = [int](Get-Content -LiteralPath $PortFile -ErrorAction SilentlyContinue)
        if ($savedPort -in $PortRange -and (Test-Healthy $savedPort)) { return $savedPort }
    }
    foreach ($Port in $PortRange) {
        if ((Test-Listening $Port) -and (Test-Healthy $Port)) { return $Port }
    }
    return $null
}

function Get-FreePort {
    foreach ($Port in $PortRange) {
        $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port)
        try { $listener.Start(); return $Port } catch {} finally { try { $listener.Stop() } catch {} }
    }
    throw 'No free local application port is available.'
}

function Start-Server($Port) {
    if (-not (Test-Path $Runtime)) { throw "Runtime not found: $Runtime" }
    if (-not (Test-Path $Server)) { throw "Server not found: $Server" }

    New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
    $env:DASTYAR_KOMISION_DATA_DIR = $DataDir

    $env:DASTYAR_KOMISION_PORT = [string]$Port
    Start-Process -FilePath $Runtime -ArgumentList @($Server) -WorkingDirectory $Root -WindowStyle Hidden | Out-Null
}

try {
    ${port} = Get-HealthyPort
    if (-not ${port}) {
        ${port} = Get-FreePort
        Start-Server ${port}
        $ready = $false
        for ($i = 0; $i -lt 30; $i++) {
            Start-Sleep -Milliseconds 500
            if (Test-Healthy ${port}) {
                $ready = $true
                break
            }
        }
        if (-not $ready) {
            throw 'The local server did not become healthy within 15 seconds.'
        }
    }

    if (-not $NoBrowser) {
        Start-Process "http://127.0.0.1:${port}/index.html"
    }
} catch {
    New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
    Add-Content -LiteralPath $LogPath -Encoding UTF8 -Value ("[{0}] {1}" -f (Get-Date -Format s), $_.Exception.Message)
    throw
}
