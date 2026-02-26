# Langkah Ubah Package Name Secara Manual (Android)

Panduan ini untuk mengubah **package name** (Application ID) aplikasi Android Traka secara manual. Saat ini project memakai **`id.traka.app`**. Jika Anda perlu mengubah ke nama lain atau menerapkan di project baru, ikuti langkah di bawah.

---

## Yang Diubah

| Yang diubah | Lokasi | Nilai saat ini |
|-------------|--------|-----------------|
| Application ID & namespace | `android/app/build.gradle.kts` | `id.traka.app` |
| Package deklarasi Kotlin | `android/app/src/main/kotlin/id/traka/app/MainActivity.kt` | `package id.traka.app` |
| Folder struktur Kotlin | `android/app/src/main/kotlin/id/traka/app/` | Satu folder per segmen package |
| Default packageName (backend) | `functions/index.js` (verifyContributionPayment) | `id.traka.app` |
| Firebase / google-services.json | Unduh ulang dari Firebase Console | Sesuaikan package name di project Firebase |

---

## Langkah 1: Ubah di build.gradle.kts

1. Buka file **`android/app/build.gradle.kts`**.
2. Cari blok **`android {`**.
3. Ubah **`namespace`**:
   - Dari: `namespace = "com.example.traka"` (atau nilai lama)
   - Menjadi: `namespace = "id.traka.app"` (atau package name baru Anda, contoh: `id.perusahaan.app`).
4. Di blok **`defaultConfig {`**, ubah **`applicationId`**:
   - Dari: `applicationId = "com.example.traka"`
   - Menjadi: `applicationId = "id.traka.app"` (harus sama dengan namespace).
5. Simpan.

---

## Langkah 2: Struktur Folder dan MainActivity.kt (Kotlin/Java)

Package name menentukan **struktur folder** dan **baris `package`** di file Kotlin/Java.

**Contoh:** package name **`id.traka.app`** → folder: **`kotlin/id/traka/app/`**.

### 2.1 Buat folder baru

Di dalam **`android/app/src/main/kotlin/`**:

- Untuk **`id.traka.app`**: buat folder **`id`** → di dalamnya **`traka`** → di dalamnya **`app`**.
- Jadi path lengkap: **`android/app/src/main/kotlin/id/traka/app/`**.

### 2.2 Pindahkan / buat MainActivity.kt

1. **Jika sudah ada MainActivity di package lama** (misalnya di `kotlin/com/example/traka/MainActivity.kt`):
   - Buka file tersebut.
   - Baris pertama: ubah **`package com.example.traka`** menjadi **`package id.traka.app`** (sesuai package name baru).
   - Simpan isi file.
   - Buat file baru di **`kotlin/id/traka/app/MainActivity.kt`** dengan isi yang sudah diubah (package + kode).
   - Hapus file lama **`kotlin/com/example/traka/MainActivity.kt`**.
2. **Jika belum ada:** buat **`MainActivity.kt`** di **`kotlin/id/traka/app/`** dengan baris pertama **`package id.traka.app`** dan kode activity yang dipakai project.

### 2.3 Hapus folder lama (opsional)

Setelah MainActivity dipindah dan build sukses, Anda bisa hapus folder kosong package lama, misalnya **`kotlin/com/example/traka/`** dan **`kotlin/com/example/`** jika kosong.

---

## Langkah 3: Firebase & google-services.json

Package name harus sama dengan yang didaftarkan di **Firebase Console**.

