@echo off
echo === Traka: Diagnosa Error Install ===
echo.

echo [1] Cek device terhubung...
adb devices
echo.

echo [2] Uninstall app lama...
adb uninstall id.traka.app 2>nul
echo.

echo [3] Build APK jika belum ada...
if not exist "build\app\outputs\flutter-apk\app-debug.apk" (
    call flutter build apk --debug
)
echo.

echo [4] Coba install (akan tampil error detail)...
adb install -r -t -d build\app\outputs\flutter-apk\app-debug.apk 2>&1
set INSTALL_RESULT=%errorlevel%
echo.

if %INSTALL_RESULT% neq 0 (
    echo [5] Ambil error dari logcat...
    adb logcat -d -s PackageManager:* 2>nul | findstr /i "fail error install"
    echo.
    echo ---
    echo Jika masih gagal, coba:
    echo 1. HAPUS Secure Folder (Samsung): Pengaturan - Keamanan - Secure Folder
    echo 2. Uninstall Traka MANUAL dari HP: Pengaturan - Aplikasi - Traka - Uninstall
    echo 3. Restart HP, sambung USB lagi
    echo 4. Cek storage HP minimal 500 MB kosong
) else (
    echo Berhasil!
)

echo.
pause
