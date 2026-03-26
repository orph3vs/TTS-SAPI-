@echo off
setlocal
set "SCRIPT_DIR=%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%audio_creator.ps1"
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if "%EXIT_CODE%"=="0" (
    echo Completed.
) else (
    echo Failed. Check the messages above.
)

if /I not "%~1"=="--no-pause" pause
exit /b %EXIT_CODE%

