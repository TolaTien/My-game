@echo off
chcp 65001 >nul
echo ========================================================
echo   GOLD RUSH MOBILE - DONG GOI FILE APK CHO ANDROID
echo ========================================================
set "PROJECT_DIR=%~dp0"
if "%PROJECT_DIR:~-1%"=="\" set "PROJECT_DIR=%PROJECT_DIR:~0,-1%"

REM Anh xa o dia ao Z: de tranh loi duong dan tieng Viet cua Gradle & gen_snapshot tren Windows
subst Z: /D >nul 2>&1
subst Z: "%PROJECT_DIR%"
cd /d Z:\

call flutter build apk --release --no-tree-shake-icons

cd /d "%PROJECT_DIR%"
subst Z: /D >nul 2>&1

echo.
echo [HOAN TAT] File APK da duoc xuat tai:
echo "%PROJECT_DIR%\build\app\outputs\flutter-apk\app-release.apk"
pause
