param(
    [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Runtime = Join-Path $Root 'runtime\pythonw.exe'
$Server = Join-Path $Root 'server.py'
$DataDir = Join-Path $env:LOCALAPPDATA 'DastyarKomisionData'
$LogDir = Join-Path $DataDir 'logs'
$LogPath = Join-Path $LogDir 'server.log'
$HealthUrl = 'http://127.0.0.1:8765/api/health'
$AppUrl = 'http://127.0.0.1:8765/index.html'

function Test-Healthy {
    try {
        $response = Invoke-WebRequest -Uri $HealthUrl -UseBasicParsing -TimeoutSec 2
        return $response.StatusCode -eq 200 -and $response.Content -match '"ok"\s*:\s*true'
    } catch {
        return $false
    }
}

function Start-Server {
    if (-not (Test-Path $Runtime)) { throw "Runtime not found: $Runtime" }
    if (-not (Test-Path $Server)) { throw "Server not found: $Server" }

    New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
    $env:DASTYAR_KOMISION_DATA_DIR = $DataDir

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Runtime
    $psi.Arguments = "`"$Server`""
    $psi.WorkingDirectory = $Root
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.EnvironmentVariables['DASTYAR_KOMISION_DATA_DIR'] = $DataDir
    $process = [System.Diagnostics.Process]::Start($psi)

    Start-Job -ScriptBlock {
        param($ProcessId, $LogPath)
        try {
            $p = Get-Process -Id $ProcessId -ErrorAction Stop
            $p.WaitForExit()
            Add-Content -Path $LogPath -Encoding UTF8 -Value ("[{0}] server process exited with code {1}" -f (Get-Date -Format s), $p.ExitCode)
        } catch {}
    } -ArgumentList $process.Id, $LogPath | Out-Null
}

if (-not (Test-Healthy)) {
    Start-Server
    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Milliseconds 500
        if (Test-Healthy) {
            $ready = $true
            break
        }
    }
    if (-not $ready) {
        throw 'The local server did not become healthy within 15 seconds.'
    }
}

if (-not $NoBrowser) {
    Start-Process $AppUrl
}
