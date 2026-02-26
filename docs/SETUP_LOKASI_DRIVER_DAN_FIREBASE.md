# Setup Lokasi Driver dan Firebase

Dokumen ini menjelaskan fitur lokasi untuk pendaftaran driver (izin, ambil lokasi, reverse geocoding, simpan ke Firestore) dan langkah konfigurasi Firebase jika diperlukan.

---

## Ringkasan Fitur

- **Proteksi Fake GPS:** Di Android, aplikasi mendeteksi lokasi palsu (mock location). Jika terdeteksi, muncul peringatan *"Aplikasi Traka melindungi pengguna dari berbagai modus kejahatan yang disengaja, matikan Fake GPS/Lokasi palsu jika ingin menggunakan Traka...!"* dan pendaftaran driver tidak dilanjutkan. Detail keamanan: lihat **`docs/KEAMANAN_APLIKASI_TRAKA.md`**.

- **Pendaftaran driver:** Saat user mendaftar sebagai **driver**, aplikasi akan:
  1. Meminta izin lokasi (jika belum diberikan).
  2. Mengambil lokasi handphone driver secara otomatis (GPS).
  3. Reverse geocoding: dari koordinat (lat/lng) ke negara dan provinsi/region.
  4. **Validasi:** Jika lokasi di luar Indonesia → tampilkan pesan **"Bahwa Traka hanya dapat di gunakan di Indonesia"** dan pendaftaran tidak bisa dilanjutkan.
  5. Jika lokasi di Indonesia → simpan **region/provinsi** dan koordinat (**latitude**, **longitude**) ke Firestore bersama data driver.

- **Pendaftaran penumpang:** Tidak memakai lokasi; tidak ada perubahan.

---

## 1. Izin Lokasi

### Android

Izin lokasi sudah dideklarasikan di **`android/app/src/main/AndroidManifest.xml`**:

- `ACCESS_FINE_LOCATION`
- `ACCESS_COARSE_LOCATION`
- `ACCESS_BACKGROUND_LOCATION` (opsional, untuk akses di background)

Tidak perlu menambah deklarasi izin lagi. Saat pertama kali pendaftaran driver, aplikasi akan meminta izin lokasi ke user (permission prompt).

### iOS

Izin lokasi sudah dideklarasikan di **`ios/Runner/Info.plist`**:

- `NSLocationAlwaysAndWhenInUseUsageDescription`
- `NSLocationWhenInUseUsageDescription`

Tidak perlu menambah key baru. Saat pertama kali, sistem akan menampilkan dialog izin lokasi.

---

## 2. Ambil Lokasi (GPS)

- Menggunakan package **`geolocator`**.
- Setelah izin diberikan, aplikasi memanggil **`Geolocator.getCurrentPosition()`** dengan akurasi **high**.
- Hasil: **latitude** dan **longitude**.

Jika GPS mati atau izin ditolak, akan ada pesan error dan pendaftaran driver tidak bisa dilanjutkan sampai lokasi berhasil didapat.

---

## 3. Reverse Geocoding

- Menggunakan package **`geocoding`**.
- Dari **latitude** dan **longitude** → memanggil **`placemarkFromCoordinates()`**.
- Dari placemark diambil:
  - **Negara** (`country`) → untuk cek Indonesia.
  - **Provinsi/region** (`administrativeArea` atau `subAdministrativeArea`) → disimpan sebagai **region** driver.

Indonesia dianggap cocok jika nama negara mengandung **"Indonesia"**, **"ID"**, atau **"Republic of Indonesia"** (case insensitive).

---

## 4. Validasi Indonesia dan Pesan Error

- Jika **negara bukan Indonesia** → tampilkan SnackBar merah:
  - **ID:** *"Bahwa Traka hanya dapat di gunakan di Indonesia"*
  - **EN:** *"Traka can only be used in Indonesia"*
  - Pendaftaran dihentikan (return), data tidak disimpan.

- Jika **gagal dapat lokasi** (izin ditolak, GPS error, timeout, dll.) → tampilkan pesan error dari service (misalnya: *"Tidak dapat memperoleh lokasi. Pastikan izin lokasi diaktifkan dan GPS menyala."*).

