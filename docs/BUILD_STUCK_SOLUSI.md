# Solusi Build Stuck Lebih dari 1 Jam

## Masalah
Build Flutter sudah berjalan lebih dari 1 jam dan masih di "Running Gradle task 'assembleDebug'..."

## Tindakan Segera

### 1. Cancel Build yang Stuck
**Tekan `Ctrl + C` di terminal** untuk cancel build yang sedang berjalan.

### 2. Stop Semua Process Gradle
```bash
taskkill /F /IM java.exe
cd android
gradlew --stop
cd ..
```

### 3. Hapus Build Folder
```bash
rmdir /s /q android\app\build
rmdir /s /q build
```

## Solusi: Build dengan Cara Lebih Efisien

### Opsi 1: Build Release (Lebih Cepat dan Stabil)

Build release biasanya lebih cepat dan stabil:
```bash
flutter build apk --release
```

Setelah build selesai, install:
```bash
flutter install --release
```

**Keuntungan:**
- Lebih cepat (5-10 menit)
- Lebih stabil
- File lebih kecil
- Cocok untuk testing

### Opsi 2: Build Tanpa Daemon (Lebih Stabil)

Build tanpa daemon akan lebih lambat tapi lebih stabil:
```bash
cd android
gradlew assembleDebug --no-daemon
cd ..
flutter install
```

### Opsi 3: Naikkan Memory (Jika RAM Cukup)

Jika komputer punya RAM cukup (8 GB+), naikkan memory di `android/gradle.properties`:
```properties
org.gradle.jvmargs=-Xmx1536m -XX:MaxMetaspaceSize=512m -XX:ReservedCodeCacheSize=128m -Dfile.encoding=UTF-8
```

Lalu:
```bash
cd android
gradlew --stop
cd ..
flutter clean
flutter pub get
flutter run
```

### Opsi 4: Build Incremental (Skip Clean)

Jangan clean jika tidak perlu:
```bash
# Skip flutter clean
flutter pub get
flutter run
```

## Langkah yang Direkomendasikan

### Langkah 1: Cancel Build
Tekan `Ctrl + C` di terminal

### Langkah 2: Stop Semua Process
```bash
taskkill /F /IM java.exe
cd android
gradlew --stop
cd ..
```

### Langkah 3: Hapus Build Folder
```bash
rmdir /s /q android\app\build
rmdir /s /q build
```

### Langkah 4: Cek Disk Space
Pastikan ada minimal **10 GB free space**:
```bash
dir C:\ | findstr "bytes free"
```

### Langkah 5: Build Release (Paling Cepat)
```bash
flutter build apk --release
flutter install --release
```

## Mengapa Build Stuck?

### Kemungkinan Penyebab:
1. **Memory tidak cukup** - Build sangat lambat karena GC terus-menerus
2. **Disk space penuh** - Tidak bisa menulis file
3. **Disk I/O lambat** - Hard disk lama atau penuh
4. **Network issue** - Download dependencies stuck
5. **Gradle daemon corrupt** - Process hang

### Tanda Build Stuck:
- Build lebih dari **30 menit** tanpa progress
- CPU usage rendah (< 10%)
- Memory usage stabil (tidak naik)
- Tidak ada aktivitas disk

## Pencegahan

### 1. Gunakan Build Release untuk Testing
```bash
flutter build apk --release
flutter install --release
```

### 2. Jangan Clean Terlalu Sering
Hanya clean jika benar-benar perlu:
- Ada masalah build yang tidak bisa diselesaikan
- Mengubah native code
- Setelah update Flutter SDK

### 3. Monitor Build Progress
Jika build lebih dari 30 menit tanpa progress, cancel dan coba lagi.

### 4. Gunakan Hot Reload untuk Development
Untuk perubahan kecil, gunakan hot reload (`r`) daripada rebuild.

## Catatan Penting

- **Build pertama memang lambat** (15-20 menit normal)
- **Build lebih dari 30 menit** kemungkinan stuck
- **Build release lebih cepat** daripada debug
- **Jangan biarkan build lebih dari 1 jam** - cancel dan coba lagi

## Setelah Cancel

1. **Stop semua process** (perintah di atas)
2. **Hapus build folder** (perintah di atas)
3. **Coba build release** (lebih cepat dan stabil)
4. **Atau naikkan memory** jika RAM cukup
