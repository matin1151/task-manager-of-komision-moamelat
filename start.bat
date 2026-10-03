@echo off
cd /d "%~dp0"
where py >nul 2>nul
if %errorlevel%==0 (
  start "دستیار کمیسیون معاملات" http://127.0.0.1:8765/index.html
  py server.py
  goto :eof
)
where python >nul 2>nul
if %errorlevel%==0 (
  start "دستیار کمیسیون معاملات" http://127.0.0.1:8765/index.html
  python server.py
  goto :eof
)
echo Python was not found. Install Python 3 and run this file again.
pause
