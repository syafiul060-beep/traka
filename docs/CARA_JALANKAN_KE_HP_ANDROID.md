# Cara Menjalankan Aplikasi Flutter ke HP Android

Panduan lengkap untuk menjalankan aplikasi Traka ke HP Android fisik.

---

## Prerequisites

Sebelum mulai, pastikan:

- ✅ **HP Android sudah diaktifkan** dan tidak dalam mode sleep
- ✅ **USB Debugging sudah diaktifkan** di HP Android
- ✅ **Kabel USB** untuk menghubungkan HP ke komputer
- ✅ **Flutter SDK sudah terinstall** dan dikonfigurasi dengan benar
- ✅ **Android SDK sudah terinstall** (biasanya otomatis dengan Flutter)

---

## Langkah 1: Aktifkan USB Debugging di HP Android

### Untuk Android 8.0 (Oreo) ke atas:

1. **Buka Settings** → **About phone**
2. **Tap "Build number" 7 kali** sampai muncul pesan "You are now a developer!"
3. **Kembali ke Settings** → **System** → **Developer options**
4. **Aktifkan "Developer options"** (toggle ON)
5. **Aktifkan "USB debugging"** (toggle ON)
6. **Jika muncul dialog "Allow USB debugging?"** → centang **"Always allow from this computer"** → klik **"OK"**

### Untuk Android versi lama:

1. **Buka Settings** → **About phone**
2. **Tap "Build number" 7 kali**
3. **Kembali ke Settings** → **Developer options**
4. **Aktifkan "USB debugging"**

---

## Langkah 2: Hubungkan HP ke Komputer

1. **Hubungkan HP Android ke komputer** menggunakan kabel USB.
2. **Di HP Android**, jika muncul dialog **"Allow USB debugging?"**:
   - Centang **"Always allow from this computer"**
   - Klik **"OK"** atau **"Allow"**
3. **Pilih mode koneksi USB** (jika diminta):
   - Pilih **"File Transfer"** atau **"MTP"** (bukan "Charging only")

---

## Langkah 3: Cek Apakah HP Terdeteksi

1. **Buka Command Prompt atau PowerShell**.
2. **Masuk ke folder project:**
   ```bash
   cd "C:\Users\syafi\OneDrive\Dokumen\Traka\traka"
   ```

3. **Cek apakah HP terdeteksi:**
   ```bash
   flutter devices
   ```

4. **Seharusnya muncul output seperti:**
   ```
   Connected devices:
   SM A1234 (mobile) • R58M123456 • android-arm64 • Android 13 (API 33)
   ```
   (Nama device dan ID akan berbeda sesuai HP Anda)

**Jika HP tidak muncul:**
- Pastikan USB debugging sudah aktif
- Coba cabut dan pasang kembali kabel USB
- Coba kabel USB lain
- Restart HP Android
- Cek apakah driver USB sudah terinstall di komputer

---

## Langkah 4: Jalankan Aplikasi ke HP

### Opsi 1: Jalankan langsung (Recommended)

1. **Pastikan HP sudah terdeteksi** (cek dengan `flutter devices`).
2. **Jalankan aplikasi:**
   ```bash
   flutter run
   ```

3. **Tunggu sampai aplikasi terinstall dan terbuka** di HP Android (biasanya 1-3 menit pertama kali).

### Opsi 2: Jalankan dengan device ID spesifik

Jika ada beberapa device terdeteksi, pilih device tertentu:

```bash
flutter run -d <device-id>
```

Contoh:
```bash
flutter run -d R58M123456
```
(Ganti `<device-id>` dengan ID device yang muncul di `flutter devices`)

### Opsi 3: Build dan install APK

Jika ingin build APK terlebih dahulu:

1. **Build APK:**
   ```bash
   flutter build apk
   ```

2. **APK akan tersimpan di:**
   ```
   build\app\outputs\flutter-apk\app-release.apk
   ```

3. **Transfer APK ke HP** (via USB, email, atau cloud storage).

4. **Install APK di HP:**
   - Buka file manager di HP
   - Cari file `app-release.apk`
   - Tap untuk install
   - Izinkan "Install from unknown sources" jika diminta

---

