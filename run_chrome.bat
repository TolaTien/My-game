@echo off
chcp 65001 >nul
echo ========================================================
echo   GOLD RUSH - CHAY THU TREN TRINH DUYET CHROME
echo ========================================================
set "PROJECT_DIR=%~dp0"
if "%PROJECT_DIR:~-1%"=="\" set "PROJECT_DIR=%PROJECT_DIR:~0,-1%"

subst Z: /D >nul 2>&1
subst Z: "%PROJECT_DIR%"
cd /d Z:\

call flutter run -d chrome

cd /d "%PROJECT_DIR%"
subst Z: /D >nul 2>&1
pause
