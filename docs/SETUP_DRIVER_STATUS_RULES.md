# Setup Firestore Rules untuk Driver Status

## Langkah-langkah

### 1. Buka Firebase Console
- Buka [Firebase Console](https://console.firebase.google.com/)
- Pilih project **Traka**

### 2. Buka Firestore Rules
- Di menu kiri, klik **Firestore Database**
- Klik tab **Rules**

### 3. Copy Paste Rules Lengkap

**Hapus semua rules yang lama** di editor Firebase, lalu **copy-paste** rules lengkap di bawah ini:

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

    // device_accounts – baca diperbolehkan agar app bisa cek "perangkat sudah punya akun" saat buka daftar
    match /device_accounts/{deviceId} {
      allow read: if true;
      allow create, update: if request.auth != null;
      allow delete: if false;
    }

    // device_rate_limit – dicatat saat login gagal (user belum auth)
    match /device_rate_limit/{deviceId} {
      allow read, write: if true;
    }

    // driver_status – status dan lokasi driver yang sedang aktif (siap kerja dengan rute)
    match /driver_status/{driverId} {
      // Baca: semua orang bisa baca (agar penumpang bisa cari travel)
      allow read: if true;
      // Tulis: hanya driver yang login dan mengupdate data miliknya sendiri
      allow write: if request.auth != null && request.auth.uid == driverId;
    }

  }
}
```

> **Catatan:** File `docs/FIRESTORE_RULES_LENGKAP.txt` berisi rules yang sama. Bisa copy-paste dari file tersebut juga.

### 4. Publish Rules
- Klik tombol **Publish** di kanan atas
- Tunggu sampai rules aktif (beberapa detik)

## Verifikasi

Setelah rules di-publish, coba jalankan aplikasi dan:
1. Login sebagai driver
2. Buka halaman beranda driver
3. Klik tombol "Siap Kerja" (hijau) dan buat rute
4. Buka Firebase Console → Firestore Database → Data
5. Akan muncul collection baru: `driver_status`
6. Di dalam collection, akan ada document dengan ID = UID driver
7. Document berisi: `status`, `latitude`, `longitude`, `routeOriginLat`, `routeDestLat`, dll.

## Struktur Data

Collection `driver_status` akan terlihat seperti ini di Firestore:

```
driver_status/
  └── {driverId} (UID driver)
      ├── uid: "abc123..."
      ├── status: "siap_kerja"
      ├── latitude: -3.3194
      ├── longitude: 114.5907
      ├── lastUpdated: Timestamp (12 Jan 2026, 10:30:45)
      ├── routeOriginLat: -3.3194
      ├── routeOriginLng: 114.5907
      ├── routeDestLat: -3.4200
      ├── routeDestLng: 115.1234
      ├── routeOriginText: "Mekarjaya, Tanah Bumbu, Kalimantan Selatan"
      └── routeDestText: "Banjarmasin, Kalimantan Selatan"
```

## Troubleshooting

### Error: "Missing or insufficient permissions"
- Pastikan rules sudah di-publish
- Pastikan user sudah login (FirebaseAuth.instance.currentUser tidak null)
- Pastikan driverId di path sama dengan user.uid

### Data tidak muncul di Firestore
- Cek koneksi internet
- Cek apakah driver sudah klik "Siap Kerja" dan buat rute
- Tunggu 10-15 detik (update pertama kali butuh waktu)
- Lihat log di terminal: `flutter run --verbose`
