$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$app = Join-Path $env:LOCALAPPDATA 'DastyarKomision'
$pythonZip = Join-Path $env:TEMP 'python-embed.zip'
$pythonUrl = 'https://www.python.org/ftp/python/3.12.10/python-3.12.10-embed-amd64.zip'
New-Item -ItemType Directory -Force -Path $app | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'index.html'), (Join-Path $PSScriptRoot 'server.py') -Destination $app -Force
if (-not (Test-Path (Join-Path $app 'python.exe'))) {
  Write-Host 'در حال دریافت Python مستقل...'
  Invoke-WebRequest $pythonUrl -OutFile $pythonZip -UseBasicParsing
  Expand-Archive $pythonZip -DestinationPath $app -Force
  Remove-Item $pythonZip -Force
}
$task = 'DastyarKomisionServer'
$action = New-ScheduledTaskAction -Execute (Join-Path $app 'pythonw.exe') -Argument ('"' + (Join-Path $app 'server.py') + '"') -WorkingDirectory $app
$trigger = New-ScheduledTaskTrigger -AtLogOn
Register-ScheduledTask -TaskName $task -Action $action -Trigger $trigger -Description 'Dastyar Komision local server and alarms' -Force | Out-Null
Start-ScheduledTask -TaskName $task
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'دستیار کمیسیون معاملات.lnk'))
$shortcut.TargetPath = 'http://127.0.0.1:8765/index.html'; $shortcut.Save()
Start-Process 'http://127.0.0.1:8765/index.html'
Write-Host 'نصب با موفقیت انجام شد.' -ForegroundColor Green
