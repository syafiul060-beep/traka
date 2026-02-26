# Cara Cek Log Firebase Functions untuk Debug

## Masalah
Function `onChatMessageCreated` sudah ter-deploy dan sudah dipanggil (1 request), tapi pesan suara masih gagal atau notifikasi tidak terkirim.

## Langkah 1: Cek Log Function di Firebase Console

### Via Firebase Console:
1. Buka Firebase Console: https://console.firebase.google.com
2. Pilih project `syafiul-traka`
3. Buka **Functions** (di sidebar kiri)
4. Klik function **`onChatMessageCreated`**
5. Klik tab **"Logs"** atau **"View logs in Google Cloud Console"**
6. Cari log yang terkait dengan request terakhir

### Via Google Cloud Console (Lebih Detail):
1. Di Firebase Console → Functions → `onChatMessageCreated`
2. Klik **"View logs in Google Cloud Console"** (banner biru di atas)
3. Atau langsung buka: https://console.cloud.google.com/logs/query
4. Filter log:
   - **Resource**: Cloud Function
   - **Function name**: `onChatMessageCreated`
   - **Time range**: Last 1 hour atau Last 24 hours

## Langkah 2: Cek Log via CLI

```bash
firebase functions:log --only onChatMessageCreated
```

Atau untuk melihat log real-time:
```bash
firebase functions:log --only onChatMessageCreated --follow
```

## Yang Perlu Dicek di Log

### 1. Apakah Function Terpanggil?
Cari log seperti:
```
Function execution started
Function execution took X ms
```

### 2. Apakah Ada Error?
Cari log dengan kata kunci:
- `error`
- `Error`
- `FCM send error`
- `Exception`

### 3. Apakah FCM Token Ada?
Cari log yang menunjukkan:
- `fcmToken` ada atau tidak
- `FCM token tidak ditemukan`

### 4. Apakah Notifikasi Terkirim?
Cari log:
- `FCM send error` → berarti ada masalah saat kirim
- `Successfully sent message` → berarti berhasil

## Langkah 3: Cek FCM Token di Firestore

1. Buka Firebase Console → **Firestore Database**
2. Buka collection **`users`**
3. Cari document dengan UID driver atau penumpang yang seharusnya menerima notifikasi
4. Cek apakah field **`fcmToken`** ada dan berisi token yang valid

**Format FCM Token biasanya seperti:**
```
dXXXXXXXXX:APA91bH...
```

Jika `fcmToken` tidak ada atau kosong:
- User belum login atau belum set FCM token
- Perlu set FCM token saat login/register

## Langkah 4: Test Function Manual

### Via Firebase Console:
1. Buka Firebase Console → **Firestore Database**
2. Buka collection **`orders`** → pilih order yang aktif
3. Buka subcollection **`messages`**
4. Tambah document baru dengan data:
   ```json
   {
     "senderUid": "UID_PENUMPANG",
     "text": "",
     "type": "audio",
     "audioUrl": "https://test.com/audio.m4a",
     "audioDuration": 5,
     "createdAt": [timestamp],
     "status": "sent"
   }
   ```
5. Function `onChatMessageCreated` akan terpanggil otomatis
6. Cek log untuk melihat apakah ada error

## Troubleshooting Berdasarkan Error

### Error: "fcmToken tidak ditemukan"
**Solusi:**
- Pastikan user sudah login
- Pastikan FCM token sudah disimpan di `users/{uid}/fcmToken`
- Cek apakah ada kode untuk set FCM token saat login

### Error: "FCM send error"
**Solusi:**
- Cek apakah FCM token masih valid
- Cek apakah project Firebase sudah enable Cloud Messaging
- Cek apakah ada masalah dengan Firebase Cloud Messaging API

### Error: "Order tidak ditemukan"
**Solusi:**
- Pastikan `orderId` yang digunakan benar
- Pastikan order masih ada di Firestore

### Function Tidak Terpanggil
**Solusi:**
- Pastikan pesan benar-benar tersimpan ke Firestore
- Cek apakah trigger `document.create` sudah benar
- Cek apakah ada error di Firestore rules yang menghalangi write

## Langkah 5: Verifikasi Kode Function

Pastikan function `onChatMessageCreated` di `functions/index.js` sudah menggunakan kode yang benar (yang sudah kita perbaiki untuk support audio).

Cek apakah ada baris:
```javascript
if (!text || messageType !== "text") {
  // Handle audio, image, video
  if (messageType === "audio") {
    notificationText = `🎤 Pesan suara${durationText}`;
    // ...
  }
}
```

Jika tidak ada, perlu deploy ulang dengan kode yang sudah diperbaiki.

## Langkah 6: Test End-to-End

1. **Pastikan user sudah login** di aplikasi
2. **Pastikan FCM token sudah tersimpan** (cek di Firestore)
3. **Kirim pesan suara** dari aplikasi
4. **Cek log function** untuk melihat prosesnya
5. **Cek apakah notifikasi terkirim** ke HP penerima

## Catatan Penting

- Function sudah ter-deploy dan sudah dipanggil (1 request) → berarti function bekerja
- Masalahnya mungkin di:
  - FCM token tidak ada atau tidak valid
  - Error saat kirim notifikasi
  - Pesan tidak tersimpan ke Firestore dengan benar
  - Function menggunakan kode lama (belum support audio)

Cek log untuk mengetahui masalah spesifiknya!
