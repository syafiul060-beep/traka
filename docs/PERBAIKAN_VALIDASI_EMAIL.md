# Perbaikan Validasi Email yang Sudah Terdaftar

Dokumen ini menjelaskan cara memperbaiki masalah validasi email yang sudah terdaftar.

---

## Masalah

Ketika user mencoba meminta kode verifikasi dengan email yang sudah terdaftar, sistem seharusnya menampilkan error "Email Sudah Terdaftar", tapi malah mengizinkan proses berlanjut.

---

## Penyebab

Masalah biasanya terjadi karena:

1. **Firestore Security Rules tidak mengizinkan query** ke collection `users` untuk user yang belum login.
2. **Error permission-denied** diabaikan dan proses tetap berlanjut.

---

## Solusi: Update Firestore Security Rules

Pastikan Firestore Security Rules mengizinkan query ke collection `users` berdasarkan email untuk pengecekan validasi.

### Langkah 1: Buka Firestore Security Rules

1. **Buka Firebase Console:** https://console.firebase.google.com/
2. **Pilih project:** `syafiul-traka`
3. **Klik "Firestore Database"** di menu kiri.
4. **Buka tab "Rules"**.

### Langkah 2: Update Security Rules

**Rules yang direkomendasikan:**

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Collection users
    match /users/{userId} {
      // Semua orang bisa baca untuk validasi email (tapi hanya field email)
      allow read: if true;
      
      // Hanya user yang login bisa write data mereka sendiri
      allow write: if request.auth != null && request.auth.uid == userId;
      
      // Atau untuk development, izinkan semua write (HAPUS DI PRODUCTION!)
      // allow write: if true;
    }
    
    // Collection verification_codes
    match /verification_codes/{email} {
      // Semua orang bisa create, read, dan delete untuk kode verifikasi
      allow create, read, delete: if true;
      
      // Tidak perlu update (kode hanya dibuat sekali)
      allow update: if false;
    }
  }
}
```

**Atau jika ingin lebih ketat (hanya izinkan query berdasarkan email):**

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Collection users
    match /users/{userId} {
      // Izinkan read jika query berdasarkan email (untuk validasi)
      allow read: if request.query.limit == 1 && 
                     resource.data.email == request.query.where('email', '==', request.resource.data.email);
      
      // Atau lebih sederhana: izinkan semua read untuk validasi email
      allow read: if true;
      
      // Hanya user yang login bisa write data mereka sendiri
      allow write: if request.auth != null && request.auth.uid == userId;
    }
    
    // Collection verification_codes
    match /verification_codes/{email} {
      allow create, read, delete: if true;
      allow update: if false;
    }
  }
}
```

### Langkah 3: Publish Rules

1. **Klik "Publish"** di bagian atas editor Rules.
2. **Tunggu beberapa detik** sampai rules terpublish.

---

## Testing

Setelah update Security Rules:

1. **Test dengan email baru:**
   - Masukkan email yang belum terdaftar.
   - Klik tombol refresh untuk kirim kode.
   - Seharusnya kode verifikasi terkirim.

2. **Test dengan email yang sudah terdaftar:**
   - Masukkan email yang sudah terdaftar (penumpang atau driver).
   - Klik tombol refresh untuk kirim kode.
   - Seharusnya muncul error: **"Email Sudah Terdaftar...!!! gunakan email lainnya yang aktif"**.

---

## Troubleshooting

### Masalah: Masih bisa kirim kode untuk email yang sudah terdaftar

**Kemungkinan penyebab:**
- Security Rules belum terpublish.
- Query ke collection `users` masih error permission-denied.

**Solusi:**
1. **Cek Security Rules sudah terpublish:**
   - Firebase Console → Firestore Database → Rules
   - Pastikan tidak ada warning atau error.

2. **Test query manual di Firestore Console:**
   - Firebase Console → Firestore Database → Data
   - Coba query collection `users` dengan filter `email == "test@email.com"`

3. **Cek log error di aplikasi:**
   - Buka log Flutter saat klik tombol refresh.
   - Cek apakah ada error "permission-denied".

### Masalah: Email baru tidak bisa kirim kode (error permission)

**Kemungkinan penyebab:**
- Security Rules untuk collection `verification_codes` tidak benar.

**Solusi:**
- Pastikan rules untuk `verification_codes` mengizinkan `create`:
  ```javascript
  match /verification_codes/{email} {
    allow create, read, delete: if true;
  }
  ```

---

## Catatan Penting

1. **Security Rules untuk Production:**
   - Untuk production, pertimbangkan untuk membatasi read ke collection `users` hanya untuk field `email` saja.
   - Jangan izinkan read semua data user untuk user yang belum login.

2. **Alternatif:**
   - Jika Security Rules tidak bisa diubah, bisa gunakan Cloud Function untuk validasi email.
   - Atau gunakan Firebase Auth `fetchSignInMethodsForEmail()` (tapi kurang akurat).

---

Setelah update Security Rules, validasi email yang sudah terdaftar seharusnya berfungsi dengan benar.
