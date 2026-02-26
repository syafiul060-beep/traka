@echo off
echo === Traka: Fix ADB Install ===
echo.
echo PENTING Samsung: Jika pakai Secure Folder, nonaktifkan dulu!
echo    Pengaturan - Keamanan - Secure Folder - Hapus
echo.

echo 1. Uninstalling existing app (if any)...
adb uninstall id.traka.app 2>nul
if %errorlevel% neq 0 (
    echo    App mungkin belum terinstall - lanjut...
) else (
    echo    App berhasil di-uninstall.
)
echo.

echo 2. Building APK...
call flutter build apk --debug
if %errorlevel% neq 0 (
    echo BUILD GAGAL. Cek error di atas.
    pause
    exit /b 1
)
echo.

echo 3. Installing APK...
adb install -r -t build\app\outputs\flutter-apk\app-debug.apk
if %errorlevel% neq 0 (
    echo.
    echo INSTALL GAGAL. Coba:
    echo   - Pastikan HP terhubung: adb devices
    echo   - Uninstall manual: adb uninstall id.traka.app
    echo   - Cek storage HP
    pause
    exit /b 1
)

echo.
echo Berhasil! Jalankan app dengan: flutter run
pause