---

## 5. Simpan ke Firestore

### Collection: `users`

Document driver di **`users/{uid}`** sekarang bisa berisi field tambahan:

| Field        | Tipe    | Keterangan                                      |
|-------------|---------|--------------------------------------------------|
| `role`      | string  | `"driver"`                                      |
| `email`     | string  | Email driver                                    |
| `displayName` | string | Nama                                            |
| `photoUrl`  | string  | URL foto profil                                 |
| `createdAt` | timestamp | Waktu dibuat                                  |
| **`region`**  | string  | **Provinsi/region dari reverse geocoding** (hanya driver) |
| **`latitude`** | number  | **Koordinat latitude** (hanya driver)          |
| **`longitude`** | number | **Koordinat longitude** (hanya driver)         |

- **Penumpang:** tidak ada field `region`, `latitude`, `longitude`.
- **Driver:** `region`, `latitude`, `longitude` diisi otomatis dari lokasi handphone saat daftar.

### Contoh document driver di Firestore

```json
{
  "role": "driver",
  "email": "driver@example.com",
  "displayName": "Budi",
  "photoUrl": "https://...",
  "createdAt": "<timestamp>",
  "region": "Kalimantan Selatan",
  "latitude": -3.3194,
  "longitude": 114.5907
}
```

---

## 6. Konfigurasi Firebase yang Diperlukan

Bagian ini menjelaskan **apa saja yang harus diatur di Firebase** agar fitur lokasi driver (termasuk penyimpanan **region**, **latitude**, **longitude** ke Firestore) berjalan dengan benar. Hanya **Firestore Security Rules** yang perlu dicek/diubah; Authentication dan Storage tidak berubah.

**Ringkasan singkat:**

| Yang perlu dilakukan | Di mana | Untuk apa |
|---------------------|---------|-----------|
| Atur Firestore Security Rules untuk collection `users` | Firebase Console → Firestore Database → Rules | Agar aplikasi boleh menulis data driver (termasuk region, latitude, longitude) ke `users/{uid}` |
| Publish rules | Tombol "Publish" di tab Rules | Agar rule aktif dan dipakai Firestore |

Tidak perlu mengubah Authentication, Storage, atau membuat collection baru.

---

### 6.1 Firestore Security Rules – Penjelasan Singkat

**Apa itu Security Rules?**  
Rules di Firestore menentukan **siapa boleh baca/tulis** data. Tanpa rule yang benar, aplikasi bisa dapat error **permission-denied** saat menyimpan data driver (termasuk field region, latitude, longitude).

**Mengapa untuk `users`?**  
Saat driver mendaftar, aplikasi menyimpan data ke collection **`users`** dengan document id = **uid** (ID user dari Firebase Auth). Field yang disimpan antara lain: **role**, **email**, **displayName**, **photoUrl**, **createdAt**, dan untuk driver ditambah **region**, **latitude**, **longitude**. Supaya operasi **tulis** ini diizinkan, rule untuk **`users`** harus mengizinkan **write** oleh user yang login ke document miliknya sendiri.

**Apakah field region/latitude/longitude butuh rule khusus?**  
Tidak. Firestore mengatur per **document**, bukan per field. Jadi selama **write** ke **`users/{userId}`** oleh user dengan **uid = userId** sudah diizinkan, maka **semua field** (termasuk region, latitude, longitude) ikut ter-allow. Tidak perlu konfigurasi tambahan di Firebase Console khusus untuk field tersebut.

---

### 6.2 Cara Mengatur Firestore Security Rules (Langkah Terperinci)

Ikuti langkah berikut satu per satu.

#### Langkah 1: Buka Firebase Console

1. Buka browser (Chrome, Edge, atau lainnya) dan ketik di address bar: **https://console.firebase.google.com/** lalu Enter.
2. Jika belum login, masuk dengan **akun Google** yang dipakai untuk project Traka. Jika sudah login, Anda akan langsung melihat daftar project.
3. Di halaman utama (**Project Overview**), cari **nama project** Traka Anda (misalnya **syafiul-traka** atau **traka**) lalu **klik** pada kartu project tersebut.
   - **Yang akan Anda lihat:** Setelah diklik, Anda masuk ke dashboard project (menu kiri: Build, Release, Analytics, dll.).

