$ErrorActionPreference = 'Stop'

$AppName = 'DastyarKomision'
$InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\DastyarKomision'
$DataDir = Join-Path $env:LOCALAPPDATA 'DastyarKomisionData'
$StartupDir = [Environment]::GetFolderPath('Startup')
$DesktopDir = [Environment]::GetFolderPath('Desktop')
$StartMenuDir = Join-Path ([Environment]::GetFolderPath('Programs')) 'Dastyar Komision'
$LogPath = Join-Path $DataDir 'install.log'
$PayloadDir = Join-Path $PSScriptRoot 'app'

function Write-Step($Message) {
    Write-Host "[Dastyar Komision] $Message"
}

function New-Shortcut($Path, $Target, $Arguments = '', $WorkingDirectory = '') {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($Path)
    $shortcut.TargetPath = $Target
    if ($Arguments) { $shortcut.Arguments = $Arguments }
    if ($WorkingDirectory) { $shortcut.WorkingDirectory = $WorkingDirectory }
    $shortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll,220"
    $shortcut.Save()
}

function Stop-OldServer {
    Write-Step 'Stopping previous background server if it is running...'
    try {
        Get-ScheduledTask -TaskName 'DastyarKomisionServer' -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false
    } catch {}

    $matches = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -and
            $_.CommandLine -match 'server\.py' -and
            ($_.CommandLine -match 'DastyarKomision' -or $_.CommandLine -match 'task-manager-of-komision')
        }
    foreach ($proc in $matches) {
        try { Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
    }
}

function Assert-Payload {
    foreach ($file in @('index.html', 'server.py', 'launcher.ps1', 'start-app.vbs', 'uninstall.ps1', 'health-check.ps1')) {
        if (-not (Test-Path (Join-Path $PayloadDir $file))) {
            throw "Installer payload is missing $file"
        }
    }
    if (-not (Test-Path (Join-Path $PayloadDir 'assets\Vazirmatn-Regular.ttf'))) {
        throw 'Bundled Persian font is missing.'
    }
    if (-not (Test-Path (Join-Path $PayloadDir 'runtime\pythonw.exe'))) {
        throw 'Bundled Python runtime is missing. Build the Windows delivery package before installing.'
    }
}

New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
Start-Transcript -Path $LogPath -Append | Out-Null

try {
    Assert-Payload
    Stop-OldServer

    Write-Step 'Installing application files...'
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    New-Item -ItemType Directory -Force -Path $StartMenuDir | Out-Null

    foreach ($item in @('index.html', 'server.py', 'launcher.ps1', 'start-app.vbs', 'uninstall.ps1', 'health-check.ps1', 'assets', 'runtime')) {
        $source = Join-Path $PayloadDir $item
        $target = Join-Path $InstallDir $item
        Copy-Item -LiteralPath $source -Destination $target -Recurse -Force
    }

    $oldDb = Join-Path $env:LOCALAPPDATA 'DastyarKomision\komision.db'
    $newDb = Join-Path $DataDir 'komision.db'
    if ((Test-Path $oldDb) -and -not (Test-Path $newDb)) {
        Write-Step 'Migrating existing database to the stable data folder...'
        Copy-Item -LiteralPath $oldDb -Destination $newDb -Force
    }

    Write-Step 'Creating desktop and startup shortcuts...'
    $launcher = Join-Path $InstallDir 'start-app.vbs'
    $wscript = Join-Path $env:SystemRoot 'System32\wscript.exe'
    New-Shortcut -Path (Join-Path $DesktopDir 'Dastyar Komision.lnk') -Target $wscript -Arguments "//B //Nologo `"$launcher`"" -WorkingDirectory $InstallDir
    New-Shortcut -Path (Join-Path $StartupDir 'Dastyar Komision.lnk') -Target $wscript -Arguments "//B //Nologo `"$launcher`" -NoBrowser" -WorkingDirectory $InstallDir
    New-Shortcut -Path (Join-Path $StartMenuDir 'Open Dastyar Komision.lnk') -Target $wscript -Arguments "//B //Nologo `"$launcher`"" -WorkingDirectory $InstallDir
    New-Shortcut -Path (Join-Path $StartMenuDir 'Health Check.lnk') -Target 'powershell.exe' -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$InstallDir\health-check.ps1`"" -WorkingDirectory $InstallDir
    New-Shortcut -Path (Join-Path $StartMenuDir 'Uninstall.lnk') -Target 'powershell.exe' -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$InstallDir\uninstall.ps1`"" -WorkingDirectory $InstallDir

    Write-Step 'Starting application...'
    Start-Process -FilePath $wscript -ArgumentList @('//B', '//Nologo', $launcher)
    Start-Sleep -Seconds 2
    & (Join-Path $InstallDir 'health-check.ps1') -Quiet

    Write-Host ''
    Write-Host 'Dastyar Komision installed successfully.' -ForegroundColor Green
    Write-Host "Application: $InstallDir"
    Write-Host "Data:        $DataDir"
}
finally {
    Stop-Transcript | Out-Null
}
