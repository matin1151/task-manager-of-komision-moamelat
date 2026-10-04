$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$BuildDir = Join-Path $Root 'build'
$PackageDir = Join-Path $BuildDir 'DastyarKomision-Windows'
$RuntimeZip = Join-Path $BuildDir 'python-embed.zip'
$RuntimeDir = Join-Path $PackageDir 'runtime'
$PythonUrl = 'https://www.python.org/ftp/python/3.12.10/python-3.12.10-embed-amd64.zip'

Write-Host 'Building Dastyar Komision Windows delivery package...'

if (Test-Path $PackageDir) {
    Remove-Item -LiteralPath $PackageDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $PackageDir | Out-Null
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

foreach ($item in @('index.html', 'server.py', 'install.bat', 'install.ps1', 'launcher.ps1', 'start-app.vbs', 'health-check.ps1', 'uninstall.ps1', 'README.txt', 'DELIVERY_GUIDE_FA.md')) {
    Copy-Item -LiteralPath (Join-Path $Root $item) -Destination (Join-Path $PackageDir $item) -Force
}

if (-not (Test-Path $RuntimeZip)) {
    Write-Host 'Downloading bundled Python runtime...'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $PythonUrl -OutFile $RuntimeZip -UseBasicParsing
}

Write-Host 'Expanding runtime...'
Expand-Archive -Path $RuntimeZip -DestinationPath $RuntimeDir -Force

$pth = Get-ChildItem -Path $RuntimeDir -Filter '*._pth' | Select-Object -First 1
if ($pth) {
    $lines = Get-Content -LiteralPath $pth.FullName
    if ($lines -notcontains 'Lib\site-packages') {
        Add-Content -LiteralPath $pth.FullName -Value 'Lib\site-packages'
    }
}

$ZipPath = Join-Path $BuildDir 'DastyarKomision-Windows.zip'
if (Test-Path $ZipPath) {
    Remove-Item -LiteralPath $ZipPath -Force
}
Compress-Archive -Path (Join-Path $PackageDir '*') -DestinationPath $ZipPath -Force

Write-Host ''
Write-Host "Package folder: $PackageDir" -ForegroundColor Green
Write-Host "Package zip:    $ZipPath" -ForegroundColor Green
