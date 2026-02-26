# Device ID & Verifikasi Wajah

Dokumen ini menjelaskan fitur **Device ID** dan **Face Verification** yang diterapkan di pendaftaran dan login.

## Opsi "Pakai foto ini" (blur)

Saat validasi foto gagal karena blur, pengguna bisa:
- **Ulangi** – ambil foto lagi
- **Pakai foto ini** – tetap pakai foto tersebut (hanya muncul untuk error blur)

## Pool foto verifikasi (maks 3)

- Saat registrasi: 1 foto tersimpan di pool
- Saat login dari device baru + verifikasi wajah berhasil: foto selfie baru ditambah ke pool (maks 3)
- Jika pool sudah 3 dan foto baru lebih bagus (lebar×tinggi lebih besar) dari yang terburuk: foto terburuk diganti otomatis
- `face_verification.jpg` = foto utama untuk verifikasi (selalu foto terbaru yang berhasil)
- `faceVerificationPool` = array {url, width, height} di Firestore

## Face embedding (vektor) – dinonaktifkan

- `tensorflow_face_verification` bentrok dengan `face_verification` (tflite_flutter ^0.11 vs ^0.12)
- Saat ini: **image-based** (download gambar + face_verification)

## Anti-duplikat wajah (sesama role)

- Saat registrasi: wajah baru dibandingkan dengan semua user dengan **role sama** (penumpang vs penumpang, driver vs driver)
- Jika wajah sama dengan akun lain (role sama): tampil **"Anda Sudah punya Akun. Silakan login."**
- **Role berbeda diperbolehkan**: penumpang yang sudah punya akun boleh daftar driver (dan sebaliknya)
- Layanan: `lib/services/face_duplicate_check_service.dart`

## Optimasi untuk Indonesia

Aplikasi disesuaikan untuk **spesifikasi HP rata-rata pengguna Indonesia** (IDC 2024, ASP ~US\$195):

### Target perangkat
- **RAM**: 4–6 GB (Transsion, Xiaomi Redmi, Oppo A, Vivo Y, Samsung A0x)
- **Prosesor**: Unisoc T606, MediaTek Helio G36, Snapdragon 4xx
- **Kamera depan**: 5–8 MP
- **Layar**: 720p–1080p

### Konfigurasi (`lib/config/indonesia_config.dart`)
| Parameter | Nilai | Alasan |
|-----------|-------|--------|
| `cameraResolutionPreset` | low | Ringan di RAM & CPU |
| `sampleIntervalSearchMs` | 380 | Jeda lebih lama untuk CPU entry-level |
| `blurThresholdMin` | 80 | Toleran untuk kamera budget |
| `minResolutionWidth/Height` | 360 | Mendukung HP entry-level |
| `minBrightness` | 35 | Toleran low-light HP budget |
| `jpegQuality` | 70 | Ukuran file lebih kecil |
| `faceDetectorPerformanceMode` | fast | Ringan di CPU |

---

## 1. Ringkasan Fitur

1. **Device ID** – ID unik perangkat disimpan otomatis saat registrasi dan diambil saat login.
2. **Kamera Depan Saja** – Foto profil wajib diambil dari kamera depan.
3. **Verifikasi Wajah** – Deteksi wajah (ML Kit) + face recognition (FaceVerification) saat mengambil foto.
4. **Login dari Perangkat Baru** – Jika device ID berbeda dari yang tersimpan, user harus verifikasi wajah dengan selfie.

---

## 2. Device ID & Keamanan Device

### 2.1 Cara Kerja

- **Android**: `androidId` dari DeviceInfoPlugin
- **iOS**: `identifierForVendor`
- **Install ID**: UUID unik per install (SharedPreferences)
- **Fingerprint**: deviceId + OS version + model + installId (untuk keamanan)

### 2.2 Keamanan Device ID