1. Buka [Firebase Console](https://console.firebase.google.com) → pilih project Traka.
2. **Project settings** (ikon roda) → tab **General** → bagian **Your apps**.
3. Jika aplikasi Android sudah ada dengan package lama (**com.example.traka**):
   - Anda bisa **tambah aplikasi Android baru** dengan package **`id.traka.app`**, lalu unduh **google-services.json** baru.
   - Ganti file **`android/app/google-services.json`** dengan yang baru.
4. Jika belum ada: tambah aplikasi Android, isi package name **`id.traka.app`**, unduh **google-services.json**, letakkan di **`android/app/`**.

---

## Langkah 4: Cloud Functions (verifikasi pembayaran)

Jika ada callable untuk verifikasi pembayaran Google Play yang memakai **packageName**:

1. Buka **`functions/index.js`**.
2. Cari **`verifyContributionPayment`** (atau fungsi yang memakai `packageName`).
3. Ubah default **packageName** ke package name baru, misalnya:
   - `const packageName = (data?.packageName || "id.traka.app").toString();`
4. Deploy ulang Functions: `firebase deploy --only functions`.

---

## Langkah 5: Google Play Console & Billing

- Di **Play Console**, aplikasi didaftarkan dengan **satu package name**. Jika Anda **sudah publish** dengan **com.example.traka**, Anda **tidak bisa** mengubah package name aplikasi yang sama; Anda harus buat **aplikasi baru** di Play Console dengan package **id.traka.app**.
- **In-app products** (Billing) terikat ke aplikasi (package name). Pastikan di Play Console aplikasi memakai package name **id.traka.app** dan Product ID (misalnya **traka_contribution_once**) sudah dibuat untuk aplikasi tersebut.

---

## Langkah 6: Cek dan Build

1. Di **`android/app/build.gradle.kts`** pastikan lagi **namespace** dan **applicationId** sama dengan package name yang diinginkan.
2. Bersihkan build:
   - `cd android && ./gradlew clean && cd ..`
   - Atau lewat Flutter: `flutter clean`.
3. Build:
   - `flutter pub get`
   - `flutter build apk` atau `flutter build appbundle`.

Jika ada error **“package … does not exist”** atau **“Unresolved reference”**, pastikan:
- Path folder Kotlin sesuai package (satu folder per segmen),
- Baris **`package ...`** di **MainActivity.kt** persis sama dengan package name di **build.gradle.kts**.

---

## Ringkasan Cek List (Package name: id.traka.app)

- [ ] **android/app/build.gradle.kts**: `namespace = "id.traka.app"` dan `applicationId = "id.traka.app"`.
- [ ] **android/app/src/main/kotlin/id/traka/app/MainActivity.kt** ada dan baris pertama: `package id.traka.app`.
- [ ] File/folder package lama (misalnya **com/example/traka**) sudah dihapus atau tidak lagi dipakai.
- [ ] **android/app/google-services.json** dari Firebase untuk package **id.traka.app**.
- [ ] **functions/index.js**: default **packageName** = **id.traka.app** (jika dipakai).
- [ ] **Play Console**: aplikasi terdaftar dengan package **id.traka.app** (untuk Billing/upload AAB).

Setelah semua sesuai, build dan jalankan aplikasi seperti biasa.

---

## Setelah Ganti Firebase Project (mis. ke id.traka.app)

Jika Anda **ganti ke project Firebase baru** (bukan hanya tambah Android app di project yang sama):

1. **Data Order driver kosong?**  
   - Aplikasi punya **fallback**: jika **driver_status** kosong, **routeJourneyNumber** diambil dari order aktif driver (agreed/picked_up). Pesanan bisa muncul selama **ada order** untuk driver itu di project yang sama.
   - Di layar Data Order driver, jika masih tampil "Belum ada rute aktif", tap **「Muat ulang」** (setelah driver buka Beranda > Siap Kerja lebih dulu jika perlu).

2. **Pastikan data satu project:**  
   - App driver dan app penumpang harus pakai **project Firebase yang sama** (file **google-services.json** dari project yang sama).
   - **orders** dan **users** harus ada di project itu. Jika project benar-benar baru, **driverUid** di dokumen order harus sama dengan **UID driver yang login** di project itu (biasanya beda project = beda UID).

3. **Agar driver_status terisi lagi:**  
   Driver buka **Beranda** → **Siap Kerja** → pilih/set **rute** (asal–tujuan). Setelah itu **driver_status** terisi dan Data Order bisa memuat pesanan. Lalu di Data Order tap **Muat ulang** jika masih kosong.

4. **Deploy Functions:**  
   `firebase deploy --only functions` dipakai agar **Cloud Functions** (verifikasi pembayaran, notifikasi, dll.) jalan di project yang dipakai. Itu **tidak** mengisi **driver_status** atau **orders**; data itu ada di Firestore dan harus dari app (driver/penumpang) atau dari migrasi data.

5. **Tombol Selesai Bekerja tidak bisa diklik (padahal penumpang/barang 0):**  
   - Setelah ganti project, query hitung order bisa gagal (index/project). Aplikasi sekarang menganggap 0 jika query error, sehingga tombol **Selesai Bekerja** tetap bisa diklik. Pastikan app driver build terbaru.
   - Jika tombol masih tidak bereaksi: pastikan **driver_status** dan **orders** di project yang sama; lalu coba **force close** app driver dan buka lagi, lalu tap **Selesai Bekerja**.

6. **Penumpang tidak menemukan driver (status Siap Kerja aktif di HP driver):**  
   - **Driver dan penumpang harus pakai project Firebase yang sama** (satu **google-services.json** untuk satu project). Jika HP driver pakai project A dan HP penumpang pakai project B, penumpang tidak akan melihat driver.
   - Pastikan di HP driver: setelah **Siap Kerja** dan pilih rute, lokasi GPS aktif dan app sempat mengirim **driver_status** ke Firestore (biasanya otomatis setelah dapat lokasi). Buka **Beranda** sekali, tunggu beberapa detik, lalu di HP penumpang coba **Cari travel** lagi.
   - Di **Firebase Console** → **Firestore** → collection **driver_status**: cek apakah ada dokumen dengan **ID = UID driver** yang login, dan field **status** = `siap_kerja`. Jika tidak ada, artinya app driver belum menulis; pastikan login driver dan project Firebase sama.

7. **Riwayat (data sebelum ganti id.traka.app) tidak ada lagi:**  
   - Data riwayat (tab **Riwayat Rute** driver, **Riwayat** penumpang, pesanan selesai) disimpan di Firestore menurut **UID** user yang login (collection `route_sessions`, `trips`, `orders` dengan status completed).
   - **Penyebab hilang:** Setelah ganti ke **id.traka.app** Anda biasanya pakai **project Firebase baru**. Data lama (riwayat, pesanan selesai) ada di **project lama** dan terikat **UID lama**. App baru baca dari **project baru** dengan **UID baru** (akun login baru) sehingga riwayat kosong. Data lama **tidak hilang**—masih di project lama, tapi app baru tidak mengakses project itu.
   - **Opsi:**
     - **Tetap pakai project baru:** Riwayat hanya berisi data **setelah** pakai id.traka.app. Data lama tetap ada di project lama jika Anda tidak hapus.
     - **Ingin lihat riwayat lama:** Harus **migrasi data** dari project lama ke project baru (export Firestore `route_sessions`, `trips`, `orders`, `users` dari project lama, lalu import ke project baru; dan/atau sesuaikan `driverUid`/`passengerUid` dengan UID di project baru). Atau sementara pakai app build lama (package lama) + project lama hanya untuk cek riwayat.
     - **Satu project untuk kedua package:** Jika Anda **tidak** ganti project dan hanya menambah Android app id.traka.app di project yang sama, lalu login dengan **akun yang sama** (email/HP sama), UID tetap sama sehingga riwayat lama seharusnya masih tampil. Jika tidak, cek di Firestore apakah dokumen di `route_sessions` / `trips` / `orders` punya `driverUid`/`passengerUid` = UID yang login sekarang.

8. **Kalau tetap tidak bisa:**  
   - Cek di **Firebase Console** → **Firestore**: apakah ada collection **orders** dengan dokumen yang **driverUid**-nya = UID driver yang login?
   - Cek **Authentication**: apakah driver login di project yang sama dengan tempat data orders disimpan?
   - Jika project baru dan data lama di project lain, perlu **migrasi/copy** data (orders, users, driver_status, route_sessions, trips) ke project baru, atau pastikan flow buat order dan "Siap Kerja" sudah jalan di project baru sehingga data terisi.
