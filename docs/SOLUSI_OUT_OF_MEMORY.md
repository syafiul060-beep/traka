# Solusi Error "Out of Memory" saat Build Flutter

## Masalah
Error saat build Flutter:
```
FAILURE: Build failed with an exception.
Unable to start the daemon process.
There is insufficient memory for the Java Runtime Environment to continue.
The paging file is too small for this operation to complete.
Out of memory.
```

## Penyebab
1. **RAM tidak cukup** untuk Gradle build process
2. **Paging file Windows terlalu kecil** untuk handle memory allocation
3. **Terlalu banyak aplikasi** yang menggunakan memory bersamaan

## Solusi yang Sudah Diterapkan

### 1. Mengurangi Memory Allocation Gradle
File `android/gradle.properties` sudah diupdate dengan:
- `-Xmx512m` (dari 1024m) - Maximum heap size dikurangi
- `-XX:MaxMetaspaceSize=256m` (dari 384m) - Metaspace dikurangi
- `-XX:ReservedCodeCacheSize=64m` (dari 96m) - Code cache dikurangi
- `org.gradle.parallel=false` - Disable parallel build untuk mengurangi memory usage
- `org.gradle.configureondemand=false` - Disable configure on demand

### 2. Langkah Selanjutnya

#### Langkah 1: Tutup Aplikasi Lain
**PENTING:** Tutup semua aplikasi yang tidak perlu:
- Browser (Chrome, Firefox, dll)
- Android Studio (jika tidak digunakan)
- Aplikasi lain yang menggunakan banyak memory
- Cek Task Manager → Memory usage

#### Langkah 2: Stop Gradle Daemon
```bash
cd android
gradlew --stop
cd ..
```

#### Langkah 3: Clean Build
```bash
flutter clean
flutter pub get
```

#### Langkah 4: Build dengan Memory Terbatas
```bash
flutter run
```

Jika masih error, coba build tanpa daemon:
```bash
cd android
gradlew assembleDebug --no-daemon
cd ..
```

### 3. Solusi Jangka Panjang: Tingkatkan Paging File Windows

**Langkah-langkah:**

1. **Buka System Properties:**
   - Tekan `Win + R`
   - Ketik `sysdm.cpl`
   - Tekan Enter

2. **Buka Virtual Memory Settings:**
   - Tab **Advanced**
   - Klik **Settings** di bagian Performance
   - Tab **Advanced**
   - Klik **Change** di bagian Virtual memory

3. **Set Paging File:**
   - **Uncheck** "Automatically manage paging file size for all drives"
   - Pilih drive **C:**
   - Pilih **Custom size**
   - **Initial size:** `4096` MB (4 GB)
   - **Maximum size:** `8192` MB (8 GB)
   - Klik **Set**
   - Klik **OK**

4. **Restart Komputer:**
   - Setelah set paging file, **restart komputer** agar perubahan berlaku

5. **Setelah Restart:**
   - Coba build lagi: `flutter clean && flutter pub get && flutter run`

### 4. Alternatif: Build Release (Lebih Ringan)

Jika debug build masih gagal, coba build release:
```bash
flutter build apk --release
```

Atau install release build:
```bash
flutter install --release
```

### 5. Cek Memory Usage

**Via Task Manager:**
1. Tekan `Ctrl + Shift + Esc`
2. Tab **Performance** → **Memory**
3. Cek **Available** memory
4. Jika kurang dari 2 GB, tutup aplikasi lain

**Via Command Prompt:**
```bash
wmic OS get TotalVisibleMemorySize,FreePhysicalMemory
```

### 6. Solusi Ekstrem: Kurangi Memory Lebih Lanjut

Jika masih gagal, edit `android/gradle.properties`:
```properties
org.gradle.jvmargs=-Xmx256m -XX:MaxMetaspaceSize=128m -XX:ReservedCodeCacheSize=32m -Dfile.encoding=UTF-8
```

**Catatan:** Ini akan membuat build lebih lambat tapi menggunakan lebih sedikit memory.

## Troubleshooting

### Error Masih Terjadi Setelah Semua Langkah
1. **Restart komputer** untuk clear memory
2. **Tutup semua aplikasi** termasuk browser
3. **Cek RAM:** Pastikan RAM minimal 4 GB (disarankan 8 GB)
4. **Cek disk space:** Pastikan ada minimal 10 GB free space di drive C:

### Build Sangat Lambat Setelah Kurangi Memory
- Ini normal karena memory dikurangi
- Pertimbangkan upgrade RAM jika sering terjadi
- Atau gunakan build release yang lebih ringan

### Paging File Tidak Bisa Diubah
- Pastikan login sebagai Administrator
- Atau gunakan Command Prompt sebagai Administrator:
  ```bash
  # Run as Administrator
  wmic computersystem where name="%computername%" set AutomaticManagedPagefile=False
  ```

## Rekomendasi

**Untuk Development:**
- Minimal RAM: **8 GB**
- Paging file: **4-8 GB**
- Tutup aplikasi tidak perlu saat build

**Untuk Production Build:**
- Gunakan `flutter build apk --release` (lebih ringan)
- Atau build di CI/CD dengan resource lebih besar

## Setelah Memperbaiki

1. **Test build:**
   ```bash
   flutter clean
   flutter pub get
   flutter run
   ```

2. **Jika berhasil:**
   - Aplikasi akan ter-install dan jalan di device
   - Chat list driver sudah bisa digunakan

3. **Jika masih error:**
   - Cek log error detail
   - Pertimbangkan upgrade RAM atau paging file lebih besar
   - Atau gunakan komputer lain dengan spec lebih tinggi
