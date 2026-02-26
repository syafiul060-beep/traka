# Debug: Pesan Suara Gagal Terkirim

## Status Saat Ini
✅ Function `onChatMessageCreated` sudah ter-deploy  
✅ Function sudah dipanggil 1 kali (berarti trigger bekerja)  
❓ Masalah: Pesan suara masih gagal atau notifikasi tidak terkirim

## Langkah Debugging

### 1. Cek Log Function (PENTING!)

**Via Firebase Console:**
1. Buka: https://console.firebase.google.com/project/syafiul-traka/functions
2. Klik function **`onChatMessageCreated`**
3. Klik **"View logs in Google Cloud Console"** (banner biru)
4. Atau langsung: https://console.cloud.google.com/logs/query?project=syafiul-traka
5. Filter: Function name = `onChatMessageCreated`, Time = Last 1 hour
6. Cari log dengan kata kunci: `error`, `FCM`, `fcmToken`

**Via CLI:**
```bash
firebase functions:log --only onChatMessageCreated
```

### 2. Cek Apakah Pesan Tersimpan ke Firestore

1. Buka Firebase Console → **Firestore Database**
2. Buka collection **`orders`** → pilih order yang digunakan untuk test
3. Buka subcollection **`messages`**
4. **Cek apakah pesan audio sudah tersimpan:**
   - Harus ada document dengan `type: "audio"`
   - Harus ada field `audioUrl` (URL dari Firebase Storage)
   - Harus ada field `audioDuration` (durasi dalam detik)

**Jika pesan TIDAK ada di Firestore:**
- Masalahnya di client side (upload ke Storage atau save ke Firestore gagal)
- Cek log aplikasi untuk error

**Jika pesan ADA di Firestore:**
- Function seharusnya terpanggil
- Cek log function untuk melihat apakah ada error

### 3. Cek FCM Token

1. Buka Firebase Console → **Firestore Database**
2. Buka collection **`users`**
3. Cari document dengan UID **driver** atau **penumpang** yang seharusnya menerima notifikasi
4. **Cek field `fcmToken`:**
   - Harus ada dan tidak kosong
   - Format biasanya: `dXXXXXXXXX:APA91bH...`

**Jika `fcmToken` TIDAK ada atau kosong:**
- User belum set FCM token saat login
- Perlu tambahkan kode untuk set FCM token saat login/register

**Jika `fcmToken` ADA:**
- Token mungkin sudah expired atau tidak valid
- Function akan return `null` di baris: `if (!fcmToken) return null;`
- Cek log function untuk konfirmasi

### 4. Cek Error di Log Function

Berdasarkan kode function, kemungkinan error:

#### Error: "fcmToken tidak ditemukan"
**Log akan menunjukkan:**
```
Function execution completed but returned null (fcmToken tidak ada)
```

**Solusi:**
- Set FCM token saat user login
- Pastikan token tersimpan di `users/{uid}/fcmToken`

#### Error: "FCM send error"
**Log akan menunjukkan:**
```
FCM send error: [error detail]
```

**Solusi:**
- Cek apakah FCM token masih valid
- Cek apakah Firebase Cloud Messaging API sudah enable
- Cek apakah ada masalah dengan payload notifikasi

#### Error: "Order tidak ditemukan"
**Log akan menunjukkan:**
```
Order tidak ditemukan untuk orderId: [orderId]
```

**Solusi:**
- Pastikan `orderId` yang digunakan benar
- Pastikan order masih ada di Firestore

### 5. Test Manual Function

Untuk test apakah function bekerja dengan benar:

1. Buka Firebase Console → **Firestore Database**
2. Buka collection **`orders`** → pilih order yang aktif
3. Buka subcollection **`messages`**
4. Klik **"Add document"**
5. Isi dengan data berikut:
   ```json
   {
     "senderUid": "UID_PENUMPANG_ATAU_DRIVER",
     "text": "",
     "type": "audio",
     "audioUrl": "https://test.com/test.m4a",
     "audioDuration": 5,
     "createdAt": [klik "timestamp" untuk set waktu sekarang],
     "status": "sent"
   }
   ```
6. Klik **"Save"**
7. Function `onChatMessageCreated` akan terpanggil otomatis
8. Cek log function untuk melihat apakah ada error
9. Cek apakah notifikasi terkirim ke HP

### 6. Cek Apakah Pesan Suara Benar-Benar Terkirim

**Di aplikasi:**
1. Buka chat room
2. Kirim pesan suara
3. **Cek apakah pesan muncul di chat:**
   - Jika muncul → pesan tersimpan dengan benar
   - Jika tidak muncul → masalah di client side (upload/save gagal)

**Di Firestore:**
1. Buka `orders/{orderId}/messages`
2. Cek apakah ada document baru dengan `type: "audio"`
3. Jika ada → function seharusnya terpanggil
4. Jika tidak ada → masalah di client side

### 7. Cek Apakah Notifikasi Terkirim

**Di HP penerima:**
1. Pastikan aplikasi tidak sedang dibuka (di background)
2. Pastikan notifikasi tidak di-disable
3. Cek apakah notifikasi muncul

**Di log function:**
1. Cek apakah ada log: `Successfully sent message` atau `FCM send error`
2. Jika ada error → lihat detail error

## Kemungkinan Masalah dan Solusi

### Masalah 1: Pesan Tidak Tersimpan ke Firestore
**Gejala:** Pesan suara tidak muncul di chat, tidak ada di Firestore

**Penyebab:**
- Upload ke Firebase Storage gagal
- Save ke Firestore gagal
- Permission error

**Solusi:**
- Cek log aplikasi untuk error
- Cek Firebase Storage rules
- Cek Firestore rules
- Pastikan koneksi internet stabil

### Masalah 2: Function Tidak Terpanggil
**Gejala:** Pesan ada di Firestore tapi function tidak terpanggil

**Penyebab:**
- Trigger tidak bekerja
- Function error sebelum log

**Solusi:**
- Cek apakah function masih aktif di Firebase Console
- Cek log function untuk error
- Deploy ulang function jika perlu

### Masalah 3: FCM Token Tidak Ada
**Gejala:** Function terpanggil tapi tidak ada notifikasi, log menunjukkan `fcmToken tidak ditemukan`

**Penyebab:**
- User belum set FCM token saat login
- Token tidak tersimpan dengan benar

**Solusi:**
- Tambahkan kode untuk set FCM token saat login
- Pastikan token tersimpan di `users/{uid}/fcmToken`

### Masalah 4: FCM Send Error
**Gejala:** Function terpanggil, fcmToken ada, tapi ada error saat kirim

**Penyebab:**
- FCM token tidak valid atau expired
- Firebase Cloud Messaging API tidak enable
- Payload notifikasi tidak valid

**Solusi:**
- Cek detail error di log
- Pastikan FCM token masih valid
- Pastikan Firebase Cloud Messaging API sudah enable
- Cek format payload notifikasi

## Langkah Selanjutnya

1. **Cek log function** untuk melihat error spesifik
2. **Cek apakah pesan tersimpan** ke Firestore
3. **Cek FCM token** di Firestore
4. **Test manual** dengan menambah document langsung ke Firestore
5. **Beri tahu hasil** dari langkah-langkah di atas

Dengan informasi dari langkah-langkah di atas, kita bisa mengetahui masalah spesifiknya dan memperbaikinya.
