# Perbaikan Error: API Key Expired

Dokumen ini menjelaskan cara memperbaiki error **"API key expired. Please renew the API key"** yang muncul saat login atau menggunakan aplikasi.

---

## Penyebab Error

Error ini muncul karena:
1. **Google Maps API key expired** atau tidak valid
2. **Billing tidak aktif** di Google Cloud Console
3. **Maps SDK tidak diaktifkan** untuk API key tersebut
4. **API key tidak memiliki izin** untuk Maps SDK

---

## Solusi: Buat API Key Baru dan Aktifkan Billing

### Langkah 1: Buka Google Cloud Console

1. Buka **https://console.cloud.google.com/**
2. Login dengan akun Google yang sama dengan Firebase project Anda
3. Pastikan project yang dipilih adalah **syafiul-traka**

### Langkah 2: Aktifkan Billing (PENTING!)

**Google Maps memerlukan billing yang aktif**, meskipun ada free tier $200 per bulan.

1. **Klik icon hamburger menu (☰)** di pojok kiri atas Google Cloud Console untuk membuka menu utama
2. Di menu utama, scroll ke bawah dan cari **"Billing"** (atau **"Penagihan"**) — ini adalah menu utama, bukan di dalam submenu "APIs & Services"
3. Klik **"Billing"** untuk membuka halaman billing
4. **Alternatif:** Anda juga bisa langsung mengakses halaman billing dengan URL: **https://console.cloud.google.com/billing**

5. **Jika sudah ada billing account** (seperti yang terlihat di halaman "Your billing accounts"):
   - Pastikan salah satu billing account sudah **linked** ke project **syafiul-traka**
   - Untuk mengecek: Klik tab **"Your projects"** di halaman billing
   - Cari project **"syafiul-traka"** dan pastikan ada billing account yang terhubung
   - Jika belum terhubung: Klik project **"syafiul-traka"** → Klik **"Change billing account"** → Pilih billing account yang ingin digunakan

6. **Jika belum ada billing account:**
   - Klik tombol **"+ Create account"** di halaman "Your billing accounts"
   - Ikuti langkah untuk menambahkan kartu kredit/debit
   - **Catatan:** Free tier $200 per bulan biasanya cukup untuk development dan penggunaan awal
   - Setelah dibuat, pastikan billing account sudah **linked** ke project **syafiul-traka**

### Langkah 3: Aktifkan Maps SDK

1. Di menu kiri, klik **"APIs & Services"** → **"Library"** (atau **"API & Layanan"** → **"Pustaka"**)
2. Cari **"Maps SDK for Android"** dan klik
3. Klik tombol **"Enable"** (atau **"Aktifkan"**)
4. Tunggu sampai status menjadi **"Enabled"**

### Langkah 4: Gunakan API Key yang Ada atau Buat Baru

**PENTING: Jangan Hapus API Key atau Service Accounts yang Sudah Ada!**

- **API Keys yang sudah ada** (seperti "Android_traka" dan "ios_traka") **TIDAK perlu dihapus**. Anda bisa:
  - Menggunakan API key yang sudah ada dan memperbaikinya (tambahkan restrictions)
  - Atau membuat API key baru jika diperlukan
  
- **Service Accounts** (seperti "App Engine default service account", "Compute Engine default service account", "firebase-adminsdk") **JANGAN DIHAPUS** karena:
  - Ini adalah service accounts default yang penting untuk Firebase dan Google Cloud
  - Menghapusnya bisa menyebabkan aplikasi tidak berfungsi
  - Service accounts ini digunakan oleh Firebase untuk berbagai layanan

**Rekomendasi:** Gunakan API key **"Android_traka"** yang sudah ada (yang memiliki green checkmark) dan pastikan restrictions-nya sudah benar. Jika perlu, buat API key baru sebagai backup.

---

### Langkah 4A: Perbaiki API Key yang Sudah Ada (Rekomendasi)

Jika Anda melihat API key **"Android_traka"** dengan green checkmark, gunakan yang ini:

1. Klik pada API key **"Android_traka"** untuk membuka pengaturan
2. Klik **"Show key"** untuk melihat API key-nya
3. Salin API key tersebut
4. Pastikan restrictions sudah benar (lihat Langkah 5)

---

### Langkah 4B: Buat API Key Baru (Jika Diperlukan)

**Cara Membuat API Key Baru (Langkah Terperinci):**

1. **Buka halaman Credentials:**
   - Di Google Cloud Console, klik menu kiri **"APIs & Services"** → **"Credentials"** (atau **"API & Layanan"** → **"Kredensial"**)
   - Pastikan project yang dipilih adalah **"syafiul-traka"**

2. **Buat API Key:**
   - Di bagian atas halaman, klik tombol **"+ CREATE CREDENTIALS"** (atau **"+ BUAT KREDENSIAL"**)
   - Dari dropdown yang muncul, pilih **"API key"**

