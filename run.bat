@echo off
setlocal
cd /d "%~dp0"
if not exist ".venv\Scripts\python.exe" (
    py -3 -m venv .venv
    if errorlevel 1 goto fail
)
".venv\Scripts\python.exe" -m pip install --disable-pip-version-check -r backend\requirements.txt
if errorlevel 1 goto fail
".venv\Scripts\python.exe" backend\server.py
if not errorlevel 1 exit /b 0
:fail
echo Review the error above. See README.md for setup and troubleshooting.
pause
exit /b 1
