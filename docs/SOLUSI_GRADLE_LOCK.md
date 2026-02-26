# Solusi Error "Timeout waiting to lock journal cache"

## Masalah
Error saat build Flutter:
```
Timeout waiting to lock journal cache (C:\Users\syafi\.gradle\caches\journal-1).
It is currently in use by another Gradle instance.
Owner PID: 6020
Our PID: 1044
```

## Penyebab
Ada Gradle process lain yang masih berjalan atau lock file tidak terhapus dengan benar setelah build sebelumnya gagal.

## Solusi Cepat

### Langkah 1: Stop Semua Gradle Process

**Via Command Prompt:**
```bash
cd android
gradlew --stop
cd ..
```

**Via Task Manager:**
1. Tekan `Ctrl + Shift + Esc`
2. Tab **Details**
3. Cari process **java.exe** atau **gradle**
4. Klik kanan → **End task** untuk semua instance

**Via Command (Force Kill):**
```bash
taskkill /F /IM java.exe
```

### Langkah 2: Hapus Lock File Manual

**Hapus folder journal cache:**
```bash
rmdir /s /q "%USERPROFILE%\.gradle\caches\journal-1"
```

Atau hapus via File Explorer:
1. Buka: `C:\Users\syafi\.gradle\caches\`
2. Hapus folder `journal-1` (jika ada)
3. Atau hapus seluruh folder `caches` (akan di-rebuild otomatis)

### Langkah 3: Hapus Gradle Daemon Folder (Opsional)

Jika masih bermasalah, hapus daemon folder:
```bash
rmdir /s /q "%USERPROFILE%\.gradle\daemon"
```

### Langkah 4: Clean dan Build Lagi

```bash
flutter clean
flutter pub get
flutter run
```

## Solusi Lengkap (Step by Step)

### 1. Stop Semua Process Gradle/Java
```bash
# Stop via Gradle
cd android
gradlew --stop
cd ..

# Force kill Java processes
taskkill /F /IM java.exe
```

### 2. Hapus Lock Files
```bash
# Hapus journal cache
rmdir /s /q "%USERPROFILE%\.gradle\caches\journal-1"

# Hapus daemon (opsional)
rmdir /s /q "%USERPROFILE%\.gradle\daemon"
```

### 3. Tunggu Beberapa Detik
Tunggu 5-10 detik untuk memastikan semua process sudah benar-benar berhenti.

### 4. Clean Project
```bash
flutter clean
```

### 5. Get Dependencies
```bash
flutter pub get
```

### 6. Build Lagi
```bash
flutter run
```

## Alternatif: Build Tanpa Daemon

Jika masih bermasalah, build tanpa daemon:
```bash
cd android
gradlew assembleDebug --no-daemon
cd ..
flutter install
```

## Troubleshooting

### Error: "Access Denied" saat hapus folder
**Solusi:**
- Tutup semua aplikasi yang menggunakan Gradle (Android Studio, dll)
- Run Command Prompt sebagai Administrator
- Atau restart komputer dan coba lagi

### Error Masih Terjadi Setelah Hapus Lock File
**Solusi:**
1. **Restart komputer** untuk clear semua process
2. **Cek Task Manager** untuk memastikan tidak ada java.exe yang masih berjalan
3. **Hapus seluruh folder `.gradle`** (akan di-rebuild otomatis):
   ```bash
   rmdir /s /q "%USERPROFILE%\.gradle"
   ```
4. **Build lagi** setelah restart

### Build Sangat Lambat Setelah Hapus Cache
- Ini normal, Gradle akan rebuild cache
- Build pertama akan lebih lambat
- Build selanjutnya akan lebih cepat

## Pencegahan

Untuk mencegah masalah ini di masa depan:

1. **Selalu stop Gradle daemon** sebelum tutup aplikasi:
   ```bash
   cd android
   gradlew --stop
   ```

2. **Jangan force close** Flutter/Android Studio saat sedang build

3. **Tunggu build selesai** sebelum menjalankan build lagi

4. **Gunakan `flutter clean`** jika ada masalah build

## Catatan Penting

- Lock file adalah mekanisme normal Gradle untuk mencegah multiple build bersamaan
- Masalah terjadi jika build sebelumnya tidak selesai dengan benar (crash, force close, dll)
- Hapus lock file aman dilakukan jika tidak ada build yang sedang berjalan
- Setelah hapus lock file, build pertama akan lebih lambat karena rebuild cache
