# Reset Kontribusi Driver (saat hapus semua Firestore)

## Masalah
Jika Anda pernah **hapus semua** data Firestore (orders, dll) tapi **tidak reset** collection `users`, maka field berikut di `users/{driverUid}` tetap menyimpan nilai lama:
- `totalPenumpangServed` – total penumpang yang pernah dilayani
- `contributionPaidUpToCount` – total penumpang sampai pembayaran terakhir

Akibatnya, setelah 1 order baru selesai, aplikasi bisa langsung menampilkan **wajib bayar kontribusi** karena `totalPenumpangServed` masih memakai angka lama.

## Solusi: Reset manual di Firebase Console

1. Buka **Firebase Console** → **Firestore Database**
2. Buka collection **users**
3. Pilih dokumen driver yang ingin direset
4. Edit field:
   - `totalPenumpangServed` → **0**
   - `contributionPaidUpToCount` → **0**
5. Simpan

## Kapasitas mobil (1× kapasitas)

- Kapasitas diambil dari **vehicleJumlahPenumpang** di Data Kendaraan (users)
- Jika kosong atau 0, default **7** penumpang
- Driver wajib bayar setelah melayani **1× kapasitas** (mis. 7 penumpang untuk mobil 7 seat)

## Perbaikan di kode
- Jika `vehicleJumlahPenumpang` = 0 atau invalid, otomatis pakai 7 (mencegah wajib bayar setelah 1 penumpang)
