# Setup Google Directions API

Agar rute perjalanan bisa ditampilkan di peta (garis biru dari asal ke tujuan), **Directions API** harus diaktifkan di Google Cloud Console.

## Jika Rute Tidak Muncul & Tombol Masih Hijau

Saat driver memilih tujuan dan menekan "Rute Perjalanan", namun:
- Rute tidak muncul di peta
- Tombol tetap hijau "Siap Kerja" (seharusnya merah "Selesai Bekerja")

**Penyebab:** Directions API belum diaktifkan atau API key tidak punya akses.

---

## Langkah Aktifkan Directions API

### 1. Buka Google Cloud Console
- Kunjungi [https://console.cloud.google.com](https://console.cloud.google.com)
- Login dengan akun Google
- Pilih project **Traka** (atau project yang dipakai)

### 2. Buka API Library
- Di menu kiri: **APIs & Services** → **Library**
- Atau langsung: [https://console.cloud.google.com/apis/library](https://console.cloud.google.com/apis/library)

### 3. Cari dan Aktifkan Directions API
- Di kotak pencarian, ketik **"Directions API"**
- Klik **Directions API** (dari Google)
- Klik tombol **Enable**

### 4. Cek API Key

1. Buka **APIs & Services** → **Credentials**
2. Di daftar "API keys", cari key yang sama dengan di `lib/config/maps_config.dart` (atau key yang dipakai untuk Maps)
3. Klik nama/key tersebut untuk buka pengaturan
4. Di bagian **"API restrictions"**:
   - Jika **"Don't restrict key"** → key bisa akses semua API (termasuk Directions API), tidak perlu ubah
   - Jika **"Restrict key"** → pastikan **Directions API** ada dalam daftar API yang diizinkan:
     - Klik **"Restrict key"**
     - Di "Select APIs", cari dan centang **Directions API**
     - Klik **Save**
5. Tunggu 1–2 menit agar perubahan tersebar

### 5. Billing ( jika diperlukan )
- Directions API memakai **Google Maps Platform** yang butuh billing
- Bila project belum punya billing: buka **Billing** dan aktifkan
- Ada free tier: sekitar \$200 kredit gratis per bulan

---

## Verifikasi

Setelah Directions API aktif:
1. Restart aplikasi (`flutter run`)
2. Login sebagai driver
3. Klik "Siap Kerja" → pilih rute → isi tujuan → pilih dari daftar → klik "Rute Perjalanan"
4. Rute biru harus muncul di peta
5. Tombol berubah menjadi merah "Selesai Bekerja"
