# Solusi Error "packageDebug" Task Failed

## Masalah
Build Flutter gagal dengan error:
```
Execution failed for task ':app:packageDebug'.
> A failure occurred while executing com.android.build.gradle.tasks.PackageAndroidArtifact$IncrementalSplitterRunnable
```

## Penyebab Umum

1. **Memory tidak cukup** saat packaging APK
2. **Disk space tidak cukup** untuk file APK
3. **File terlalu besar** atau ada masalah dengan resources
4. **Gradle cache corrupt** atau lock file masih ada

## Solusi

### Solusi 1: Clean dan Build Lagi

```bash
flutter clean
cd android
gradlew clean
cd ..
flutter pub get
flutter run
```

### Solusi 2: Hapus Build Folder Manual

```bash
# Hapus build folder
rmdir /s /q android\app\build
rmdir /s /q build

# Clean dan build lagi
flutter clean
flutter pub get
flutter run
```

### Solusi 3: Build Tanpa Daemon (Lebih Stabil)

```bash
cd android
gradlew assembleDebug --no-daemon
cd ..
flutter install
```

### Solusi 4: Cek Disk Space

Pastikan ada cukup disk space:
```bash
# Cek free space di drive C:
dir C:\ | findstr "bytes free"
```

Minimal perlu **5 GB free space** untuk build.

### Solusi 5: Naikkan Memory untuk Packaging

Edit `android/gradle.properties`:
```properties
org.gradle.jvmargs=-Xmx1024m -XX:MaxMetaspaceSize=384m -XX:ReservedCodeCacheSize=128m -Dfile.encoding=UTF-8
```

**Catatan:** Hanya jika komputer punya RAM cukup (8 GB+).

### Solusi 6: Disable Split APKs (Jika Masalah dengan Split)

Edit `android/app/build.gradle.kts`, tambahkan di `android` block:
```kotlin
android {
    // ... existing code ...
    
    splits {
        abi {
            isEnable = false
        }
    }
}
```

## Langkah yang Direkomendasikan

1. **Hapus build folder:**
   ```bash
   rmdir /s /q android\app\build
   rmdir /s /q build
   ```

2. **Clean project:**
   ```bash
   flutter clean
   cd android
   gradlew clean
   cd ..
   ```

3. **Stop Gradle daemon:**
   ```bash
   cd android
   gradlew --stop
   cd ..
   ```

4. **Hapus lock file (jika ada):**
   ```bash
   rmdir /s /q "%USERPROFILE%\.gradle\caches\journal-1"
   ```

5. **Get dependencies:**
   ```bash
   flutter pub get
   ```

6. **Build lagi:**
   ```bash
   flutter run
   ```

## Troubleshooting

### Error Masih Terjadi Setelah Semua Langkah
1. **Cek disk space** - Pastikan minimal 5 GB free
2. **Cek memory** - Tutup aplikasi lain yang menggunakan banyak memory
3. **Restart komputer** - Clear semua process dan memory
4. **Coba build release** - Biasanya lebih stabil:
   ```bash
   flutter build apk --release
   ```

### Build Sangat Lambat
- Ini normal setelah clean
- Build pertama akan lambat (15-20 menit)
- Build selanjutnya akan lebih cepat (3-5 menit)

## Catatan Penting

- Error `packageDebug` biasanya terjadi di tahap akhir build
- Sering terkait dengan memory atau disk space
- Clean build folder biasanya menyelesaikan masalah
- Build release biasanya lebih stabil daripada debug
