@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
set "rc=%errorlevel%"
echo.
if not "%rc%"=="0" (
  echo Installation failed. Please send the text in this window to support.
) else (
  echo Installation finished. You can close this window.
)
echo.
pause
exit /b %rc%
