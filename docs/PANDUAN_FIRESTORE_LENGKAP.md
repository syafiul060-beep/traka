# Panduan Lengkap Firestore untuk Traka

Dokumen ini menjelaskan **Rules**, **Cache HP (Offline Persistence)**, **Indexes**, dan **Deployment** Firestore agar mudah dipahami dan dijalankan.

---

## Daftar Isi

1. [Firestore Rules](#1-firestore-rules)
2. [Cache HP (Offline Persistence)](#2-cache-hp-offline-persistence)
3. [Indexes](#3-indexes)
4. [Deploy ke Firebase](#4-deploy-ke-firebase)
5. [Cek & Verifikasi](#5-cek--verifikasi)

---

## 1. Firestore Rules

**Apa itu?** Aturan keamanan yang mengatur siapa boleh **baca** dan **tulis** data di setiap collection Firestore.

**File:** `firestore.rules` (di root project)

**Kenapa penting?** Tanpa rules yang benar, data bisa dibaca/diubah orang lain atau query gagal.

### Ringkasan per Collection

| Collection | Baca | Tulis | Catatan |
|------------|------|-------|--------|
| **users** | Semua | Hanya pemilik dokumen (userId = auth.uid) | Profil penumpang/driver, region, lokasi |
| **verification_codes** | Semua | Create/read/delete saja | Kode verifikasi email; update tidak boleh |
| **device_accounts** | Semua | Create/update hanya jika login | Cek "perangkat sudah punya akun" saat daftar |
| **device_rate_limit** | Semua | Semua | Pencatatan saat login gagal (belum auth) |
| **driver_status** | Semua | Hanya driver pemilik | Status & lokasi driver yang aktif |
| **driver_schedules** | Hanya driver pemilik | Hanya driver pemilik | Jadwal keberangkatan driver |
| **trips** | Jika login | Create: driver pemilik; update/delete: jika login | Riwayat perjalanan driver |
| **orders** | Jika login | Jika login | Pesanan penumpang |
| **orders/{id}/messages** | Hanya penumpang atau driver order tersebut | Hanya penumpang atau driver; delete tidak boleh | Chat penumpang–driver |
| **counters** | Jika login | Jika login | Generator nomor pesanan & nomor rute |
| **vehicles** | Jika login | Create: driver pemilik; update/delete: driver pemilik | Data kendaraan driver |
| **vehicle_brands** | Jika login | Jika login | Merek & tipe mobil |

### Aturan Penting untuk Chat (messages)

- Hanya **passengerUid** atau **driverUid** dari dokumen `orders/{orderId}` yang boleh **read, create, update** di `orders/{orderId}/messages`.
- **Delete** pesan tidak diizinkan (`allow delete: if false`).

---

## 2. Cache HP (Offline Persistence)

**Apa itu?** Firestore bisa menyimpan data di HP (cache lokal) sehingga app tetap bisa menampilkan data terakhir saat **offline** (misalnya riwayat chat).

**Di mana diatur?** Di `lib/main.dart`, setelah `Firebase.initializeApp()`:

```dart
final firestore = FirebaseFirestore.instance;
firestore.settings = const Settings(
  persistenceEnabled: true,
  cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
);
```

- **persistenceEnabled: true** → Aktifkan penyimpanan lokal.
- **cacheSizeBytes: CACHE_SIZE_UNLIMITED** → Tidak batasi ukuran cache (sesuai kebutuhan chat/riwayat).

**Kenapa penting untuk Traka?** Pengguna bisa tetap melihat chat dan riwayat order saat sinyal lemah atau sebentar offline; setelah online lagi, data akan sinkron otomatis.

**Cara cek:** Jalankan app, buka beberapa chat/order, lalu matikan internet—chat/order yang sudah pernah dibuka harus tetap terbaca.

---

## 3. Indexes

**Apa itu?** Index dipakai Firestore untuk mempercepat query yang memakai **beberapa field** (filter + sort). Tanpa index composite, Firestore akan menolak query dan memberi link untuk membuat index.

**File:** `firestore.indexes.json` (di root project)

### Index yang Dipakai Traka (collection `orders`)

| No | Field yang di-index | Kegunaan singkat |
|----|----------------------|-------------------|
| 1 | passengerUid (ASC), status (ASC), updatedAt (DESC) | Daftar order penumpang, filter status, urut terbaru |
| 2 | driverUid (ASC), status (ASC), createdAt (DESC) | Daftar order driver, filter status, urut terbaru |
| 3 | routeJourneyNumber (ASC), driverUid (ASC), status (ASC), createdAt (DESC) | Query order per nomor rute + driver |
| 4 | status (ASC), completedAt (ASC) | Query order selesai (misalnya untuk auto-hapus chat / laporan) |

Jika app menampilkan error **"The query requires an index"**, buka link di pesan error tersebut—Firebase akan mengarahkan ke Console untuk membuat index. Atau deploy index dari file (lihat bagian Deploy).

---

## 4. Deploy ke Firebase

### Di Firebase Console (Firestore → Rules)

- **Rules** tampil di tab **Rules** (Cloud Firestore → Database → **Rules**).
- Yang dipakai deploy adalah file lokal **`firestore.rules`**. Isi di Console bisa dipakai sebagai salinan referensi.
- **Deployment history** (kiri): daftar waktu deploy (mis. "Yesterday • 2:31 am", "Feb 3, 2026 • 9:33 pm")—versi terbaru ditandai bintang.
- Tombol **"Develop and Test"** dipakai untuk simulasi dan uji rules sebelum publish.

### Perintah deploy (dari root project)

Pastikan sudah login: `firebase login`.

| Yang di-deploy | Perintah |
|----------------|----------|
| **Hanya Rules** | `firebase deploy --only firestore:rules` |
| **Hanya Indexes** | `firebase deploy --only firestore:indexes` |
| **Rules + Indexes** | `firebase deploy --only firestore` |
| **Cloud Functions** | `firebase deploy --only functions` |

Contoh di terminal:

```bash
# Hanya rules (file: firestore.rules)
firebase deploy --only firestore:rules

# Hanya indexes (file: firestore.indexes.json)
firebase deploy --only firestore:indexes

# Rules + indexes sekaligus
firebase deploy --only firestore

# Cloud Functions (folder: functions, runtime: nodejs20)
firebase deploy --only functions
```

**Catatan:** Setelah deploy indexes, pembuatan index di server bisa memakan waktu beberapa menit. Status bisa dicek di Firebase Console → Firestore → **Indexes**. Konfigurasi functions ada di `firebase.json`.

---

## 5. Cek & Verifikasi

### Rules

- **Firebase Console** → Firestore → Rules: Pastikan isi sama dengan `firestore.rules` dan status “Published”.
- **Di app:** Login sebagai penumpang dan driver, buka order & chat—harus bisa baca/tulis. Akun lain tidak boleh mengakses order orang lain.

### Cache (Offline)

- Buka app, masuk ke beberapa order/chat.
- Matikan WiFi/data.
- Buka lagi halaman chat/order—data yang sudah pernah dimuat harus masih tampil.

### Indexes

- **Firebase Console** → Firestore → Indexes: Semua index dari `firestore.indexes.json` harus ada dan status **Enabled**.
- Jika ada query baru dan muncul error “index required”, buat index lewat link di error atau tambahkan ke `firestore.indexes.json` lalu deploy.

### Cloud Functions

- **Firebase Console** → Functions: Cek fungsi yang dipakai (notifikasi, auto-hapus chat, dll.) sudah deploy dan tidak error di Logs.

---

## Referensi File

| Yang diatur | File |
|-------------|------|
| Rules | `firestore.rules` |
| Indexes | `firestore.indexes.json` |
| Konfigurasi Firebase (termasuk path rules & indexes) | `firebase.json` |
| Cache Firestore di app | `lib/main.dart` (Settings persistenceEnabled & cacheSizeBytes) |

Dengan mengikuti panduan ini, konfigurasi Firestore (rules, cache HP, indexes) dan langkah deploy seharusnya bisa diikuti dengan mudah dan konsisten.
