# Build dan Jalankan Traka

## Error: "Creation failed, path = 'D:\Traka\pub-cache \hosted-hashes'"

Penyebab: variabel **PUB_CACHE** masih ter-set (dari session lama atau dari Variabel Lingkungan Windows) dan nilainya salah — ada **spasi** di path (`pub-cache `), sehingga Flutter gagal membuat folder.

### Perbaikan

**1. Hapus PUB_CACHE untuk session ini (Command Prompt yang sedang dipakai):**

```batch
set PUB_CACHE=
flutter pub get
flutter run
```

**2. Jika tetap gagal, hapus/sesuaikan di Variabel Lingkungan Windows:**

- Tekan **Win + R** → ketik `sysdm.cpl` → Enter → tab **Advanced** → **Environment Variables**.
- Di **User variables** atau **System variables**, cari **PUB_CACHE**.
  - Hapus variabel **PUB_CACHE**, **atau**
  - Edit nilainya jadi persis: `D:\Traka\pub-cache` (tanpa spasi di depan/belakang).
- Tutup semua Command Prompt / terminal, buka lagi, lalu di `D:\Traka\traka` jalankan:

```batch
flutter pub get
flutter run
```

**3. Tanpa PUB_CACHE (disarankan)**

Lebih aman tidak pakai PUB_CACHE. Pakai pub cache default Flutter (di C:). Proyek di D: sudah aman berkat `kotlin.incremental=false` di `android/gradle.properties`.

---

## Jika Gradle daemon crash (JVM out of memory)

Gejala: "Gradle build daemon disappeared unexpectedly", dan ada file `android/hs_err_pid*.log` berisi "insufficient memory" atau "Native memory allocation failed".

Penyebab: RAM terbatas (mis. 15GB); heap Gradle 4GB + native memory kompilator JVM melebihi yang tersedia.

Sudah diset di `android/gradle.properties`: heap lebih kecil (2GB), worker 1. Setelah mengubah, **hentikan semua daemon Gradle** lalu coba lagi:

```batch
cd D:\Traka\traka\android
gradlew --stop
cd ..
flutter run
```

Saat build, tutup aplikasi lain yang banyak memakai RAM (browser dengan banyak tab, Android Studio, dll).

---

## Jika instal ke HP gagal (ADB exit code 1)

- Pastikan kabel USB terpasang dan **USB debugging** di HP diizinkan (cek "Izinkan debugging USB?" di HP).
- Coba cabut-pasang kabel, lalu jalankan lagi: `flutter run`.
- Atau jalankan di emulator: `flutter run -d emulator-5554` (atau pilih device dengan `flutter devices` lalu `flutter run -d <device_id>`).
- Jika masih gagal: di HP buka **Pengaturan > Aplikasi > Traka** (jika sudah pernah terpasang), uninstall, lalu jalankan lagi `flutter run`.
