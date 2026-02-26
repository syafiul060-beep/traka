# Firestore Rules untuk Driver Status

Dokumen ini menjelaskan secara terperinci tentang collection `driver_status` di Firestore dan cara mengaturnya.

---

## Daftar Isi

1. [Apa itu Driver Status?](#1-apa-itu-driver-status)
2. [Kenapa Diperlukan?](#2-kenapa-diperlukan)
3. [Struktur Data](#3-struktur-data)
4. [Cara Menambah Firestore Rules](#4-cara-menambah-firestore-rules)
5. [Cara Kerja Aplikasi](#5-cara-kerja-aplikasi)
6. [Alur Update Lokasi](#6-alur-update-lokasi)
7. [Query untuk Penumpang](#7-query-untuk-penumpang)
8. [Verifikasi dan Troubleshooting](#8-verifikasi-dan-troubleshooting)

---

## 1. Apa itu Driver Status?

**Driver Status** adalah data di Firestore yang menyimpan:
- **Status driver**: Apakah driver sedang kerja (ada rute) atau tidak aktif
- **Lokasi driver**: Koordinat GPS driver saat ini
- **Info rute**: Dari mana driver berangkat dan ke mana tujuan (jika sedang kerja)

Data ini dipakai agar **penumpang bisa mencari travel** yang cocok dengan tujuan mereka. Penumpang hanya akan melihat driver yang statusnya "siap kerja" dan rutenya sesuai.

---

## 2. Kenapa Diperlukan?

| Kebutuhan | Penjelasan |
|-----------|------------|
| **Penumpang cari travel** | Penumpang ingin melihat daftar driver yang sedang aktif dan rutenya ke mana |
| **Filter driver** | Hanya driver dengan status "siap_kerja" yang muncul di pencarian |
| **Lokasi real-time** | Lokasi driver perlu terupdate agar penumpang tahu posisi driver saat ini |
| **Efisiensi** | Update lokasi tidak setiap detik, tapi hanya jika driver pindah jauh atau sudah lama (hemat kuota & battery) |

---

## 3. Struktur Data

### Collection: `driver_status`

Setiap driver yang sedang aktif akan punya **1 document** dengan ID = UID driver.

### Path Document

```
driver_status/{driverId}
```

**Contoh**: `driver_status/abc123xyz456` (abc123xyz456 = UID driver dari Firebase Auth)

### Field di Dalam Document

| Nama Field | Tipe | Wajib? | Penjelasan |
|------------|------|--------|------------|
| `uid` | string | Ya | UID driver (sama dengan ID document) |
| `status` | string | Ya | "siap_kerja" atau "tidak_aktif" |
| `latitude` | number | Ya | Latitude lokasi driver saat ini |
| `longitude` | number | Ya | Longitude lokasi driver saat ini |
| `lastUpdated` | timestamp | Ya | Waktu terakhir data diupdate |
| `routeOriginLat` | number \| null | Tidak | Latitude titik awal rute |
| `routeOriginLng` | number \| null | Tidak | Longitude titik awal rute |
| `routeDestLat` | number \| null | Tidak | Latitude titik tujuan rute |
| `routeDestLng` | number \| null | Tidak | Longitude titik tujuan rute |
| `routeOriginText` | string \| null | Tidak | Teks lokasi awal (mis: "Kec. Angsana, Tanah Bumbu") |
| `routeDestText` | string \| null | Tidak | Teks lokasi tujuan (mis: "Banjarmasin, Kalsel") |

### Contoh Data di Firestore

**Driver sedang kerja (status = "siap_kerja"):**

```json
{
  "uid": "abc123xyz456",
  "status": "siap_kerja",
  "latitude": -3.3194,
  "longitude": 114.5907,
  "lastUpdated": "2026-02-01T04:59:00Z",
  "routeOriginLat": -3.3194,
  "routeOriginLng": 114.5907,
  "routeDestLat": -3.3200,
  "routeDestLng": 114.5940,
  "routeOriginText": "Kecamatan Angsana, Kabupaten Tanah Bumbu, Kalimantan Selatan",
  "routeDestText": "Banjarmasin, Kalimantan Selatan"
}
```

**Driver tidak aktif (status = "tidak_aktif"):**

```json
{
  "uid": "abc123xyz456",
  "status": "tidak_aktif",
  "latitude": -3.3194,
  "longitude": 114.5907,
  "lastUpdated": "2026-02-01T05:10:00Z",
  "routeOriginLat": null,
  "routeOriginLng": null,
  "routeDestLat": null,
  "routeDestLng": null,
  "routeOriginText": null,
  "routeDestText": null
}
```

---

## 4. Cara Menambah Firestore Rules

Firestore Rules mengatur siapa yang boleh membaca dan menulis data. Tanpa rules yang benar, aplikasi bisa gagal atau data tidak aman.

### Langkah 1: Buka Firebase Console

1. Buka browser, kunjungi [https://console.firebase.google.com](https://console.firebase.google.com)
2. Login dengan akun Google
3. Pilih project **Traka** (atau nama project Anda)

### Langkah 2: Buka Firestore Rules

1. Di menu kiri, klik **Firestore Database**
2. Klik tab **Rules** (di atas area data)
3. Anda akan melihat editor dengan kode rules yang sudah ada

### Langkah 3: Tambahkan Rules untuk driver_status

**Penting**: Jangan hapus rules yang sudah ada (users, verification_codes, dll). Hanya **tambahkan** blok baru di dalam `match /databases/{database}/documents { ... }`.

Cari baris terakhir sebelum `}` penutup, lalu tambahkan:

```javascript
    // Collection driver_status: status dan lokasi driver yang sedang aktif
    match /driver_status/{driverId} {
      // Baca: semua orang bisa baca (agar penumpang bisa cari travel)
      allow read: if true;
      
      // Tulis: hanya driver yang login dan mengupdate data miliknya sendiri
      allow write: if request.auth != null && request.auth.uid == driverId;
    }
```

### Langkah 4: Contoh Rules Lengkap

Jika ingin melihat rules lengkap (gabungan semua collection), berikut contohnya:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Collection users
    match /users/{userId} {
      allow read: if true;
      allow write: if request.auth != null && request.auth.uid == userId;
    }
    
    // Collection verification_codes
    match /verification_codes/{email} {
      allow create, read, delete: if true;
      allow update: if false;
    }
    
    // Collection device_accounts
    match /device_accounts/{deviceId} {
      allow read: if true;
      allow create, update: if request.auth != null;
      allow delete: if false;
    }
    
    // Collection device_rate_limit
    match /device_rate_limit/{deviceId} {
      allow read, write: if true;
    }
    
    // Collection driver_status (TAMBAHAN BARU)
    match /driver_status/{driverId} {
      allow read: if true;
      allow write: if request.auth != null && request.auth.uid == driverId;
    }
  }
}
```

### Langkah 5: Publish Rules

1. Setelah menambah rules, klik tombol **Publish** di kanan atas
2. Konfirmasi dengan klik **Publish** lagi
3. Tunggu beberapa detik hingga rules aktif

### Penjelasan Rules driver_status

| Rule | Makna |
|------|-------|
| `allow read: if true` | Semua orang (termasuk penumpang yang belum login) boleh **membaca** data driver_status. Ini perlu agar penumpang bisa melihat daftar driver yang siap kerja. |
| `allow write: if request.auth != null && request.auth.uid == driverId` | Hanya user yang **sudah login** dan **UID-nya sama dengan driverId** di path yang boleh **menulis** (create, update, delete). Jadi driver hanya bisa mengubah data miliknya sendiri. |

---

## 5. Cara Kerja Aplikasi

### Kapan Data Driver Status Ditulis?

| Kejadian | Yang Terjadi |
|----------|--------------|
| Driver klik **"Siap Kerja"** → pilih rute → klik **"Rute Perjalanan"** | Data dibuat/diupdate dengan status `siap_kerja`, lokasi, dan info rute |
| Driver dalam perjalanan, pindah ≥ 1,5 km atau sudah 12 menit | Lokasi diupdate (latitude, longitude, lastUpdated) |
| Driver klik **"Selesai Bekerja"** (tombol merah) | Data diupdate dengan status `tidak_aktif`, info rute dihapus |
| Driver sampai tujuan & tidak klik tombol (auto-end 1,5 jam) | Sama seperti "Selesai Bekerja" |
| Driver pilih **"Putar Arah Rute sebelumnya"** | Data diupdate dengan rute baru (asal-tujuan dibalik) |
| Driver logout atau keluar dari halaman beranda | Document driver_status **dihapus** |

### Status Driver

| Status | Makna | Terlihat di Pencarian Penumpang? |
|--------|-------|----------------------------------|
| `siap_kerja` | Driver sedang kerja, ada rute aktif | ✅ Ya |
| `tidak_aktif` | Driver tidak kerja, tidak ada rute | ❌ Tidak |

---

## 6. Alur Update Lokasi

Lokasi driver **tidak** di-update setiap detik agar hemat kuota Firestore dan battery HP.

### Kondisi Update

Lokasi akan di-update ke Firestore **hanya jika** salah satu terpenuhi:

1. **Driver pindah ≥ 1,5 km** dari lokasi terakhir yang di-update
2. **Sudah ≥ 12 menit** sejak update terakhir (update paksa)

### Ilustrasi Alur

```
[Driver buka beranda] 
       ↓
[Refresh GPS setiap 10 detik] 
       ↓
[Cek: apakah perlu update ke Firestore?]
       ↓
   ┌───┴───┐
   │       │
   ↓       ↓
Pindah    Sudah 12
≥ 1,5 km  menit?
   │       │
   └───┬───┘
       ↓
   [Ya] → Update ke Firestore
       ↓
   [Tidak] → Lewati (tidak update)
```

---

## 7. Query untuk Penumpang

Penumpang yang fitur "Cari Travel" akan membutuhkan query ke collection `driver_status`.

### Query Dasar (Driver yang Siap Kerja)

```dart
// Flutter / Dart
FirebaseFirestore.instance
  .collection('driver_status')
  .where('status', isEqualTo: 'siap_kerja')
  .get();
```

### Contoh Hasil

```dart
QuerySnapshot snapshot = await FirebaseFirestore.instance
  .collection('driver_status')
  .where('status', isEqualTo: 'siap_kerja')
  .get();

for (var doc in snapshot.docs) {
  final data = doc.data();
  final uid = data['uid'];
  final lat = data['latitude'];
  final lng = data['longitude'];
  final destText = data['routeDestText'];
  // Cek apakah tujuan driver cocok dengan tujuan penumpang
}
```

### Filter Berdasarkan Tujuan (Client-side)

Karena Firestore tidak mendukung query geospatial secara native, filter jarak atau kecocokan tujuan biasanya dilakukan di client:

1. Ambil semua driver dengan status `siap_kerja`
2. Di aplikasi, filter mana yang `routeDestText` atau koordinatnya cocok dengan tujuan penumpang
3. Urutkan berdasarkan jarak (jika perlu)

---

## 8. Verifikasi dan Troubleshooting

### Cara Cek Apakah Driver Status Berfungsi

1. **Login sebagai driver** di aplikasi Traka
2. Buka **Beranda** driver
3. Klik tombol **"Siap Kerja"** (hijau) → pilih jenis rute → isi tujuan → klik **"Rute Perjalanan"**
4. Buka **Firebase Console** → Firestore Database → Data
5. Cek collection **driver_status** → seharusnya ada document dengan UID driver Anda
6. Klik document tersebut → pastikan ada field `status`, `latitude`, `longitude`, `routeDestText`, dll.

### Error Umum

| Error | Penyebab | Solusi |
|-------|----------|--------|
| **Missing or insufficient permissions** | Rules belum di-publish atau salah | Publish ulang rules, pastikan `request.auth.uid == driverId` |
| **Data tidak muncul di Firestore** | Driver belum buat rute / belum "Siap Kerja" | Pastikan driver sudah klik "Rute Perjalanan" dan rute berhasil dimuat |
| **Data tidak ter-update** | GPS atau izin lokasi | Pastikan izin lokasi diberikan dan GPS aktif |
| **Document tidak terhapus saat logout** | Error di `removeDriverStatus` | Cek koneksi internet dan rules (allow delete untuk driver sendiri) |

### Cek Rules di Simulator

1. Di Firebase Console → Firestore → Rules
2. Klik **Rules Playground**
3. Pilih **get** (read) atau **set** (write)
4. Path: `driver_status/UID_ANDA`
5. Klik **Run** untuk tes apakah rules mengizinkan aksi tersebut

---

## Ringkasan

- **driver_status** = data status & lokasi driver yang sedang aktif
- **Rules**: Baca = semua orang, Tulis = hanya driver pemilik data
- **Update lokasi**: Hanya jika pindah ≥ 1,5 km atau sudah 12 menit
- **Penumpang** bisa query `status == 'siap_kerja'` untuk cari travel
