@echo off
chcp 65001 >nul
echo ========================================================
echo   GOLD RUSH MOBILE - DONG GOI FILE APK CHO ANDROID
echo ========================================================
set "PROJECT_DIR=%~dp0"
if "%PROJECT_DIR:~-1%"=="\" set "PROJECT_DIR=%PROJECT_DIR:~0,-1%"

cd /d "%PROJECT_DIR%"

call flutter build apk --release --no-tree-shake-icons

echo.
echo [HOAN TAT] File APK da duoc xuat tai:
echo "%PROJECT_DIR%\build\app\outputs\flutter-apk\app-release.apk"
pause
