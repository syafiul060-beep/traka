# Cara Build Flutter Tanpa Gradle Daemon (Solusi Out of Memory)

## Masalah
Build Flutter gagal dengan error "Out of Memory" meskipun sudah mengurangi memory allocation.

## Solusi: Build Tanpa Daemon

Gradle daemon menggunakan memory yang cukup besar. Build tanpa daemon akan menggunakan lebih sedikit memory, meskipun lebih lambat.

### Langkah 1: Stop Semua Gradle Daemon
```bash
cd android
gradlew --stop
cd ..
```

### Langkah 2: Build Tanpa Daemon

**Opsi A: Build APK langsung tanpa daemon**
```bash
cd android
gradlew assembleDebug --no-daemon
cd ..
```

**Opsi B: Build via Flutter dengan environment variable**
```bash
# Windows PowerShell
$env:GRADLE_OPTS="-Dorg.gradle.daemon=false"
flutter run

# Atau Windows CMD
set GRADLE_OPTS=-Dorg.gradle.daemon=false
flutter run
```

**Opsi C: Build release (lebih ringan)**
```bash
flutter build apk --release
```

### Langkah 3: Install APK yang Sudah Dibuild

Jika build berhasil, install APK ke device:
```bash
# Cek device terhubung
flutter devices

# Install APK
flutter install
```

## Alternatif: Build di WSL atau Linux VM

Jika Windows terus bermasalah dengan memory:
1. Install WSL2 (Windows Subsystem for Linux)
2. Install Flutter di WSL2
3. Build dari WSL2 (biasanya lebih stabil)

## Catatan Penting

- Build tanpa daemon akan **lebih lambat** (bisa 2-3x lebih lama)
- Tapi akan menggunakan **lebih sedikit memory**
- Cocok untuk komputer dengan RAM terbatas
- Setelah build berhasil, APK bisa diinstall langsung ke device

## Troubleshooting

### Masih Error Setelah Build Tanpa Daemon
1. **Tutup semua aplikasi** termasuk browser
2. **Restart komputer** untuk clear memory
3. **Tingkatkan paging file** (lihat `docs/SOLUSI_OUT_OF_MEMORY.md`)
4. **Cek RAM:** Pastikan minimal 4 GB available

### Build Sangat Lambat
- Ini normal saat build tanpa daemon
- Pertimbangkan upgrade RAM atau gunakan komputer lain
- Atau build release yang lebih cepat
