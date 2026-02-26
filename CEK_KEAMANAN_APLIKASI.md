# Laporan Keamanan Aplikasi Traka

## 1. Device ID – Status: Berjalan Normal

### Implementasi
- **DeviceService** (`lib/services/device_service.dart`): Mengambil `android.id` (Android) atau `identifierForVendor` (iOS), plus `installId` dari SharedPreferences sebagai fallback.
- **DeviceSecurityService** (`lib/services/device_security_service.dart`): 
  - Cegah spam: maksimal 1 akun per role per device (penumpang + driver boleh di device sama).
  - Rate limit: maksimal 10 gagal login per jam.
  - Deteksi emulator: blokir registrasi dan login dari emulator.
- **Login** (`lib/screens/login_screen.dart`): 
  - Jika `deviceId` berbeda dari yang tersimpan → wajib verifikasi wajah.
  - Setelah verifikasi berhasil, `deviceId` diupdate ke device baru.

### Catatan
- Di Android 10+, `android.id` bisa kosong untuk non-system apps. Aplikasi sudah memakai `installId` sebagai fallback.
- Device ID **tidak** dihapus saat logout agar bisa mendeteksi login dari device baru.

---

## 2. Fake GPS / Lokasi Palsu – Status: Sudah Diperluas

### Kondisi Saat Ini (setelah perbaikan)

| Flow | Metode Lokasi | Cek Fake GPS? |
|------|---------------|----------------|
| **Registrasi driver** | `getDriverLocationResult()` | Ya |
| Update lokasi driver (tracking) | `getCurrentPositionWithMockCheck()` | Ya |
| Lokasi penumpang (origin) | `getCurrentPositionWithMockCheck()` | Ya |
| Update lokasi penumpang ke order | `getCurrentPositionWithMockCheck()` | Ya |
| Kesepakatan penumpang (setuju harga) | `getCurrentPositionWithMockCheck()` | Ya |
| Isi lokasi saat pesan | `getCurrentPositionWithMockCheck()` | Ya |
| Scan barcode (driver/penumpang) | `getCurrentPositionWithMockCheck()` | Ya |
| Cek lokasi barang | `getCurrentPosition()` | Belum (display only) |

### Implementasi
- Method baru `LocationService.getCurrentPositionWithMockCheck()` memakai native Android `getLocationWithMockCheck` untuk deteksi mock.
- Jika fake GPS terdeteksi: tampil SnackBar merah, lokasi tidak diupdate ke Firestore / tidak diproses.

### Batasan Teknis Android
- `Location.isMock()` (API 31+) dan `isFromMockProvider()` (deprecated) **tidak selalu andal**.
- Beberapa aplikasi fake GPS bisa lolos deteksi.
- Deteksi mock location di Android tidak 100% tahan bypass.

### Rekomendasi Lanjutan
1. ~~Tambahkan cek fake GPS di flow lokasi kritis~~ (sudah diterapkan).
2. Pertimbangkan deteksi tambahan (mis. kecepatan tidak wajar, loncatan koordinat).
3. Untuk keamanan tinggi, pertimbangkan library pihak ketiga (mis. Malwarelytics) yang punya deteksi spoofing lebih canggih.

---

## 3. Ringkasan

| Aspek | Status | Keterangan |
|-------|--------|------------|
| Device ID | Normal | Dipakai untuk verifikasi login dan cegah spam |
| Fake GPS (registrasi driver) | Aktif | Deteksi di registrasi |
| Fake GPS (flow kritis) | Aktif | Driver tracking, lokasi penumpang, kesepakatan, pesan, scan barcode |

### Catatan
- Deteksi mock di Android memakai `Location.isMock()` (API 31+) / `isFromMockProvider()` (deprecated). Beberapa aplikasi fake GPS bisa lolos.
- Untuk testing: set `kDisableFakeGpsCheck = true` di `lib/services/location_service.dart`.
