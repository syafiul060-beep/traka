# Cara Deploy Firebase Storage Rules

## Masalah
Pesan suara gagal terkirim karena Firebase Storage rules belum dikonfigurasi, sehingga upload audio ke Storage diblokir.

## Solusi: Deploy Storage Rules

### Langkah 1: File Sudah Dibuat
File `storage.rules` sudah dibuat di root project dengan rules yang mengizinkan:
- Upload/download audio ke `chat_audio/{orderId}/{fileName}` untuk user yang login
- Upload/download gambar ke `chat_images/{orderId}/{fileName}` untuk user yang login
- Upload/download video ke `chat_videos/{orderId}/{fileName}` untuk user yang login
- Upload foto profil ke `users/{userId}/` hanya untuk pemilik

### Langkah 2: Deploy Storage Rules

**Via Firebase CLI:**
```bash
firebase deploy --only storage
```

**Via Firebase Console:**
1. Buka Firebase Console: https://console.firebase.google.com/project/syafiul-traka/storage
2. Klik tab **"Rules"**
3. Copy-paste isi file `storage.rules`
4. Klik **"Publish"**

### Langkah 3: Verifikasi

1. Buka Firebase Console → **Storage** → **Rules**
2. Pastikan rules sudah ter-update dengan rules baru
3. Cek apakah ada error di rules (akan muncul warning jika ada)

## Rules yang Sudah Dikonfigurasi

**File:** `storage.rules` (di root project)

```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    // Chat audio: hanya user yang login boleh upload/download
    match /chat_audio/{orderId}/{fileName} {
      allow read, write: if request.auth != null;
    }
    
    // Chat images: hanya user yang login boleh upload/download
    match /chat_images/{orderId}/{fileName} {
      allow read, write: if request.auth != null;
    }
    
    // Chat videos: hanya user yang login boleh upload/download
    match /chat_videos/{orderId}/{fileName} {
      allow read, write: if request.auth != null;
    }
    
    // User photos: hanya pemilik yang boleh upload, semua user login boleh baca
    match /users/{userId}/{allPaths=**} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

**Catatan Penting:**
- Ini adalah **Firebase Storage rules** (untuk file/media)
- **Bukan Firestore rules** (untuk database)
- Firestore rules ada di file `firestore.rules` (sudah terkonfigurasi dengan benar)

## Setelah Deploy

1. **Test kirim pesan suara** dari aplikasi
2. **Cek apakah upload berhasil** di Firebase Console → Storage → Files
3. **Cek apakah pesan tersimpan** di Firestore → `orders/{orderId}/messages`
4. **Cek apakah notifikasi terkirim** ke penerima

## Troubleshooting

### Error: "Permission denied"
**Solusi:**
- Pastikan user sudah login (`request.auth != null`)
- Pastikan storage rules sudah ter-deploy
- Cek apakah path file sesuai dengan rules (`chat_audio/{orderId}/{fileName}`)

### Error: "Storage rules not found"
**Solusi:**
- Pastikan file `storage.rules` ada di root project
- Pastikan `firebase.json` sudah dikonfigurasi dengan `"storage": { "rules": "storage.rules" }`
- Deploy ulang: `firebase deploy --only storage`

### Upload Berhasil Tapi Pesan Tidak Tersimpan
**Solusi:**
- Cek log aplikasi untuk error saat save ke Firestore
- Cek Firestore rules untuk collection `orders/{orderId}/messages`
- Pastikan `orderId` valid dan order masih ada

## Catatan Penting

- Storage rules berbeda dengan Firestore rules
- Storage rules mengatur akses ke file di Firebase Storage
- Firestore rules mengatur akses ke data di Firestore Database
- Keduanya harus dikonfigurasi dengan benar agar aplikasi berfungsi
