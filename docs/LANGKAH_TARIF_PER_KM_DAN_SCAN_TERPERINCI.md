# Langkah-Langkah Terperinci: Tarif Per KM & Alur Scan Barcode

Dokumen ini berisi langkah-langkah terperinci untuk memprogram manual atau memahami alur **tarif per km** (dari jemput sampai turun, 50 Rp/km) dan **scan barcode** driver–penumpang.

---

## Daftar Isi

1. [Konsep Umum](#1-konsep-umum)
2. [Struktur Data Firestore](#2-struktur-data-firestore)
3. [Langkah 1: Titik Jemput (Driver Scan Barcode Penumpang)](#3-langkah-1-titik-jemput-driver-scan-barcode-penumpang)
4. [Langkah 2: Titik Turun & Hitung Jarak + Tarif (Penumpang Scan Barcode Driver)](#4-langkah-2-titik-turun--hitung-jarak--tarif-penumpang-scan-barcode-driver)
5. [Langkah 3: Config Tarif Per KM (Admin)](#5-langkah-3-config-tarif-per-km-admin)
6. [Langkah 4: Menampilkan Jarak & Tarif di UI](#6-langkah-4-menampilkan-jarak--tarif-di-ui)
7. [Rumus & Validasi](#7-rumus--validasi)
8. [Checklist Implementasi Manual](#8-checklist-implementasi-manual)

---

## 1. Konsep Umum

- **Jarak yang dihitung:** dari **titik jemput** (saat penumpang dijemput/driver scan barcode penumpang) sampai **titik turun** (saat penumpang sampai tujuan/penumpang scan barcode driver).
- **Tarif:** `Tarif (Rp) = Jarak (km) × Tarif per km (Rp)`. Default tarif per km = **50 Rupiah**.
- **Siapa menyimpan apa:**
  - **Driver** saat scan barcode penumpang → simpan **titik jemput** (lokasi driver saat itu).
  - **Penumpang** saat scan barcode driver di tujuan → simpan **titik turun**, hitung **jarak (km)** dan **tarif (Rp)**.

---

## 2. Struktur Data Firestore

### 2.1 Collection `orders` – field yang dipakai untuk tarif/jarak

| Field             | Tipe     | Di-set oleh                    | Keterangan |
|-------------------|----------|---------------------------------|------------|
| `pickupLat`       | number   | Driver (saat scan penumpang)   | Latitude titik jemput. |
| `pickupLng`       | number   | Driver (saat scan penumpang)   | Longitude titik jemput. |
| `dropLat`         | number   | Penumpang (saat scan driver)   | Latitude titik turun. |
| `dropLng`         | number   | Penumpang (saat scan driver)   | Longitude titik turun. |
| `tripDistanceKm`  | number   | Penumpang (saat scan driver)   | Jarak jemput → turun (km). |
| `tripFareRupiah`  | number   | Penumpang (saat scan driver)   | Tarif = jarak × tarif per km (Rp). |

Field lain yang sudah ada (tetap dipakai): `driverScannedAt`, `passengerScannedAt`, `status`, `passengerLat`, `passengerLng`, dll.

### 2.2 Collection `app_config` – config admin

| Document   | Field        | Tipe   | Nilai default | Keterangan |
|------------|--------------|--------|----------------|------------|
| `settings` | `tarifPerKm` | number | 50            | Tarif (Rp) per 1 km. Bisa diubah di web admin. |

Jika `app_config/settings` atau field `tarifPerKm` tidak ada, aplikasi memakai **50** Rp/km.

---

## 3. Langkah 1: Titik Jemput (Driver Scan Barcode Penumpang)

**Tujuan:** Saat driver berhasil scan barcode penumpang, simpan lokasi driver saat itu sebagai **titik jemput** di order.

### 3.1 Alur singkat

1. Driver buka layar scan barcode penumpang.
2. App baca **lokasi GPS driver saat ini** (latitude, longitude).
3. App panggil logic yang memvalidasi barcode dan meng-update order.
4. Di update order, selain `driverScannedAt`, `driverBarcodePayload`, `status: picked_up`, tambahkan **`pickupLat`** dan **`pickupLng`** (lokasi tadi).

### 3.2 Langkah pemrograman (manual)

**A. Model order (OrderModel)**

- Tambah property: `pickupLat` (double?), `pickupLng` (double?).
- Di `fromFirestore`: baca `d['pickupLat']`, `d['pickupLng']` (num → double).

**B. Service order – fungsi “driver scan barcode penumpang”**

- Signature fungsi: terima `rawPayload` (string barcode), dan **opsional** `pickupLat`, `pickupLng`.
- Validasi seperti biasa: parse barcode TRAKA:orderId:P:*, cek order milik driver, status `agreed`.
- Update dokumen order:
  - `driverScannedAt`: serverTimestamp
  - `driverBarcodePayload`: string payload barcode driver (TRAKA:orderId:D:uuid)
  - `status`: `"picked_up"`
  - `updatedAt`: serverTimestamp
  - **Jika `pickupLat` dan `pickupLng` tidak null:**  
    `pickupLat`, `pickupLng` = nilai yang dikirim.

**C. Layar scan barcode penumpang (driver)**

- Sebelum/sesudah barcode terbaca, panggil **get current position** (Geolocator / API lokasi).
- Dapatkan `latitude` dan `longitude`.
- Panggil fungsi service di atas dengan `rawPayload`, `pickupLat: latitude`, `pickupLng: longitude`.
- Jika lokasi gagal didapat, tetap panggil fungsi tanpa `pickupLat`/`pickupLng` (order tetap bisa picked_up, nanti jarak pakai fallback `passengerLat`/`passengerLng`).

### 3.3 Contoh pseudocode (driver scan)

```
ON barcode detected:
  lat, lng = getCurrentPosition()  // boleh null jika gagal
  success, err, payload = OrderService.applyDriverScanPassenger(rawPayload, pickupLat: lat, pickupLng: lng)
  if success:
    kirim barcode driver ke chat, tampilkan sukses, tutup layar
  else:
    tampilkan error
```

---

## 4. Langkah 2: Titik Turun & Hitung Jarak + Tarif (Penumpang Scan Barcode Driver)

**Tujuan:** Saat penumpang berhasil scan barcode driver di tujuan, simpan titik turun, hitung jarak (km) dan tarif (Rp), lalu simpan ke order.

### 4.1 Alur singkat

1. Penumpang buka layar scan barcode driver (saat sampai tujuan).
2. App baca **lokasi GPS penumpang saat ini** → ini jadi **titik turun** (`dropLat`, `dropLng`).
3. Ambil **titik jemput** dari order: pakai `pickupLat`, `pickupLng` jika ada; kalau tidak, pakai `passengerLat`, `passengerLng` (fallback).
4. Hitung **jarak** (km) antara titik jemput dan titik turun (rumus haversine).
5. Baca **tarif per km** (dari config atau default 50).
6. Hitung **tarif (Rp) = jarak (km) × tarif per km**.
7. Update order: `passengerScannedAt`, `status: completed`, `completedAt`, `dropLat`, `dropLng`, `tripDistanceKm`, `tripFareRupiah`.

### 4.2 Langkah pemrograman (manual)

**A. Model order (OrderModel)**

- Tambah property: `tripFareRupiah` (double?).
- Di `fromFirestore`: baca `d['tripFareRupiah']` (num → double).

**B. Helper jarak (haversine)**

- Fungsi: `haversineKm(lat1, lng1, lat2, lng2)` → return jarak dalam km (double).
- Rumus standar haversine (earth radius ≈ 6371 km).

**C. Helper baca tarif per km**

- Fungsi: `getTarifPerKm()` → return number (int/num).
- Baca dari Firestore: collection `app_config`, document `settings`, field `tarifPerKm`.
- Jika dokumen/field tidak ada atau invalid, return **50**.

**D. Service order – fungsi “penumpang scan barcode driver”**

- Input: `rawPayload`, opsional `dropLat`, `dropLng` (lokasi penumpang saat scan).
- Validasi: parse TRAKA:orderId:D:*, cek order milik penumpang, status `picked_up`.
- Jika `dropLat` dan `dropLng` ada:
  - Ambil titik jemput: `pickLat = order.pickupLat ?? order.passengerLat`, `pickLng = order.pickupLng ?? order.passengerLng`.
  - Jika `pickLat` dan `pickLng` ada:  
    `tripDistanceKm = haversineKm(pickLat, pickLng, dropLat, dropLng)`.
  - `tarifPerKm = await getTarifPerKm()`.
  - `tripFareRupiah = round(tripDistanceKm * tarifPerKm)`.
- Update order:
  - `passengerScannedAt`, `status: completed`, `completedAt`, `updatedAt`
  - `dropLat`, `dropLng`
  - `tripDistanceKm` (jika dihitung)
  - `tripFareRupiah` (jika dihitung)

**E. Layar scan barcode driver (penumpang)**

- Saat barcode terbaca, ambil **get current position** → `dropLat`, `dropLng`.
- Panggil fungsi service dengan `rawPayload`, `dropLat`, `dropLng`.
- Tampilkan sukses/gagal.

### 4.3 Contoh pseudocode (penumpang scan)

```
ON barcode detected:
  dropLat, dropLng = getCurrentPosition()
  success, err = OrderService.applyPassengerScanDriver(rawPayload, dropLat: dropLat, dropLng: dropLng)
  // Di dalam applyPassengerScanDriver:
  //   pickLat = order.pickupLat ?? order.passengerLat
  //   pickLng = order.pickupLng ?? order.passengerLng
  //   tripDistanceKm = haversineKm(pickLat, pickLng, dropLat, dropLng)
  //   tarifPerKm = getTarifPerKm()  // default 50
  //   tripFareRupiah = round(tripDistanceKm * tarifPerKm)
  //   update order dengan dropLat, dropLng, tripDistanceKm, tripFareRupiah
  if success: tampilkan "Perjalanan selesai", tutup layar
  else: tampilkan error
```

---

## 5. Langkah 3: Config Tarif Per KM (Admin)

**Tujuan:** Tarif per km (default 50) bisa diubah dari “web admin” tanpa ubah kode app.

### 5.1 Firestore

- Collection: **`app_config`**.
- Document: **`settings`**.
- Field: **`tarifPerKm`** (number). Contoh: `50`, `100`.

Contoh isi dokumen:

```json
{
  "tarifPerKm": 50
}
```

### 5.2 Di aplikasi

- Sebelum hitung tarif, panggil `getTarifPerKm()` yang membaca `app_config/settings.tarifPerKm`.
- Jika tidak ada atau invalid, pakai **50**.

### 5.3 Langkah manual untuk admin (tanpa kode)

1. Buka Firebase Console → Firestore.
2. Buat collection `app_config` (jika belum ada).
3. Buat document dengan ID `settings` di dalam `app_config`.
4. Tambah field `tarifPerKm` (tipe number), isi nilai (misalnya 50).
5. Simpan. Order berikutnya yang selesai (penumpang scan driver) akan memakai nilai terbaru.

---

## 6. Langkah 4: Menampilkan Jarak & Tarif di UI

**Tujuan:** Di layar yang menampilkan order selesai, tampilkan **Jarak: X km** dan **Tarif: Rp X**.

### 6.1 Di mana menampilkan

- **Data Order – Driver:** tab Pemesanan Selesai (order dengan status completed).
- **Data Order – Penumpang:** tab Riwayat (order completed).
- **Riwayat Rute (driver):** detail rute yang berisi order completed.

### 6.2 Data yang dipakai

- `order.tripDistanceKm` → tampilkan "Jarak: {value} km" (format 1 desimal).
- `order.tripFareRupiah` → tampilkan "Tarif: Rp {value}" (bulat, tanpa desimal).

### 6.3 Kondisi tampil

- Jarak: tampilkan jika `tripDistanceKm != null` dan `>= 0`.
- Tarif: tampilkan jika `tripFareRupiah != null` dan `>= 0`.

---

## 7. Rumus & Validasi

### 7.1 Jarak (haversine)

- Input: lat1, lng1 (jemput), lat2, lng2 (turun).
- Output: jarak dalam km (double).
- Gunakan rumus haversine standar (radius bumi ≈ 6371 km).

### 7.2 Tarif

- `tripFareRupiah = round(tripDistanceKm * tarifPerKm)`.
- `tarifPerKm` default 50, bisa dari Firestore `app_config/settings.tarifPerKm`.

### 7.3 Validasi

- Driver scan: order status harus `agreed`; setelah update jadi `picked_up`.
- Penumpang scan: order status harus `picked_up`; setelah update jadi `completed`.
- Jika titik jemput tidak ada (pickupLat/pickupLng null), pakai passengerLat/passengerLng untuk hitung jarak.

---

## 8. Checklist Implementasi Manual

Gunakan checklist ini kalau implementasi dari nol atau cek satu per satu:

**Model & Firestore**

- [ ] Order: field `pickupLat`, `pickupLng`, `tripFareRupiah` di model dan dari Firestore.
- [ ] Firestore: siapkan `app_config/settings` dengan field `tarifPerKm` (opsional, default di kode 50).

**Driver scan barcode penumpang**

- [ ] Layar scan: dapatkan lokasi driver (getCurrentPosition).
- [ ] Service: update order dengan `driverScannedAt`, `driverBarcodePayload`, `status: picked_up`, dan `pickupLat`, `pickupLng` (jika lokasi ada).

**Penumpang scan barcode driver**

- [ ] Layar scan: dapatkan lokasi penumpang (dropLat, dropLng).
- [ ] Service: baca titik jemput (pickupLat/pickupLng atau passengerLat/passengerLng).
- [ ] Service: hitung `tripDistanceKm` (haversine), `tarifPerKm` (config/default 50), `tripFareRupiah`.
- [ ] Service: update order dengan `passengerScannedAt`, `status: completed`, `completedAt`, `dropLat`, `dropLng`, `tripDistanceKm`, `tripFareRupiah`.

**Config tarif**

- [ ] Fungsi baca `app_config/settings.tarifPerKm`; fallback 50.
- [ ] Doc/admin: cara ubah tarif per km lewat Firestore (lihat juga `TARIF_PER_KM.md`).

**UI**

- [ ] Data Order driver: tampilkan Jarak (km) dan Tarif (Rp) untuk order selesai.
- [ ] Data Order penumpang: tampilkan Jarak dan Tarif di riwayat.
- [ ] Riwayat Rute (driver): tampilkan Jarak dan Tarif per order selesai.

---

Dengan mengikuti langkah-langkah di atas, Anda bisa memprogram ulang fitur tarif per km dan alur scan secara manual atau memakai dokumen ini sebagai referensi terperinci.
