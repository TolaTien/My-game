@echo off
chcp 65001 >nul
echo ========================================================
echo   BIG-WAR - CHAY THU TREN TRINH DUYET CHROME
echo ========================================================
set "PROJECT_DIR=%~dp0"
if "%PROJECT_DIR:~-1%"=="\" set "PROJECT_DIR=%PROJECT_DIR:~0,-1%"

cd /d "%PROJECT_DIR%"

if exist ".env" (
    call flutter run -d chrome --dart-define-from-file=.env
) else (
    call flutter run -d chrome
)
pause
