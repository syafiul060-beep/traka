# Quick Fix: Hapus Gradle Lock File

## Error
```
Timeout waiting to lock journal cache
Owner PID: 8000
Our PID: 2084
```

## Solusi Cepat (Copy-Paste)

Jalankan perintah berikut **satu per satu** di Command Prompt:

### 1. Stop Semua Process Java/Gradle
```bash
taskkill /F /IM java.exe
cd android
gradlew --stop
cd ..
```

### 2. Tunggu 5 Detik
```bash
timeout /t 5
```

### 3. Hapus Lock File
```bash
rmdir /s /q "%USERPROFILE%\.gradle\caches\journal-1"
```

### 4. Build Lagi
```bash
flutter clean
flutter pub get
flutter run
```

## Atau Gunakan Script Otomatis

Buat file `fix_gradle_lock.bat` di root project:

```batch
@echo off
echo Stopping Gradle processes...
taskkill /F /IM java.exe 2>nul
cd android
call gradlew --stop
cd ..
echo Waiting 5 seconds...
timeout /t 5 /nobreak >nul
echo Removing lock file...
rmdir /s /q "%USERPROFILE%\.gradle\caches\journal-1" 2>nul
echo Done! Now run: flutter clean && flutter pub get && flutter run
pause
```

Jalankan dengan double-click atau:
```bash
fix_gradle_lock.bat
```

## Catatan

- **Jangan hapus lock file** jika ada build yang sedang berjalan
- **Tunggu beberapa detik** setelah stop process sebelum hapus lock file
- **Build pertama setelah hapus cache** akan lebih lambat (normal)
