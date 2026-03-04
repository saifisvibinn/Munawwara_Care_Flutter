@echo off
echo.
echo =========================================
echo  Munawwara Care - Clean and Run
echo =========================================
echo.

cd /d "%~dp0"

echo [1/4] Cleaning Flutter build cache...
call flutter clean
if errorlevel 1 goto :error

echo.
echo [2/4] Getting packages...
call flutter pub get
if errorlevel 1 goto :error

echo.
echo [3/4] Regenerating app icons...
call dart run flutter_launcher_icons
if errorlevel 1 goto :error

echo.
echo [4/4] Running app...
call flutter run
goto :end

:error
echo.
echo *** Something went wrong. See error above. ***
pause
exit /b 1

:end
