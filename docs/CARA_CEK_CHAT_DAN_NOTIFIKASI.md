# Cara Cek Chat dan Notifikasi Traka

Panduan lengkap untuk mengecek apakah chat dan notifikasi berfungsi dengan benar.

---

## 1. Cek Cloud Functions Sudah Deploy

### Di Firebase Console

1. Buka **Firebase Console**: https://console.firebase.google.com
2. Pilih project **syafiul-traka**
3. Klik **Functions** di sidebar kiri
4. Lihat daftar functions yang terdeploy

**Functions yang harus ada:**
- ✅ `onChatMessageCreated` - Notifikasi saat ada pesan chat baru
- ✅ `onOrderCreated` - Notifikasi saat ada order baru
- ✅ `deleteCompletedOrderChats` - Auto-hapus chat 24 jam setelah selesai

**Jika belum ada atau error:**
- Deploy dari terminal: `firebase deploy --only functions`
- Pastikan sudah login: `firebase login`
- Pastikan di folder `functions` ada file `index.js`

### Cek Logs Functions (untuk debug error)

1. Di halaman **Functions**, klik function yang ingin dicek (misalnya `onChatMessageCreated`)
2. Klik tab **Logs**
3. Lihat log terbaru untuk melihat apakah ada error

**Contoh error yang mungkin muncul:**
- `FCM send error: ...` → Masalah dengan FCM token atau konfigurasi
- `Error: ...` → Ada bug di code function

---

## 2. Cek Index Firestore Sudah Dibuat

### Di Firebase Console

1. Buka **Firebase Console** → **Firestore Database**
2. Klik tab **Indexes**
3. Pastikan ada index berikut:

**Index untuk query orders penumpang:**
- Collection: `orders`
- Fields:
  - `passengerUid` (Ascending)
  - `status` (Ascending)  
  - `updatedAt` (Descending)
- Status: **Enabled** ✅

**Index untuk query orders driver:**
- Collection: `orders`
- Fields:
  - `driverUid` (Ascending)
  - `status` (Ascending)
  - `createdAt` (Descending)
- Status: **Enabled** ✅

**Jika belum ada atau status "Building":**
- Tunggu beberapa menit (pembuatan index bisa memakan waktu)
- Atau deploy dari file: `firebase deploy --only firestore:indexes`
- File: `firestore.indexes.json` di root project

**Jika muncul error "The query requires an index":**
- Klik link di pesan error tersebut
- Firebase akan otomatis membuat index yang diperlukan

---

## 3. Cek FCM Token Driver Sudah Tersimpan

### Di Firebase Console

1. Buka **Firestore Database** → tab **Data**
2. Buka collection **users**
3. Cari document dengan `uid` driver yang ingin dicek
4. Pastikan ada field:
   - ✅ `fcmToken` (string) - Token FCM untuk notifikasi

**Jika tidak ada `fcmToken`:**
- Driver belum login atau belum grant permission notifikasi
- Pastikan app sudah request permission notifikasi saat pertama kali buka
- Cek di code: `lib/services/fcm_service.dart` - pastikan `saveTokenToFirestore()` dipanggil

### Cek di App (Debug)

1. Buka app sebagai driver
2. Login
3. Buka halaman profil atau chat
4. Cek di log console apakah ada error terkait FCM token

---

## 4. Cek Notifikasi Channel Android

### Di Code App

File: `android/app/src/main/AndroidManifest.xml` atau di code Flutter

Pastikan ada channel notification dengan ID: `traka_chat`

**Cek di code:**
- File: `lib/services/fcm_service.dart`
- Pastikan ada kode untuk membuat notification channel

**Contoh:**
```dart
const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'traka_chat',
  'Traka Chat',
  importance: Importance.high,
);
```

---

## 5. Cek Data Chat Tersimpan di Firestore

### Di Firebase Console

1. Buka **Firestore Database** → tab **Data**
2. Buka collection **orders**
3. Pilih order yang ingin dicek (misalnya order yang baru dibuat)
4. Buka subcollection **messages**
5. Pastikan ada document pesan yang baru dikirim

