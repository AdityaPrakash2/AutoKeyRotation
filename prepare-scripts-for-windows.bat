@echo off
echo Preparing scripts for execution on Windows...

REM Check if dos2unix is installed
where dos2unix >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo dos2unix is not installed. Please install it using:
    echo   - Git Bash: Use the built-in dos2unix
    echo   - Chocolatey: choco install dos2unix
    echo   - WSL: apt-get install dos2unix
    exit /b 1
)

echo Converting shell scripts to Unix line endings...
for /r %%i in (scripts\*.sh) do (
    echo Converting: %%i
    dos2unix "%%i"
)

echo Ensuring script files are executable...
for /r %%i in (scripts\*.sh) do (
    echo Making executable: %%i
    chmod +x "%%i"
)

echo Done! Scripts are now ready for use with Docker on Windows.
echo.
echo If you encounter any issues, you may need to run:
echo   - docker-compose down
echo   - docker-compose up -d
echo to restart the containers with the fixed scripts.

exit /b 0 