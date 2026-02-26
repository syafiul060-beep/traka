# Changelog Traka

Semua perubahan penting aplikasi Traka didokumentasikan di sini.

---

## [1.0.5] - 2025

### Perbaikan

- **Mode malam (dark mode):**
  - Pilihan lokasi tujuan (autocomplete) di form penumpang dan driver kini terbaca jelas
  - Teks tarif dan biaya di chat lebih terbaca di mode malam
  - Indikator rekaman pesan suara menyesuaikan tema gelap
  - Profile driver & penumpang: menu card dan sheet pakai warna tema
  - Data kendaraan: form dan dropdown pakai warna tema
  - Penumpang screen: driver sheet, bottom nav, search bar, loading overlay
  - Map: kontrol zoom dan tipe peta pakai warna tema

### Keamanan

- Deteksi fake GPS diperluas ke flow kritis: lokasi penumpang, kesepakatan harga, pesan, scan barcode
- Device ID untuk verifikasi login dan cegah spam

---

## [1.0.4] - 2025

### Fitur

- Panggilan suara (voice call) antara driver dan penumpang setelah kesepakatan harga
- Pesan suara di chat (rekam dan kirim seperti WhatsApp)
- Jadwal rute driver: atur jadwal per tanggal, tujuan awal/akhir, jam keberangkatan
- Cari jadwal: pesan travel berdasarkan jadwal driver
- Lacak Driver & Lacak Barang (in-app purchase)
- Scan barcode penumpang (driver) dan barcode driver (penumpang) untuk konfirmasi jemput/sampai tujuan
- Tarif per km: perhitungan dari titik jemput sampai titik turun
- Kontribusi driver setelah melayani penumpang
- Force update: notifikasi update wajib dari Play Store
- Promo dan riwayat pembayaran

### Perbaikan

- Perbaikan stabilitas dan pengalaman pengguna
- Debug print dibungkus kDebugMode

---

## [1.0.3] dan sebelumnya

- Fitur dasar: travel, kirim barang, chat, verifikasi wajah
- Login OTP email
- Onboarding
- Data Order, Lacak Driver, Lacak Barang
