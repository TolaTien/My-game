@echo off
chcp 65001 >nul
echo ========================================================
echo   BIG-WAR MOBILE - KHOI CHAY TREN MAY AO ANDROID
echo ========================================================

set "PROJECT_DIR=%~dp0"
if "%PROJECT_DIR:~-1%"=="\" set "PROJECT_DIR=%PROJECT_DIR:~0,-1%"

cd /d "%PROJECT_DIR%"

REM 2. Kiem tra va khoi dong may ao Medium Phone neu chua bat
echo [1/3] Kiem tra may ao Android...
call flutter emulators --launch Medium_Phone >nul 2>&1

echo [2/3] Dang cho may ao san sang...
timeout /t 3 /nobreak >nul

REM 3. Chay ung dung len may ao
echo [3/3] Dang khoi chay Flutter len Medium Phone...
if exist ".env" (
    call flutter run -d emulator-5554 --dart-define-from-file=.env
) else (
    call flutter run -d emulator-5554
)

echo.
echo [DA DONG] Hoan tat.
pause
