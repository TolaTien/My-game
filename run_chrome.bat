@echo off
chcp 65001 >nul
echo ========================================================
echo   GOLD RUSH - CHAY THU TREN TRINH DUYET CHROME
echo ========================================================
set "PROJECT_DIR=%~dp0"
if "%PROJECT_DIR:~-1%"=="\" set "PROJECT_DIR=%PROJECT_DIR:~0,-1%"

cd /d "%PROJECT_DIR%"

call flutter run -d chrome
pause
