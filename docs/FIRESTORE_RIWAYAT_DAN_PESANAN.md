# Firestore: Riwayat Perjalanan & Nomor Pesanan

Dokumen ini menjelaskan struktur Firestore untuk **nomor rute perjalanan**, **riwayat perjalanan driver**, **nomor pesanan** unik, dan **kesepakatan driver–penumpang**.

---

## 0. Nomor rute perjalanan (driver)

- **Format**: `RUTE-YYYYMMDD-XXXXXX` (contoh: RUTE-20260128-000001). Unik antar driver, terisi otomatis.
- **Isi**: Tujuan awal dan akhir driver + tanggal dan hari (dari `routeStartedAt`).
- **Simpan**: Di `driver_status` (saat rute aktif) dan di `trips` (saat rute selesai). Nanti di `trips` terisi juga daftar nomor pesanan penumpang.
- **Generator**: `RouteJourneyNumberService.generateRouteJourneyNumber()` memakai counter Firestore `counters/route_journey_number`.

---

## 1. Koleksi `trips` (Riwayat perjalanan driver)

Setiap dokumen = satu perjalanan (rute) yang **sudah selesai** oleh driver.

| Field | Tipe | Keterangan |
|-------|------|-------------|
| `driverUid` | string | UID driver |
| `routeJourneyNumber` | string | Nomor rute perjalanan (RUTE-YYYYMMDD-XXXXXX) |
| `routeOriginLat` | number | Lat titik awal rute |
| `routeOriginLng` | number | Lng titik awal rute |
| `routeDestLat` | number | Lat titik tujuan rute |
| `routeDestLng` | number | Lng titik tujuan rute |
| `routeOriginText` | string | Teks lokasi awal |
| `routeDestText` | string | Teks lokasi tujuan |
| `routeStartedAt` | timestamp | Waktu mulai rute (tanggal & hari) |
| `orderNumbers` | array&lt;string&gt; | Daftar nomor pesanan penumpang (nanti terisi saat kesepakatan) |
| `status` | string | `completed` |
| `date` | string | Tanggal selesai (YYYY-MM-DD) |
| `day` | string | Nama hari (Senin, Selasa, ...) |
| `completedAt` | timestamp | Waktu driver menekan "Selesai Bekerja" |
| `createdAt` | timestamp | Waktu dokumen dibuat |

- **Doc ID**: auto (Firestore generate).
- **Kapan dibuat**: Saat driver menekan "Selesai Bekerja" (_endWork).

---

## 2. Koleksi `orders` (Pesanan / riwayat penumpang)

Setiap dokumen = satu **pesanan** dari satu penumpang. Dipakai saat penumpang memesan travel atau kirim barang.

| Field | Tipe | Keterangan |
|-------|------|-------------|
| `orderNumber` | string | **Nomor pesanan unik** (contoh: TRK-20260128-000001). Tidak boleh sama antar penumpang. |
| `passengerUid` | string | UID penumpang (pemesan / pengirim) |
| `driverUid` | string | UID driver (setelah kesepakatan) |
| `routeJourneyNumber` | string | Nomor rute perjalanan driver yang dipilih penumpang |
| `orderType` | string | `travel` (penumpang sendiri/kerabat) atau `kirim_barang` |
| `receiverUid` | string | (opsional) UID penerima barang; untuk kirim_barang |
| `originText` | string | Alamat asal penumpang |
| `destText` | string | Alamat tujuan penumpang |
| `originLat`, `originLng` | number | Koordinat asal |
| `destLat`, `destLng` | number | Koordinat tujuan (untuk kirim_barang = lokasi penerima) |
| `status` | string | `pending_agreement`, `agreed`, `picked_up`, `completed`, `cancelled` |
| `createdAt` | timestamp | Waktu pesanan dibuat |
| `updatedAt` | timestamp | Waktu terakhir diubah |

- **Doc ID**: auto.
- **Nomor pesanan**: Diisi otomatis oleh sistem, unik (lihat generator di bawah).

---

## 3. Nomor pesanan (order number)

- **Format**: `TRK-YYYYMMDD-XXXXXX`  
  Contoh: `TRK-20260128-000001`, `TRK-20260128-000002`.
- **Aturan**:
  - Dibuat otomatis oleh sistem.
  - Harus **berbeda** untuk tiap pesanan (tidak boleh sama dengan nomor pesanan pengguna lain).
- **Cara generate**: Pakai counter di Firestore (`counters/order_number`, field `lastSequence`) dengan **transaction**: baca nilai, tambah 1, tulis kembali, lalu format jadi string.

---

## 4. Alur (ringkas)

1. **Driver selesai rute**  
   - Driver menekan "Selesai Bekerja".  
   - App membuat dokumen baru di `trips` dengan data rute, `orderNumbers: []`, `status: 'completed'`, `completedAt`, `createdAt`.

2. **Penumpang cek riwayat** (nanti)  
   - Cek berdasarkan **nomor pesanan**: query `orders` where `orderNumber == ...` dan `passengerUid == currentUser.uid` (atau filter di client).

3. **Driver cek riwayat perjalanan** (nanti)  
   - Query `trips` where `driverUid == currentUser.uid`, urutkan `completedAt` desc.  
   - Setiap dokumen `trips` punya field `orderNumbers` (daftar nomor pesanan penumpang di perjalanan itu).

---

## 5. Rules Firestore (trips & orders)

Tambahkan di file rules (lihat `FIRESTORE_RULES_LENGKAP.txt`):

