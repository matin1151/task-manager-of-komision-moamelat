@echo off
cd /d "%~dp0"
where py >nul 2>nul
if %errorlevel%==0 (
  start "دستیار کمیسیون معاملات" http://127.0.0.1:8765/index.html
  py -m http.server 8765 --bind 127.0.0.1
  goto :eof
)
where python >nul 2>nul
if %errorlevel%==0 (
  start "دستیار کمیسیون معاملات" http://127.0.0.1:8765/index.html
  python -m http.server 8765 --bind 127.0.0.1
  goto :eof
)
echo Python was not found. Install Python 3 and run this file again.
pause