## Langkah 5: Hot Reload & Hot Restart

Setelah aplikasi berjalan di HP:

- **Hot Reload** (refresh cepat, pertahankan state):
  - Tekan **`r`** di Command Prompt
  - Atau klik tombol **Hot Reload** di VS Code/Android Studio

- **Hot Restart** (restart aplikasi, reset state):
  - Tekan **`R`** (huruf besar) di Command Prompt
  - Atau klik tombol **Hot Restart** di VS Code/Android Studio

- **Stop aplikasi:**
  - Tekan **`q`** di Command Prompt

---

## Troubleshooting

### Error: "No devices found"

**Solusi:**
1. **Cek USB debugging sudah aktif** di HP Android.
2. **Cek kabel USB** (coba kabel lain).
3. **Restart HP Android**.
4. **Cek driver USB** di komputer:
   - Windows: Device Manager → cek apakah ada "Android Device" atau "ADB Interface"
   - Jika ada tanda seru kuning, install driver Android USB

### Error: "ADB not found" atau "adb: command not found"

**Solusi:**
1. **Pastikan Android SDK sudah terinstall**:
   ```bash
   flutter doctor
   ```
2. **Jika Android SDK tidak terdeteksi**, install Android Studio dan Android SDK.
3. **Tambahkan Android SDK ke PATH** (jika perlu):
   - Lokasi default: `C:\Users\<username>\AppData\Local\Android\Sdk\platform-tools`
   - Tambahkan ke PATH environment variable

### Error: "USB debugging authorization"

**Solusi:**
1. **Di HP Android**, muncul dialog "Allow USB debugging?"
2. **Centang "Always allow from this computer"**.
3. **Klik "OK"** atau **"Allow"**.

### Aplikasi crash atau tidak bisa dibuka

**Solusi:**
1. **Cek log error:**
   ```bash
   flutter run --verbose
   ```
2. **Pastikan semua dependencies sudah diinstall:**
   ```bash
   flutter pub get
   ```
3. **Clean build:**
   ```bash
   flutter clean
   flutter pub get
   flutter run
   ```

### HP tidak muncul di `flutter devices` tapi muncul di Device Manager

**Solusi:**
1. **Install Android USB Driver**:
   - Download dari: https://developer.android.com/studio/run/win-usb
   - Atau install via Android Studio → SDK Manager → SDK Tools → Google USB Driver

2. **Update driver di Device Manager:**
   - Buka Device Manager
   - Cari device Android (mungkin muncul sebagai "Unknown device")
   - Right-click → Update driver → Browse → pilih folder driver yang sudah diinstall

---

## Tips

1. **Gunakan kabel USB berkualitas** untuk koneksi yang stabil.
2. **Jangan cabut kabel USB** saat aplikasi sedang di-build atau di-deploy.
3. **Aktifkan "Stay awake"** di Developer Options agar HP tidak sleep saat development.
4. **Gunakan WiFi debugging** (Android 11+) jika kabel USB bermasalah:
   - Aktifkan "Wireless debugging" di Developer Options
   - Pair dengan komputer menggunakan IP address dan port

---

## Perintah Cepat

```bash
# Cek devices yang terdeteksi
flutter devices

# Jalankan aplikasi
flutter run

# Jalankan dengan device ID spesifik
flutter run -d <device-id>

# Build APK
flutter build apk

# Clean build
flutter clean

# Install dependencies
flutter pub get

# Cek status Flutter
flutter doctor
```

---

## Setelah Aplikasi Berjalan

Setelah aplikasi berjalan di HP Android:

1. **Test fitur registrasi:**
   - Buka aplikasi → halaman registrasi
   - Isi email → klik tombol refresh untuk kirim kode verifikasi
   - Cek email untuk kode verifikasi

2. **Monitor log:**
   - Log akan muncul di Command Prompt
   - Atau gunakan `flutter logs` di terminal lain

3. **Hot reload saat development:**
   - Edit kode di editor
   - Tekan `r` di Command Prompt untuk hot reload
   - Perubahan akan langsung terlihat di HP

---

Jika masih ada masalah, beri tahu saya dengan:
- Screenshot error (jika ada)
- Output dari `flutter devices`
- Output dari `flutter doctor`
