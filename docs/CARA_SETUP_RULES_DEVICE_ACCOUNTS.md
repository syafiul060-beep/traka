# Cara Setup Firestore Rules untuk device_accounts (Langkah Rinci)

Dokumen ini menjelaskan **di mana** dan **bagaimana** menaruh rules untuk koleksi **`device_accounts`** dan **`device_rate_limit`** di Firebase Console, agar cek "perangkat sudah punya akun" saat buka halaman daftar berjalan.

---

## Di mana rules ini ditaruh?

Rules ditaruh di **Firebase Console → Firestore Database → tab Rules**.  
Rules untuk `device_accounts` dan `device_rate_limit` harus berada **di dalam** blok:

```text
match /databases/{database}/documents {
  // ... rules users, verification_codes, dll
  // TAMBAHKAN rules device_accounts dan device_rate_limit DI SINI
}
```

Jadi **lokasi tepatnya**: di **editor Rules** Firestore, **di dalam** `match /databases/{database}/documents { ... }`, **setelah** rule untuk `users` dan `verification_codes` (boleh sebelum atau sesudah, yang penting masih di dalam blok yang sama).

---

## Langkah 1: Buka Firebase Console

1. Buka browser, masuk ke: **https://console.firebase.google.com**
2. Login dengan akun Google yang dipakai untuk project Traka.
3. Pilih project Anda (misalnya **syafiul-traka**).

---

## Langkah 2: Buka Firestore Database

1. Di **menu sebelah kiri**, cari grup **"Build"** (atau **"Bangun"**).
2. Klik **"Firestore Database"** (bukan "Realtime Database").
3. Pastikan Anda di halaman Firestore (biasanya ada tab **Data**, **Rules**, **Indexes**).

---

## Langkah 3: Buka tab Rules

1. Di bagian atas halaman Firestore, klik tab **"Rules"** (atau **"Aturan"** jika bahasa Indonesia).
2. Anda akan melihat **editor teks** berisi rules yang sedang aktif.  
   Biasanya diawali dengan:
   - `rules_version = '2';`
   - `service cloud.firestore {`
   - `match /databases/{database}/documents {`
   - Lalu di dalamnya ada `match /users/...`, `match /verification_codes/...`, dll.

Ini adalah **satu-satunya tempat** di mana Anda mengubah rules Firestore. Rules untuk `device_accounts` ditaruh **di sini**, di dalam blok `match /databases/{database}/documents { ... }`.

---

## Langkah 4: Posisi tepat di dalam editor

Struktur rules Firestore harus seperti ini (urutan blok boleh berbeda):

```text
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    match /users/{userId} { ... }

    match /verification_codes/{email} { ... }

    // ========== TARUH RULES device_accounts DAN device_rate_limit DI SINI ==========
    match /device_accounts/{deviceId} { ... }
    match /device_rate_limit/{deviceId} { ... }
    // ========== AKHIR ==========

  }
}
```

Jadi:
- **Jangan** taruh di luar `match /databases/{database}/documents {`.
- **Jangan** taruh di dalam `match /users/...` atau `match /verification_codes/...`.
- **Taruh** sebagai blok **baru** di tingkat yang sama dengan `match /users/...` dan `match /verification_codes/...`, masih di dalam `match /databases/{database}/documents {`.

---

## Langkah 5: Teks rules yang harus ditambahkan

**Salin blok di bawah ini** (dari `// device_accounts` sampai `}` yang menutup `match /device_rate_limit/...`):

```javascript
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
```

Lalu **tempel** di editor Rules, **di dalam** `match /databases/{database}/documents { ... }`, misalnya setelah blok `verification_codes` dan sebelum kurung penutup `}` dari `match /databases/...`.

---

## Langkah 6: Contoh rules lengkap (jika ingin mengganti seluruh isi)

Jika Anda ingin memastikan struktur lengkap, berikut **contoh satu file rules lengkap** (users + verification_codes + device_accounts + device_rate_limit). Anda bisa ganti seluruh isi editor dengan ini, atau cukup **tambahkan** dua blok `device_accounts` dan `device_rate_limit` seperti di Langkah 5.

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

  }
}
```

**Penting:**  
- `device_accounts` dan `device_rate_limit` ada **di dalam** `match /databases/{database}/documents {`  
- Masing-masing punya **satu** blok `match /device_accounts/{deviceId} { ... }` dan `match /device_rate_limit/{deviceId} { ... }`.

---

## Langkah 7: Publish rules

1. Setelah menambah atau mengubah rules, klik tombol **"Publish"** (atau **"Terbitkan"**) di **bagian atas kanan** halaman Rules.
2. Jika ada peringatan, baca lalu konfirmasi dengan **Publish** lagi.
3. Tunggu sampai muncul pesan sukses (misalnya "Rules published successfully").
4. Rules langsung aktif; tidak perlu restart app.

---

## Ringkasan singkat

| Yang ditanya | Jawaban |
|--------------|---------|
| **Di mana?** | Firebase Console → Firestore Database → tab **Rules** |
| **Posisi di editor?** | Di **dalam** `match /databases/{database}/documents { ... }`, sebagai blok terpisah (satu tingkat dengan `match /users/...` dan `match /verification_codes/...`) |
| **Apa yang ditambah?** | Dua blok: `match /device_accounts/{deviceId} { ... }` dan `match /device_rate_limit/{deviceId} { ... }` dengan isi seperti di Langkah 5 |
| **Setelah ubah?** | Harus klik **Publish** agar rules aktif |

Setelah rules dipublish, saat user buka halaman daftar penumpang/driver, app akan bisa **baca** koleksi `device_accounts` untuk cek apakah perangkat itu sudah punya akun dengan role yang sama. Tanpa `allow read: if true` untuk `device_accounts`, cek tersebut gagal dan registrasi ganda (role sama, device sama) tetap bisa terjadi.
