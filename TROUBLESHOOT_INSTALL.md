# Troubleshooting: ADB Failed to Install APK (Exit Code 1)

## Error
```
Error: ADB exited with exit code 1
adb.exe: failed to install ... app-debug.apk
```

## ⚠️ PENTING untuk Samsung (SM-N970F, dll.)

**Samsung Secure Folder** bisa memblokir ADB install!
- Buka: **Pengaturan → Keamanan dan Privasi → Pengaturan Keamanan Lainnya → Secure Folder**
- Pilih **Pengaturan** (ikon gear) → **Hapus Secure Folder**
- Atau nonaktifkan Secure Folder sementara
- Setelah itu coba `adb install` lagi

## Solusi (coba berurutan)

### 1. Uninstall app yang sudah ada, lalu install ulang
Sering terjadi jika app Traka sudah terinstall (dari Play Store atau build sebelumnya) dengan signature berbeda.

```bash
adb uninstall id.traka.app
flutter run
```

### 2. Install dengan flag replace
```bash
adb install -r build\app\outputs\flutter-apk\app-debug.apk
```

### 3. Cek koneksi device
```bash
adb devices
```
- Pastikan SM N970F muncul dan status `device` (bukan `unauthorized`)
- Jika `unauthorized`: cabut USB, izinkan debugging di HP, sambung lagi

### 4. Restart ADB
```bash
adb kill-server
adb start-server
adb devices
```

### 5. Cek storage HP
- Buka Settings → Storage
- Pastikan ada ruang kosong minimal 500 MB

### 6. USB Debugging
- Settings → Developer Options → USB Debugging = ON
- Jika pakai kabel USB 3.0, coba port USB lain

### 7. Install APK manual (tanpa Flutter)
```bash
flutter build apk --debug
adb install -r build\app\outputs\flutter-apk\app-debug.apk
```

### 8. Uninstall manual dari HP (jika adb uninstall gagal)
- Buka **Pengaturan → Aplikasi → Traka**
- Ketuk **Uninstall**
- Lalu jalankan `flutter run` lagi

### 9. Lihat error detail dari device
```bash
adb logcat -c
adb install build\app\outputs\flutter-apk\app-debug.apk
adb logcat -d | findstr "PackageManager"
```
