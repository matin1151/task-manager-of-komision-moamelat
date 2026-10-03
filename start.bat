@echo off
cd /d "%~dp0"
where py >nul 2>nul
if %errorlevel%==0 (
  start "دستیار کمیسیون معاملات - سرور" /min py server.py
  timeout /t 2 /nobreak >nul
  start "" http://127.0.0.1:8765/index.html
  goto :eof
)
where python >nul 2>nul
if %errorlevel%==0 (
  start "دستیار کمیسیون معاملات - سرور" /min python server.py
  timeout /t 2 /nobreak >nul
  start "" http://127.0.0.1:8765/index.html
  goto :eof
)
echo Python was not found. Install Python 3 and run this file again.
pause
