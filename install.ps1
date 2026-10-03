$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$app = Join-Path $env:LOCALAPPDATA 'DastyarKomision'
$pythonZip = Join-Path $env:TEMP 'python-embed.zip'
$pythonUrl = 'https://www.python.org/ftp/python/3.12.10/python-3.12.10-embed-amd64.zip'

Write-Host 'Preparing Dastyar Komision installation...'

New-Item -ItemType Directory -Force -Path $app | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'index.html') -Destination $app -Force
Copy-Item (Join-Path $PSScriptRoot 'server.py') -Destination $app -Force

$pythonExe = Join-Path $app 'python.exe'
if (-not (Test-Path $pythonExe)) {
    Write-Host 'Downloading standalone Python...'
    Invoke-WebRequest -Uri $pythonUrl -OutFile $pythonZip -UseBasicParsing
    Expand-Archive -Path $pythonZip -DestinationPath $app -Force
    Remove-Item $pythonZip -Force
}

$pythonw = Join-Path $app 'pythonw.exe'
$server = Join-Path $app 'server.py'
if (-not (Test-Path $pythonw)) { throw 'pythonw.exe was not found after Python installation.' }
if (-not (Test-Path $server)) { throw 'server.py was not copied to the application directory.' }

$task = 'DastyarKomisionServer'
$action = New-ScheduledTaskAction -Execute $pythonw -Argument ('"' + $server + '"') -WorkingDirectory $app
$trigger = New-ScheduledTaskTrigger -AtLogOn
Register-ScheduledTask -TaskName $task -Action $action -Trigger $trigger -Description 'Dastyar Komision local server and alarms' -Force | Out-Null
Start-ScheduledTask -TaskName $task

$shell = New-Object -ComObject WScript.Shell
$desktop = [Environment]::GetFolderPath('Desktop')
$shortcutPath = Join-Path $desktop 'Dastyar Komision.lnk'
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = 'http://127.0.0.1:8765/index.html'
$shortcut.Save()

Start-Sleep -Seconds 2
Start-Process 'http://127.0.0.1:8765/index.html'
Write-Host 'Dastyar Komision installed successfully.' -ForegroundColor Green