**Field yang harus ada di document message:**
- ✅ `senderUid` - UID pengirim
- ✅ `text` - Isi pesan
- ✅ `createdAt` - Timestamp
- ✅ `status` - Status pesan (sent/delivered/read)

**Cek order document:**
- Pastikan ada field `lastMessageAt` (terupdate setelah kirim pesan)
- Pastikan ada field `lastMessageSenderUid`
- Pastikan ada field `lastMessageText`

**Jika tidak terupdate:**
- Cloud Function `onChatMessageCreated` mungkin belum deploy atau error
- Cek logs di Functions (lihat bagian 1)

---

## 6. Cek Query Orders Berfungsi

### Test di App

1. **Sebagai Penumpang:**
   - Buka halaman **Chat**
   - Pastikan tidak stuck loading
   - Jika stuck, cek apakah index sudah dibuat (lihat bagian 2)

2. **Sebagai Driver:**
   - Buka tab **Chat**
   - Pastikan tidak stuck loading
   - Jika stuck, cek apakah index sudah dibuat (lihat bagian 2)

### Test di Firebase Console

1. Buka **Firestore Database** → tab **Data**
2. Klik collection **orders**
3. Di bagian atas, klik ikon **Query** (atau gunakan filter)
4. Test query:
   - Filter: `passengerUid` = `[uid penumpang]`
   - Filter: `status` in `[pending_agreement, agreed, picked_up, completed]`
   - Sort: `updatedAt` Descending
5. Jika muncul error "requires an index", buat index tersebut

---

## 7. Troubleshooting

### Masalah: Notifikasi tidak muncul di HP driver

**Cek:**
1. ✅ Cloud Function `onChatMessageCreated` sudah deploy (bagian 1)
2. ✅ FCM token driver sudah tersimpan di Firestore (bagian 3)
3. ✅ Notification channel `traka_chat` sudah dibuat (bagian 4)
4. ✅ Driver sudah grant permission notifikasi di HP
5. ✅ HP driver tidak dalam mode "Do Not Disturb"
6. ✅ App tidak di-force stop

**Debug:**
- Cek logs Functions untuk melihat apakah notifikasi dikirim
- Cek apakah ada error di log: `FCM send error: ...`

### Masalah: Halaman chat stuck loading

**Cek:**
1. ✅ Index Firestore sudah dibuat (bagian 2)
2. ✅ Query tidak error (cek di Firebase Console → Data → Query)
3. ✅ Koneksi internet stabil
4. ✅ Firestore Rules tidak memblokir query

**Debug:**
- Cek log console di app untuk melihat error
- Cek apakah query memerlukan index baru (akan muncul link di error)

### Masalah: Pesan tidak muncul setelah kirim

**Cek:**
1. ✅ Pesan tersimpan di Firestore (bagian 5)
2. ✅ Stream messages berfungsi (cek di code: `ChatService.streamMessages`)
3. ✅ Rules Firestore mengizinkan read messages (cek `firestore.rules`)

**Debug:**
- Cek apakah pesan tersimpan di `orders/{orderId}/messages`
- Cek apakah ada error di console saat kirim pesan

---

## Ringkasan Lokasi Cek

| Yang Dicek | Lokasi |
|------------|--------|
| **Cloud Functions** | Firebase Console → Functions |
| **Index Firestore** | Firebase Console → Firestore → Indexes |
| **FCM Token** | Firebase Console → Firestore → Data → users/{uid} |
| **Data Chat** | Firebase Console → Firestore → Data → orders/{orderId}/messages |
| **Logs Functions** | Firebase Console → Functions → [nama function] → Logs |
| **Query Test** | Firebase Console → Firestore → Data → [collection] → Query |

---

## Perintah Deploy

Jika perlu deploy ulang:

```bash
# Deploy Functions
firebase deploy --only functions

# Deploy Indexes
firebase deploy --only firestore:indexes

# Deploy Rules
firebase deploy --only firestore:rules

# Deploy semua Firestore (rules + indexes)
firebase deploy --only firestore
```

---

Dengan mengikuti panduan ini, semua masalah terkait chat dan notifikasi seharusnya bisa diidentifikasi dan diperbaiki.
