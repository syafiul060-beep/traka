# Rencana Implementasi Barcode & Scan (Driver–Penumpang)

## Status implementasi (cek terakhir)

| Bagian | Status | Keterangan |
|--------|--------|------------|
| **1. Barcode penumpang (setelah setuju)** | ✅ | Payload `TRAKA:orderId:P:uuid` di `setPassengerAgreed`; tampil di chat penumpang & driver; Data Order driver: kartu "Pesanan" (tap = barcode full). Penumpang: tombol "Tunjukkan barcode ke driver" di Data Order > Pesanan. |
| **2. Scan barcode penumpang (driver)** | ✅ | `ScanBarcodeDriverScreen` (mobile_scanner); tombol di chat driver (di atas Kesepakatan) dan di Data Order > Pemesanan. Setelah sukses: kirim barcode driver ke chat, order pindah ke tab Penumpang. |
| **3. Barcode driver & scan penumpang** | ✅ | Barcode driver dikirim ke chat setelah driver scan; tampil di chat & Data Order driver (tab Penumpang, kartu Barcode). `applyPassengerScanDriver` + `ScanBarcodePenumpangScreen`; tab Driver penumpang hanya tombol "Scan barcode driver". |
| **4. Aturan barcode** | ✅ | Validasi driver/penumpang order di `applyDriverScanPassenger` dan `applyPassengerScanDriver`; payload P/D + uuid. |
| **5. UI penumpang setelah driver scan** | ✅ | Tab Pesanan = hanya `agreed`. Tab Driver = `picked_up` dengan tombol Scan barcode driver. Banner di chat penumpang: "Perjalanan aktif. Scan barcode driver di Data Order > Driver saat sampai tujuan." |
| **6. Dependency** | ✅ | `qr_flutter`, `mobile_scanner` di pubspec. |
| **7. Model & Firestore** | ✅ | Order: `passengerBarcodePayload`, `driverBarcodePayload`, `driverScannedAt`, `passengerScannedAt`; getter `hasPassengerBarcode`, `hasDriverBarcode`, `hasDriverScannedPassenger`, `hasPassengerScannedDriver`. |

**Pemisahan menu:** Data Order driver: **Pemesanan** = hanya `agreed`; **Penumpang** = `picked_up` (dengan kartu Barcode driver); **Pemesanan Selesai** = `completed`. Data Order penumpang: **Pesanan** = `agreed`; **Driver** = `picked_up` (hanya tombol Scan barcode driver).

---

## Yang sudah dilakukan
- **Batal:** Penumpang tap Batal → dialog konfirmasi "Apakah Anda ingin membatalkan kesepakatan ini / ingin membuat kesepakatan baru?" → Ya = kirim pesan ke driver "Penumpang membatalkan kesepakatan dan ingin membuat kesepakatan baru.", popup tidak muncul lagi.
- **Setuju:** Setelah penumpang setuju, pesan otomatis ke driver: "Penumpang sudah mensetujui kesepakatan."

## Alur yang perlu dibangun

### 1. Barcode penumpang (setelah setuju)
- Saat penumpang setuju: generate payload unik (orderId + "P" + signature), simpan di order (Firestore).
- Tampilkan barcode/QR di: (a) isi chat penumpang sebagai gambar, (b) Data Order driver di menu Pesanan sebelah tombol Lokasi (klik = gambar barcode full).
- Paket: `qr_flutter` untuk generate, atau generate image pakai `barcode`/`qr_flutter`.

### 2. Scan barcode penumpang (driver)
- Tombol "Scan barcode": di chat driver (di atas tombol Kesepakatan) dan di Data Order (menu Pesanan, samping kanan tombol Lokasi).
- Klik → buka kamera belakang, scan QR/barcode.
- Validasi: payload harus orderId + "P" dan order ini milik driver yang login.
- Setelah scan berhasil: update order (mis. status `picked_up`), generate barcode driver, simpan di order. Data order pindah dari "menu Pesanan" ke "menu Penumpang" (driver).
- Paket: `mobile_scanner` atau `qr_code_scanner` untuk scan.

### 3. Barcode driver & scan oleh penumpang
- Driver barcode: payload (orderId + "D" + signature), tampil di chat driver dan di Data Order (menu Penumpang) samping tombol Lokasi; klik = gambar barcode.
- Penumpang: di Data Order (menu Driver) hanya tombol "Scan barcode" → buka kamera, scan barcode driver.
- Validasi: payload orderId + "D", order milik penumpang yang login.
- Setelah scan berhasil: anggap selesai perjalanan (status `completed`), order pindah ke "Pemesanan Selesai" / menu yang sesuai.

### 4. Aturan barcode
- Barcode penumpang hanya valid di-scan oleh driver yang punya order tersebut.
- Barcode driver hanya valid di-scan oleh penumpang yang punya order tersebut.
- Payload berisi orderId + role (P/D) + signature (mis. HMAC) agar tidak bisa dipalsu/dipakai order lain.

### 5. UI penumpang setelah driver scan
- Halaman chat/order penumpang: tombol Batal, Chat, Lokasi tidak ditampilkan; yang ada: menu untuk menampilkan gambar barcode (untuk di-scan driver).
- Data Order penumpang: di bagian "menu driver" hanya tombol Scan barcode untuk scan barcode driver.

### 6. Dependency yang perlu ditambah (pubspec.yaml)
- `qr_flutter` atau setara untuk generate QR/barcode image.
- `mobile_scanner` (atau `qr_code_scanner`) untuk scan dengan kamera.

### 7. Perubahan model & Firestore
- Order: field opsional `passengerBarcodePayload`, `driverBarcodePayload`, `driverScannedAt`, `passengerScannedAt` (timestamp).
- Atau simpan payload di subcollection/document terpisah jika tidak ingin mengubah skema order.
