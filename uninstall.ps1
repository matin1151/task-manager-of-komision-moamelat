$ErrorActionPreference = 'SilentlyContinue'
Unregister-ScheduledTask -TaskName 'DastyarKomisionServer' -Confirm:$false
Remove-Item (Join-Path ([Environment]::GetFolderPath('Desktop')) 'دستیار کمیسیون معاملات.lnk') -Force
Write-Host 'سرویس و میان‌بر حذف شدند. فایل داده‌ها در %LOCALAPPDATA%\DastyarKomision باقی مانده است.'