#### Langkah 2: Buka Halaman Firestore Rules

1. Di **menu sebelah kiri**, cari grup **"Build"** (atau **"Bangun"**). Di dalamnya ada: Authentication, Firestore Database, Storage, dll.
2. Klik **"Firestore Database"**. Jangan keliru dengan "Realtime Database"; yang dipakai Traka adalah **Firestore**.
3. Setelah halaman Firestore terbuka, di **bagian atas** Anda akan melihat beberapa tab, misalnya **"Data"**, **"Rules"**, **"Indexes"**. Klik tab **"Rules"** (atau **"Aturan"** jika bahasa Indonesia).
4. **Yang akan Anda lihat:** Sebuah editor teks (kotak besar) berisi rule yang sedang aktif. Biasanya diawali dengan `rules_version = '2';` dan `service cloud.firestore { ... }`. Ini adalah file rule Firestore Anda.

#### Langkah 3: Pahami Isi Rule yang Diperlukan

Rule untuk collection **`users`** harus mengizinkan:

- **Read (baca):**  
  Di aplikasi Traka, read ke **`users`** dipakai untuk: (1) cek email sudah terdaftar saat kirim kode verifikasi, (2) cek role setelah login. Untuk memudahkan, bisa di-set **allow read: if true** (semua orang boleh baca). Untuk production nanti bisa disempitkan jika perlu.

- **Write (tulis):**  
  Hanya user yang **sedang login** dan **uid-nya sama dengan document id** yang boleh menulis. Jadi: **allow write: if request.auth != null && request.auth.uid == userId**.

**Arti singkat:**

- **`request.auth`** = informasi user yang sedang login (dari Firebase Auth).
- **`request.auth != null`** = pasti ada user yang login.
- **`request.auth.uid`** = ID unik user tersebut.
- **`userId`** = nilai dari **`{userId}`** di path **`users/{userId}`** (document id).
- Jadi **write** hanya diizinkan ke document **`users/<uid_user_yang_login>`**.

Dengan ini, saat pendaftaran driver, aplikasi yang sudah login (setelah **createUserWithEmailAndPassword**) boleh melakukan **set** ke **`users/<uid>`** termasuk mengisi **region**, **latitude**, **longitude**.

#### Langkah 4: Salin atau Sesuaikan Rule di Editor

Di tab **Rules**, pastikan ada rule untuk collection **`users`**. Berikut **versi lengkap** yang bisa Anda salin-tempel (untuk Traka: users + verification_codes):

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // Collection users: data profil (penumpang & driver, termasuk region/latitude/longitude)
    match /users/{userId} {
      // Semua orang boleh baca (untuk validasi email terdaftar & ambil role saat login)
      allow read: if true;

      // Hanya user yang login boleh tulis ke document miliknya (uid = userId)
      allow write: if request.auth != null && request.auth.uid == userId;
    }

    // Collection verification_codes: kode verifikasi email
    match /verification_codes/{email} {
      // Create/read/delete untuk kirim dan cek kode verifikasi
      allow create, read, delete: if true;
      // Kode hanya dibuat sekali, tidak perlu update
      allow update: if false;
    }
  }
}
```

**Catatan:** Jika Anda punya baris seperti `// allow write: if true;` (untuk development), jangan diaktifkan di production — itu membuka akses tulis ke semua user. Versi di atas sudah aman untuk production.

**Penting:**

- Jika Anda **sudah punya** rule untuk **`verification_codes`** atau collection lain, **jangan hapus**. Cukup **tambahkan atau sesuaikan** blok **`match /users/{userId}`** seperti di atas.
- Pastikan tidak ada **typo** (misalnya `users` vs `user`, `userId` vs `userID`). Nama path dan variabel harus persis sama.

**Hal yang sering salah:**