3. **Salin API Key:**
   - Setelah API key dibuat, akan muncul popup/dialog yang menampilkan API key baru
   - **PENTING:** Segera **salin API key** tersebut (contoh: `AIzaSy...`)
   - API key biasanya dimulai dengan `AIzaSy` diikuti karakter lainnya
   - **Jangan tutup popup** sebelum menyalin API key!

4. **Tutup popup:**
   - Setelah menyalin API key, klik **"Close"** atau **"Tutup"** untuk menutup popup
   - API key baru akan muncul di daftar "API keys" dengan nama default seperti "API key 1" atau "API key 2"

5. **Rename API Key (Opsional tapi Disarankan):**
   - Klik pada API key yang baru dibuat untuk membuka pengaturan
   - Di bagian **"Name"**, ganti nama default dengan nama yang lebih jelas, misalnya: **"Traka_Maps_Android"**
   - Klik **"Save"** untuk menyimpan perubahan nama

**Catatan:** API key yang baru dibuat akan muncul dengan **segitiga kuning** (warning) karena belum memiliki restrictions. Ini normal dan akan diperbaiki di Langkah 5.

### Langkah 5: Restrict API Key (Disarankan untuk Keamanan)

1. Klik pada API key yang akan digunakan (baik yang baru dibuat atau "Android_traka")
2. Di bagian **"Application restrictions"**, pilih **"Android apps"**
3. Klik **"+ Add an item"**
4. Masukkan:
   - **Package name:** `com.example.traka`
   - **SHA-1 certificate fingerprint:** (opsional, bisa ditambahkan nanti)
5. Di bagian **"API restrictions"**, pastikan **"Restrict key"** dipilih
6. Centang **"Maps SDK for Android"** (pastikan sudah diaktifkan di Langkah 3)
7. Klik **"Save"**
8. **Catatan:** Setelah restrictions ditambahkan, segitiga kuning biasanya akan hilang

### Langkah 6: Update API Key di AndroidManifest.xml

1. Buka file **`android/app/src/main/AndroidManifest.xml`**
2. Cari bagian:
   ```xml
   <meta-data
       android:name="com.google.android.geo.API_KEY"
       android:value="AIzaSyA8eb49Svf-FpbWN3qbfglMB885VoSi2IE" />
   ```
3. **Ganti** nilai `android:value` dengan API key baru yang Anda buat
4. **Simpan** file

### Langkah 7: Clean dan Rebuild

1. **Stop aplikasi** jika sedang berjalan
2. **Clean build:**
   ```bash
   flutter clean
   ```
3. **Get dependencies:**
   ```bash
   flutter pub get
   ```
4. **Rebuild aplikasi:**
   ```bash
   flutter run
   ```

---

## Verifikasi

Setelah memperbarui API key:

1. **Jalankan aplikasi** dan coba login
2. **Cek apakah error sudah hilang**
3. **Masuk ke halaman penumpang** dan pastikan maps muncul
4. **Cek log** di terminal untuk memastikan tidak ada error terkait API key

---

## Troubleshooting

### Error masih muncul setelah update API key

1. **Pastikan billing aktif:**
   - Buka Google Cloud Console → Klik hamburger menu (☰) → **Billing**
   - Atau langsung akses: **https://console.cloud.google.com/billing**
   - Pastikan ada billing account yang aktif dan sudah linked ke project

2. **Pastikan Maps SDK sudah diaktifkan:**
   - Buka Google Cloud Console → APIs & Services → Library
   - Cari "Maps SDK for Android" dan pastikan status "Enabled"

3. **Cek API key restrictions:**
   - Buka Google Cloud Console → APIs & Services → Credentials
   - Klik API key yang digunakan
   - Pastikan "Maps SDK for Android" ada di daftar API restrictions

4. **Cek log detail:**
   - Buka terminal dan jalankan `flutter run`
   - Cari pesan error yang lebih detail tentang API key

### API key tidak berfungsi di production

- Pastikan **package name** di restrictions sesuai dengan package name aplikasi
- Jika menggunakan signed APK, tambahkan **SHA-1 fingerprint** ke restrictions
- Untuk mendapatkan SHA-1:
  ```bash
  keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
  ```

---

## Catatan Penting

- **Free tier $200 per bulan** biasanya cukup untuk development dan testing
- Setelah melewati free tier, biaya mulai dari **$0.007 per map load**
- Monitor penggunaan di Google Cloud Console → APIs & Services → Dashboard
- Jika tidak ingin menggunakan Google Maps, bisa dihapus dari `AndroidManifest.xml` dan fitur maps di halaman penumpang akan tidak berfungsi (tapi login tetap bisa)

---

Dengan mengikuti langkah di atas, error "API key expired" seharusnya teratasi dan aplikasi bisa login serta menampilkan maps dengan baik.
