# Setup Google Maps untuk Halaman Penumpang

Dokumen ini menjelaskan cara mengatur Google Maps API key agar fitur maps di halaman penumpang berfungsi dengan baik.

---

## Ringkasan

Halaman penumpang menggunakan **Google Maps** untuk menampilkan:
- Peta dengan lokasi penumpang (titik biru)
- Toggle antara tampilan normal dan satelit
- Marker lokasi saat ini

Agar Google Maps berfungsi, Anda perlu:
1. Membuat **Google Maps API key** di Google Cloud Console
2. Menambahkan API key ke konfigurasi Android dan iOS

---

## 1. Membuat Google Maps API Key

### Langkah 1: Buka Google Cloud Console

1. Buka browser dan masuk ke: **https://console.cloud.google.com/**
2. Login dengan akun Google yang sama dengan Firebase project Anda.
3. Pastikan **project** yang dipilih adalah project Firebase Traka Anda (misalnya **syafiul-traka**).

### Langkah 2: Aktifkan Google Maps SDK

1. Di menu kiri, klik **"APIs & Services"** → **"Library"** (atau **"API & Layanan"** → **"Pustaka"**).
2. Cari **"Maps SDK for Android"** dan klik.
3. Klik tombol **"Enable"** (atau **"Aktifkan"**).
4. Ulangi untuk **"Maps SDK for iOS"** (jika akan deploy ke iOS).

### Langkah 3: Buat API Key

1. Di menu kiri, klik **"APIs & Services"** → **"Credentials"** (atau **"API & Layanan"** → **"Kredensial"**).
2. Klik tombol **"+ CREATE CREDENTIALS"** (atau **"+ BUAT KREDENSIAL"**).
3. Pilih **"API key"**.
4. Setelah API key dibuat, akan muncul dialog. **Salin API key** tersebut (contoh: `AIzaSy...`).
5. **Opsional:** Klik **"Restrict key"** untuk membatasi penggunaan API key:
   - **Application restrictions:** Pilih **"Android apps"** atau **"iOS apps"** sesuai platform.
   - **API restrictions:** Pilih **"Restrict key"** dan centang **"Maps SDK for Android"** dan/atau **"Maps SDK for iOS"**.

---

## 2. Konfigurasi Android

### Langkah 1: Tambahkan API Key ke AndroidManifest.xml

1. Buka file **`android/app/src/main/AndroidManifest.xml`**.
2. Cari bagian `<application>` dan tambahkan meta-data untuk Google Maps API key:

```xml
<meta-data
    android:name="com.google.android.geo.API_KEY"
    android:value="YOUR_GOOGLE_MAPS_API_KEY" />
```

**Contoh lengkap:**

```xml
<application
    android:label="traka"
    android:name="${applicationName}"
    android:icon="@mipmap/ic_launcher">
    <!-- ... activity lainnya ... -->
    
    <!-- Google Maps API Key -->
    <meta-data
        android:name="com.google.android.geo.API_KEY"
        android:value="AIzaSyC_your_actual_api_key_here" />
</application>
```

3. **Ganti** `YOUR_GOOGLE_MAPS_API_KEY` dengan API key yang Anda salin dari Google Cloud Console.
4. **Simpan** file.

---

## 3. Konfigurasi iOS (Opsional - jika deploy ke iOS)

### Langkah 1: Tambahkan API Key ke AppDelegate.swift

1. Buka file **`ios/Runner/AppDelegate.swift`**.
2. Tambahkan import dan inisialisasi Google Maps di dalam fungsi `application`:

```swift
import UIKit
import Flutter
import GoogleMaps

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GMSServices.provideAPIKey("YOUR_GOOGLE_MAPS_API_KEY")
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
```

3. **Ganti** `YOUR_GOOGLE_MAPS_API_KEY` dengan API key yang sama seperti di Android.
4. **Simpan** file.

**Catatan:** Jika file `AppDelegate.swift` tidak ada, buat file baru dengan nama tersebut di folder **`ios/Runner/`**.

---

## 4. Verifikasi Setup

1. **Jalankan aplikasi:**
   ```bash
   flutter run
   ```

2. **Login sebagai penumpang** dan masuk ke halaman penumpang.

3. **Cek apakah maps muncul:**
   - Maps harus menampilkan peta (normal atau satelit).
   - Titik biru harus muncul di lokasi GPS handphone Anda.
   - Toggle map type (icon kotak di kanan atas) harus berfungsi.

4. **Jika maps tidak muncul atau error:**
   - Pastikan API key sudah benar di `AndroidManifest.xml`.
   - Pastikan **Maps SDK for Android** sudah diaktifkan di Google Cloud Console.
   - Cek log di terminal untuk pesan error (misalnya "API key not valid").
   - Pastikan billing sudah diaktifkan di Google Cloud Console (Google Maps memerlukan billing, meskipun ada free tier).

---

## 5. Troubleshooting

### Error: "API key not valid"

- Pastikan API key sudah benar di `AndroidManifest.xml` (tidak ada spasi atau karakter tambahan).
- Pastikan **Maps SDK for Android** sudah diaktifkan di Google Cloud Console.
- Pastikan billing sudah diaktifkan di Google Cloud Console.

### Maps tidak muncul (blank screen)

- Cek log di terminal untuk error detail.
- Pastikan izin lokasi sudah diberikan ke aplikasi.
- Pastikan koneksi internet aktif (Google Maps memerlukan internet).

### Error di iOS: "Google Maps SDK not found"

- Pastikan sudah menambahkan Google Maps SDK di `AppDelegate.swift`.
- Pastikan sudah menjalankan `pod install` di folder `ios/`:
  ```bash
  cd ios
  pod install
  cd ..
  ```

---

## 6. Biaya Google Maps

Google Maps memiliki **free tier** yang cukup untuk pengembangan dan penggunaan awal:
- **$200 credit per bulan** untuk Maps SDK (setara dengan ~28,000 peta loads per hari).
- Setelah melewati free tier, biaya mulai dari **$0.007 per load**.

Untuk detail lengkap, lihat: **https://mapsplatform.google.com/pricing/**

---

Dengan ini, Google Maps di halaman penumpang akan berfungsi dengan baik. Pastikan API key sudah diatur sebelum deploy ke production.
