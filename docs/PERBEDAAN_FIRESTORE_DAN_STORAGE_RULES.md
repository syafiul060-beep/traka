# Perbedaan Firestore Rules dan Storage Rules

## Perbedaan Utama

### Firestore Rules
- **File:** `firestore.rules`
- **Untuk:** Database (data struktur seperti JSON)
- **Service:** `service cloud.firestore`
- **Deploy:** `firebase deploy --only firestore:rules`
- **Mengatur:** Siapa boleh baca/tulis data di collections Firestore

### Storage Rules
- **File:** `storage.rules`
- **Untuk:** File/media (audio, gambar, video)
- **Service:** `service firebase.storage`
- **Deploy:** `firebase deploy --only storage`
- **Mengatur:** Siapa boleh upload/download file di Firebase Storage

## Contoh

### Firestore Rules (`firestore.rules`)
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      allow read: if true;
      allow write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

### Storage Rules (`storage.rules`)
```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /chat_audio/{orderId}/{fileName} {
      allow read, write: if request.auth != null;
    }
  }
}
```

## Untuk Aplikasi Traka

### Firestore Rules
- Sudah dikonfigurasi di `firestore.rules`
- Mengatur akses ke collections: `users`, `orders`, `orders/{orderId}/messages`, dll.
- Sudah ter-deploy dan bekerja dengan baik

### Storage Rules
- Baru dibuat di `storage.rules`
- Mengatur akses ke file: `chat_audio/`, `chat_images/`, `chat_videos/`, `users/`
- **Perlu di-deploy** agar upload audio/gambar/video bisa bekerja

## Deploy Keduanya

### Deploy Firestore Rules
```bash
firebase deploy --only firestore:rules
```

### Deploy Storage Rules
```bash
firebase deploy --only storage
```

### Deploy Keduanya Sekaligus
```bash
firebase deploy --only firestore:rules,storage
```

## Troubleshooting

### Error: "Permission denied" saat upload audio
**Penyebab:** Storage rules belum ter-deploy atau tidak mengizinkan upload
**Solusi:** Deploy storage rules dengan `firebase deploy --only storage`

### Error: "Permission denied" saat baca data Firestore
**Penyebab:** Firestore rules tidak mengizinkan akses
**Solusi:** Cek dan deploy firestore rules dengan `firebase deploy --only firestore:rules`

### File ter-upload tapi tidak bisa diakses
**Penyebab:** Storage rules tidak mengizinkan read
**Solusi:** Pastikan storage rules mengizinkan `allow read` untuk path yang sesuai

## Catatan Penting

- **Keduanya berbeda** dan harus dikonfigurasi terpisah
- **Keduanya penting** untuk aplikasi yang menggunakan Firestore dan Storage
- **Deploy terpisah** atau sekaligus sesuai kebutuhan
- **Cek rules di Firebase Console** untuk memastikan sudah ter-update