| Fitur | Keterangan |
|-------|------------|
| **Cegah spam** | Maks 1 akun per role per device (1 penumpang + 1 driver = OK) |
| **Rate limit login** | Maks 10 gagal login per jam per device |
| **Deteksi emulator** | Registrasi dan login dari emulator diblokir |
| **OS + Model + Install ID** | Disimpan di Firestore untuk audit |

**Pengecualian**: Device sama untuk penumpang + driver diperbolehkan (user boleh punya kedua akun di HP yang sama).

### 2.3 Kapan Device ID Diambil

- **Login** – Saat halaman login terbuka (`initState`), Device ID diambil untuk mempersiapkan verifikasi.
- **Registrasi** – Saat user berhasil daftar, Device ID disimpan ke Firestore (`users/{uid}.deviceId`).

---

## 3. Foto Profil & Verifikasi Wajah

### 3.1 Kamera Depan Saja

- `ImagePicker.pickImage` menggunakan `preferredCameraDevice: CameraDevice.front`.

### 3.2 Alur Saat Ambil Foto

1. **Deteksi wajah** – ML Kit memastikan ada wajah di foto. Jika tidak terdeteksi, user diminta ulangi.
2. **Simpan foto** – Foto dipakai sebagai profil dan untuk verifikasi wajah.
3. **Upload ke Firebase Storage**:
   - `users/{uid}/photo.jpg` – foto profil
   - `users/{uid}/face_verification.jpg` – foto untuk verifikasi wajah (sama dengan profil)
4. **Face Verification (local)** – `FaceVerification.instance.registerFromImagePath` menyimpan embedding wajah di perangkat untuk verifikasi saat login dari perangkat yang sama.

---

## 4. Login dari Perangkat Baru

### 4.1 Kapan Verifikasi Wajah Diperlukan

Verifikasi wajah diperlukan jika:

- Device ID saat ini berbeda dengan `deviceId` di Firestore
- `faceVerificationUrl` di Firestore tidak kosong

### 4.2 Alur Verifikasi Wajah

1. Dialog muncul: "Perangkat baru terdeteksi. Ambil selfie untuk memverifikasi identitas Anda."
2. User mengambil selfie dengan kamera depan.
3. App mendownload `face_verification.jpg` dari Storage ke file sementara.
4. App mendaftarkan wajah tersimpan ke FaceVerification (sementara).
5. App memverifikasi selfie terhadap wajah tersimpan (`verifyFromImagePath`).
6. Jika cocok – login lanjut, `deviceId` di Firestore diperbarui.
7. Jika tidak cocok – login dibatalkan, pesan error ditampilkan.

---

## 5. Firebase

### 5.1 Firestore – field tambahan

| Field                | Jenis  | Keterangan                            |
|----------------------|--------|----------------------------------------|
| `deviceId`           | string | ID unik perangkat                      |
| `faceVerificationUrl`| string | URL foto wajah untuk verifikasi login  |

### 5.2 Storage – path

- `users/{uid}/photo.jpg` – foto profil
- `users/{uid}/face_verification.jpg` – foto wajah untuk verifikasi login

### 5.3 Security Rules – Collections Baru

Tambahkan rules untuk `device_accounts` dan `device_rate_limit`:

```
// device_accounts – cek "perangkat sudah punya akun role ini" saat buka halaman daftar (user belum login)
// Read harus true agar app bisa cek sebelum registrasi; write hanya untuk user yang sudah auth (setelah daftar).
match /device_accounts/{deviceId} {
  allow read: if true;
  allow create, update: if request.auth != null;
  allow delete: if false;
}

// device_rate_limit – dicatat saat login gagal (user belum auth)
match /device_rate_limit/{deviceId} {
  allow read, write: if true;
}
```

**Catatan**: `device_rate_limit` membutuhkan write tanpa auth karena login gagal = user belum terautentikasi.

---

## 6. User Lama (Sebelum Update)

User yang mendaftar sebelum fitur ini:

- `deviceId` dan `faceVerificationUrl` kosong atau tidak ada
- Login tetap normal tanpa verifikasi wajah
- Setelah login pertama, `deviceId` akan diperbarui jika kode menyediakan logic untuk itu
