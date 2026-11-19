@echo off
chcp 65001 >nul
echo ========================================================
echo   GOLD RUSH MOBILE - KHOI CHAY TREN MAY AO ANDROID
echo ========================================================

set "PROJECT_DIR=%~dp0"
if "%PROJECT_DIR:~-1%"=="\" set "PROJECT_DIR=%PROJECT_DIR:~0,-1%"

REM 1. Anh xa o dia ao Z: de tranh loi duong dan tieng Viet cua Gradle & Dart
subst Z: /D >nul 2>&1
subst Z: "%PROJECT_DIR%"
if errorlevel 1 (
    echo [CANH BAO] Khong the anh xa Z:, su dung o dia hien tai...
    cd /d "%PROJECT_DIR%"
) else (
    echo [OK] Da anh xa thu muc du an vao o dia Z:\
    cd /d Z:\
)

REM 2. Kiem tra va khoi dong may ao Medium Phone neu chua bat
echo [1/3] Kiem tra may ao Android...
call flutter emulators --launch Medium_Phone >nul 2>&1

echo [2/3] Dang cho may ao san sang...
timeout /t 3 /nobreak >nul

REM 3. Chay ung dung len may ao
echo [3/3] Dang khoi chay Flutter len Medium Phone...
call flutter run -d emulator-5554

echo.
echo [DA DONG] Dang don dep o dia ao...
cd /d "%PROJECT_DIR%"
subst Z: /D >nul 2>&1
pause
