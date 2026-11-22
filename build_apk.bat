@echo off
chcp 65001 >nul
echo ========================================================
echo   BIG-WAR MOBILE - DONG GOI FILE APK CHO ANDROID
echo ========================================================
set "PROJECT_DIR=%~dp0"
if "%PROJECT_DIR:~-1%"=="\" set "PROJECT_DIR=%PROJECT_DIR:~0,-1%"

cd /d "%PROJECT_DIR%"

if exist ".env" (
    call flutter build apk --release --split-per-abi --no-tree-shake-icons --dart-define-from-file=.env
) else (
    call flutter build apk --release --split-per-abi --no-tree-shake-icons
)

echo.
echo [HOAN TAT] Cac file APK toi uu dung luong da duoc xuat tai:
echo - May Android 64-bit (pho bien nhat): "%PROJECT_DIR%\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"
echo - May Android 32-bit (may cu/cau hinh yeu): "%PROJECT_DIR%\build\app\outputs\flutter-apk\app-armeabi-v7a-release.apk"
pause
