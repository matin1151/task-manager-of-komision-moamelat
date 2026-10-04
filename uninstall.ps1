$ErrorActionPreference = 'SilentlyContinue'

$InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\DastyarKomision'
$DataDir = Join-Path $env:LOCALAPPDATA 'DastyarKomisionData'
$StartupDir = [Environment]::GetFolderPath('Startup')
$DesktopDir = [Environment]::GetFolderPath('Desktop')
$StartMenuDir = Join-Path ([Environment]::GetFolderPath('Programs')) 'Dastyar Komision'

Write-Host 'Removing Dastyar Komision shortcuts and application files...'

Get-ScheduledTask -TaskName 'DastyarKomisionServer' | Unregister-ScheduledTask -Confirm:$false

$matches = Get-CimInstance Win32_Process |
    Where-Object {
        $_.CommandLine -and
        $_.CommandLine -match 'server\.py' -and
        ($_.CommandLine -match 'DastyarKomision' -or $_.CommandLine -match 'task-manager-of-komision')
    }
foreach ($proc in $matches) {
    Stop-Process -Id $proc.ProcessId -Force
}

Remove-Item (Join-Path $DesktopDir 'Dastyar Komision.lnk') -Force
Remove-Item (Join-Path $StartupDir 'Dastyar Komision.lnk') -Force
Remove-Item $StartMenuDir -Recurse -Force
Remove-Item $InstallDir -Recurse -Force

Write-Host ''
Write-Host 'Uninstall complete.' -ForegroundColor Green
Write-Host "User data was preserved here: $DataDir"
Write-Host 'Delete that folder manually only if you intentionally want to remove all saved transactions.'