- **trips**:  
  - Baca: hanya user yang login (nanti bisa dibatasi: driver hanya baca milik sendiri).  
  - Tulis: hanya user yang login; create hanya jika `driverUid == request.auth.uid`.

- **orders**:  
  - Baca: hanya user yang login (penumpang baca milik sendiri, driver baca yang terkait trip-nya).  
  - Tulis: create oleh penumpang (pesanan baru); update oleh driver/app (konfirmasi, selesai, dll.).

- **counters** (untuk generator nomor pesanan):  
  - Baca/tulis: hanya dari backend (Cloud Functions) lebih aman; atau dari client dengan aturan ketat (hanya increment `lastSequence` lewat transaction).

Detail rules yang siap salin-tempel ada di `FIRESTORE_RULES_LENGKAP.txt`.  
**Langkah:** Buka Firebase Console → Firestore → Rules, lalu ganti seluruh isi rules dengan isi file `FIRESTORE_RULES_LENGKAP.txt` (sudah termasuk `trips`, `orders`, `counters`), lalu Publish.

---

## 6. Yang sudah diimplementasi (langkah ini)

- **TripService** (`lib/services/trip_service.dart`): saat driver menekan "Selesai Bekerja", rute yang selesai disimpan ke koleksi `trips` dengan `orderNumbers: []`.
- **OrderNumberService** (`lib/services/order_number_service.dart`): generator nomor pesanan unik (TRK-YYYYMMDD-XXXXXX) memakai counter di Firestore (`counters/order_number`). Siap dipakai saat fitur pesanan penumpang diimplementasi.
- **DriverScreen**: di `_endWork()` memanggil `TripService.saveCompletedTrip(...)` sebelum mengosongkan state.

---

## 7. Alur tombol Selesai Bekerja (sudah diimplementasi)

1. **Belum dapat penumpang**  
   - Jika waktu estimasi rute sudah habis → pekerjaan diakhiri otomatis.  
   - Jika driver klik "Selesai Bekerja" → hanya boleh setelah **15 menit** dari mulai rute (jika belum dapat penumpang).

2. **Sudah dapat penumpang** (ada pesanan dengan status agreed/picked_up untuk nomor rute ini)  
   - Tombol "Selesai Bekerja" **tidak berfungsi**.  
   - Muncul notifikasi: *"Penumpang atau Barang belum sampai. Selesaikan pekerjaan...!"*

3. **Driver boleh klik Selesai Bekerja** apabila:  
   - Belum mendapatkan penumpang, **dan**  
   - Sudah 15 menit sejak rute aktif.

---

## 8. Kesepakatan driver–penumpang + nomor pesanan (sudah diimplementasi)

### Alur kesepakatan

1. **Penumpang** mengirim permintaan dari Cari Travel → dokumen `orders` dibuat dengan status `pending_agreement`, `orderNumber: null`.
2. **Driver** di Data Order → tab Pemesanan melihat daftar pesanan → klik **Kesepakatan** → `driverAgreed: true`.
3. **Penumpang** di Data Order melihat pesanan → jika driver sudah setuju, tombol **Kesepakatan** aktif.
4. **Penumpang** klik **Kesepakatan** → app meminta izin lokasi, ambil koordinat saat ini + alamat (reverse geocoding) → panggil `OrderService.setPassengerAgreed(...)`:
   - Jika driver sudah setuju: sistem generate **nomor pesanan** unik (TRK-YYYYMMDD-XXXXXX), simpan lokasi penumpang (`passengerLat`, `passengerLng`, `passengerLocationText`), set status = `agreed`.
   - Jika driver belum setuju: hanya set `passengerAgreed: true` (nomor pesanan dan lokasi diisi nanti saat driver setuju).
5. **Driver** di tab Pemesanan melihat nomor pesanan dan lokasi penumpang → tombol **Lihat Lokasi** membuka peta dengan marker lokasi penumpang.

### Nomor pesanan

- **Format**: `TRK-YYYYMMDD-XXXXXX` (contoh: TRK-20260128-000001). Unik global.
- **Kapan dibuat**: Saat penumpang klik Kesepakatan **setelah** driver sudah klik Kesepakatan (keduanya setuju).
- **Tampilan**: Di Data Order driver (tab Pemesanan) dan Data Order penumpang, kolom "No. Pesanan" menampilkan nomor ini setelah kesepakatan lengkap.

---

## 9. Halaman Data Order driver – 4 menu (sudah kerangka)

1. **Pemesanan** – Pesanan aktif yang sudah kesepakatan. Nanti: foto profil, nama, lokasi penumpang, tombol lihat lokasi, tombol scan penumpang/barcode.  
2. **Penumpang** – Penumpang yang sudah dijemput (setelah scan/barcode; diprogram nanti).  
3. **Pemesanan Selesai** – Penumpang yang sudah selesai perjalanan: nomor pesanan, nama; klik → lokasi awal/akhir, jarak, estimasi waktu.  
4. **Riwayat Rute Perjalanan** – Semua rute perjalanan (urut terakhir); klik rute → daftar nomor pesanan & nama penumpang; klik lagi → detail perjalanan penumpang.

---

## 10. Yang nanti (belum)

- Halaman **riwayat perjalanan driver** (tab Riwayat Rute): baca dari `trips` where `driverUid == currentUser.uid`, tampilkan daftar rute selesai + daftar nomor pesanan per perjalanan.
- Halaman **riwayat travel penumpang** (per nomor pesanan): filter/query `orders` where `passengerUid == currentUser.uid`; tampilan detail per nomor pesanan (sudah ada list di Data Order penumpang).
- **Scan penumpang / barcode**: diprogram nanti.