- Lupa **Publish** setelah mengubah rule — rule hanya aktif setelah Anda klik Publish.
- Salah path: rule harus untuk **`users`** (bentuk jamak), bukan **`user`**.
- Kondisi write salah: harus **`request.auth.uid == userId`** (userId dari path `users/{userId}`), bukan email atau field lain.

#### Langkah 5: Publish Rules

1. Setelah rule di editor sudah benar, cari tombol **"Publish"** (atau **"Terbitkan"**) di **bagian atas kanan** halaman Rules. Klik tombol tersebut.
2. Jika muncul **peringatan** (misalnya "Rules will override existing rules" atau "Aturan akan menimpa aturan yang ada"), baca isinya lalu klik **"Publish"** lagi untuk konfirmasi.
3. **Tunggu** sampai muncul **pesan sukses** (biasanya "Rules published successfully" atau serupa) — umumnya hanya beberapa detik.
4. **Hasil:** Rule baru langsung aktif di seluruh project. Aplikasi Traka yang menyimpan data driver (termasuk region, latitude, longitude) ke **`users/{uid}`** tidak akan lagi mendapat error **permission-denied** karena write sudah diizinkan untuk user yang login ke document miliknya.

#### Langkah 6: Verifikasi (Opsional)

1. Di Firebase Console, tetap di **Firestore Database**.
2. Klik tab **"Data"** (atau **"Data"**).
3. Setelah ada driver yang mendaftar, cek collection **`users`**.
4. Buka salah satu document dengan field **role = driver**.
5. Pastikan ada field **region**, **latitude**, **longitude**. Jika ada dan nilainya sesuai lokasi driver, konfigurasi Firestore sudah benar.

---

### 6.3 Bagian Firebase Lain (Tidak Perlu Diubah)

Agar tidak bingung, berikut bagian Firebase yang **tidak perlu** Anda ubah untuk fitur lokasi driver:

- **Firestore Database (struktur data):**  
  Hanya dipakai collection **`users`** yang sudah ada. **Tidak perlu** membuat collection baru (misalnya `driver_locations`). Field **region**, **latitude**, **longitude** hanya **field tambahan** di document driver yang sama (`users/{uid}`). Firestore otomatis menerima field baru selama rule mengizinkan write ke document tersebut.

- **Authentication:**  
  Tetap dipakai untuk login/registrasi (email & password). Tidak perlu menambah provider, mengubah sign-in method, atau pengaturan lain untuk fitur lokasi driver.

- **Storage:**  
  Tetap dipakai untuk foto profil (upload foto saat daftar). Tidak ada bucket atau rule baru yang perlu dibuat untuk fitur lokasi driver.

**Kesimpulan:** Satu-satunya konfigurasi yang perlu Anda lakukan di Firebase Console untuk fitur lokasi driver adalah **Firestore Security Rules** untuk collection **`users`** seperti dijelaskan di 6.1 dan 6.2.

---

## 7. Langkah Terperinci (Ringkas) – Dari Awal Sampai Selesai

Bagian ini merangkum **urutan langkah** dari sisi kode (sudah diimplementasi) dan dari sisi Firebase (yang harus Anda lakukan jika belum). Cocok untuk dibaca sebelum mulai atau sebagai checklist.

---

### 7.1 Di Aplikasi (Kode – Sudah Diimplementasi)

Tidak perlu mengubah kode lagi; berikut yang sudah dilakukan di aplikasi dan **di mana** Anda bisa mengeceknya:

1. **Izin lokasi**  
   Di **`lib/services/location_service.dart`**, fungsi **`requestPermission()`** mengecek dan meminta izin lokasi (jika belum diberikan). Dipanggil **sebelum** mengambil koordinat. Saat user daftar sebagai driver, dialog izin lokasi akan muncul jika belum pernah diizinkan.

2. **Ambil koordinat**  
   - **Android:** melalui **platform channel** ke native (**MainActivity**) dengan cek **Fake GPS** (mock location). Jika terdeteksi palsu, pendaftaran dihentikan dan pesan peringatan ditampilkan.  
   - **Platform lain:** **`getCurrentPosition()`** dari package **geolocator** untuk mendapatkan **latitude** dan **longitude**.

