@echo off
cd /d "%~dp0"
set "PYTHON_CMD="
where py >nul 2>nul && set "PYTHON_CMD=py"
if not defined PYTHON_CMD (
  where python >nul 2>nul && set "PYTHON_CMD=python"
)
if not defined PYTHON_CMD (
  echo Python was not found. Install Python 3 and run this file again.
  pause
  goto :eof
)

start "دستیار کمیسیون معاملات - سرور" /min %PYTHON_CMD% server.py

set /a tries=0
:wait_server
%PYTHON_CMD% -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8765/api/health', timeout=1)" >nul 2>nul
if %errorlevel%==0 goto :open_app
set /a tries+=1
if %tries% GEQ 20 goto :server_failed
timeout /t 1 /nobreak >nul
goto :wait_server

:open_app
start "" http://127.0.0.1:8765/index.html
goto :eof

:server_failed
echo The local server did not start correctly.
echo Check whether port 8765 is already in use, then try again.
pause
