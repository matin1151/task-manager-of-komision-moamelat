$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$localCompiler = Join-Path $root 'tools\InnoSetup\ISCC.exe'
$commandCompiler = Get-Command iscc.exe -ErrorAction SilentlyContinue
$compiler = if (Test-Path -LiteralPath $localCompiler) { $localCompiler } elseif ($commandCompiler) { $commandCompiler.Source } else { $null }
if (-not $compiler) { throw 'Inno Setup Compiler (ISCC.exe) is not available.' }
& $compiler (Join-Path $root 'setup.iss')
if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed with exit code $LASTEXITCODE" }
Write-Host (Join-Path $root 'build\DastyarKomision-Setup-v1.0.2.exe') -ForegroundColor Green