3. **Reverse geocoding**  
   Koordinat (lat, lng) dikonversi ke alamat dengan **`placemarkFromCoordinates()`** (package **geocoding**) untuk mendapatkan **negara** (`country`) dan **region/provinsi** (`administrativeArea` atau serupa). Negara dipakai untuk validasi Indonesia; region disimpan ke Firestore.

4. **Validasi Indonesia**  
   Jika **negara** bukan Indonesia, aplikasi menampilkan SnackBar dengan pesan *"Bahwa Traka hanya dapat di gunakan di Indonesia"* dan menghentikan pendaftaran driver (data tidak dikirim ke Firestore).

5. **Simpan ke Firestore**  
   Hanya jika lokasi valid (di Indonesia dan bukan Fake GPS): saat menyimpan document driver di **`users/{uid}`**, aplikasi menambahkan field **region**, **latitude**, **longitude** ke data yang sudah ada (role, email, displayName, photoUrl, createdAt). Satu document = satu driver dengan uid dari Firebase Auth.

---

### 7.2 Di Firebase (Yang Harus Anda Lakukan)

Lakukan **sekali**; setelah itu semua driver yang mendaftar akan tersimpan dengan benar (termasuk region, latitude, longitude). Jika rule sudah pernah diatur untuk `users`, cukup pastikan isinya sesuai lalu Publish jika ada perubahan.

| No | Langkah | Keterangan singkat |
|----|---------|---------------------|
| 1 | **Buka Firebase Console** | Masuk ke **https://console.firebase.google.com/** dan pilih **project Traka** Anda. |
| 2 | **Buka Firestore Rules** | Menu kiri: **Firestore Database** → tab atas: **Rules**. Pastikan yang dibuka Firestore (bukan Realtime Database). |
| 3 | **Pastikan rule untuk `users`** | Di editor Rules harus ada **`match /users/{userId}`** dengan **allow read** (misalnya `if true`) dan **allow write: if request.auth != null && request.auth.uid == userId**. |
| 4 | **Publish** | Klik **Publish** di halaman Rules. Tunggu pesan sukses. Setelah itu rule aktif dan aplikasi tidak akan kena **permission-denied** saat simpan data driver. |

**Catatan:** Tidak perlu mengaktifkan API atau produk Firebase tambahan untuk fitur lokasi driver; cukup Firestore Security Rules seperti di atas. Authentication dan Storage tidak perlu diubah.

---

## 8. Troubleshooting

### Pesan "Tidak dapat memperoleh lokasi"

- Pastikan **izin lokasi** diberikan ke aplikasi (Settings → Apps → Traka → Permissions).
- Pastikan **GPS/lokasi** perangkat dalam keadaan hidup.
- Di emulator: set koordinat manual (misalnya untuk Indonesia) agar reverse geocoding mengembalikan Indonesia.

### Lokasi terbaca negara lain padahal di Indonesia

- Pastikan GPS akurat (uji di luar ruangan atau dengan WiFi/cellular).
- Di emulator, pastikan lokasi default atau mock location diset ke koordinat di Indonesia.

### Field `region` / `latitude` / `longitude` tidak muncul di Firestore

- Pastikan user mendaftar sebagai **driver** (bukan penumpang).
- Pastikan tidak ada error sebelum `userData['region'] = ...` (cek log di debug console).
- Pastikan Firestore Rules mengizinkan write ke `users/{uid}`.

---

## 9. Package yang Digunakan

- **geolocator** – izin lokasi dan pembacaan koordinat GPS.
- **geocoding** – reverse geocoding (koordinat → negara, region).

Keduanya sudah ditambahkan di **`pubspec.yaml`**. Jalankan **`flutter pub get`** jika belum.

---

Dengan ini, pendaftaran driver akan memakai lokasi handphone, memastikan hanya lokasi di Indonesia yang bisa daftar, dan menyimpan region serta koordinat ke Firestore tanpa perlu konfigurasi Firebase tambahan selain Security Rules yang sudah umum dipakai.
