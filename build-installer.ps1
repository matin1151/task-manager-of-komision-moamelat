$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$iscc = Get-Command iscc.exe -ErrorAction SilentlyContinue
if (-not $iscc) { throw 'Inno Setup Compiler (ISCC.exe) is not installed. Install Inno Setup, then run this script again.' }
& $iscc.Source (Join-Path $root 'setup.iss')
if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed with exit code $LASTEXITCODE" }
Write-Host (Join-Path $root 'build\DastyarKomision-Setup-v1.0.1.exe') -ForegroundColor Green
