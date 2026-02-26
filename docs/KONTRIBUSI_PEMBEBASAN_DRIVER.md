# Pembebasan Kontribusi Driver Penguji

Panduan lengkap untuk membebaskan driver penguji dari pembayaran kontribusi selama 1 tahun (atau lebih) tanpa mengubah aplikasi.

---

## Apa itu Kontribusi Driver?

- Setelah driver melayani penumpang sebanyak **1× kapasitas mobil** (misalnya 7 orang untuk mobil 7 seat), driver wajib bayar kontribusi via Google Play.
- Untuk **pengujian**, Anda ingin driver penguji **tidak bayar** selama 1 tahun.

---

## Cara Kerja Pembebasan

### Logika singkat

- Aplikasi mengecek: **apakah total penumpang dilayani ≥ (contributionPaidUpToCount + kapasitas mobil)?**
- Jika ya → driver wajib bayar.
- Jika **contributionPaidUpToCount** kita set ke **999999**, maka driver perlu melayani 999999+ penumpang baru wajib bayar → praktis tidak akan tercapai dalam 1 tahun.

### Peran Cloud Function

1. **Cloud Function** membaca daftar UID driver penguji dari Firestore.
2. Untuk setiap UID, function meng-update field `contributionPaidUpToCount` di dokumen `users/{uid}` menjadi **999999**.
3. Function berjalan **otomatis setiap hari jam 00:00 WIB**.
4. Aplikasi tidak diubah; ia tetap membaca data dari Firestore seperti biasa.

---

## Langkah 1: Deploy Cloud Function

### 1.1 Buka Terminal / Command Prompt

- Tekan `Win + R`, ketik `cmd`, Enter.
- Atau buka PowerShell.

### 1.2 Masuk ke folder project

```bash
cd D:\Traka\traka
```

### 1.3 Pastikan sudah login Firebase

```bash
firebase login
```

- Jika belum login, browser akan terbuka untuk login akun Google.
- Pastikan akun yang dipakai punya akses ke project Firebase Traka.

### 1.4 Deploy function

```bash
firebase deploy --only functions
```

- Tunggu sampai proses selesai.
- Jika berhasil, akan muncul pesan seperti: `✔  Deploy complete!`

### 1.5 Cek di Firebase Console

1. Buka [Firebase Console](https://console.firebase.google.com)
2. Pilih project **Traka**
3. Menu kiri → **Functions**
4. Pastikan ada function:
   - `updateContributionExemptDrivers` (scheduled)
   - `runContributionExemptUpdate` (callable)

---

## Langkah 2: Dapatkan UID Driver Penguji

**UID** = ID unik setiap user di Firebase (panjang, contoh: `xK9mP2qR7sT4uVwXyZ1234567890`).

### Cara 1: Dari Authentication

1. Firebase Console → **Build** → **Authentication** → **Users**
2. Cari user (driver penguji) berdasarkan email atau nomor HP
3. Klik baris user tersebut
4. Di panel kanan, lihat **User UID**
5. Klik ikon copy di samping UID, lalu paste ke Notepad

### Cara 2: Dari Firestore

1. Firebase Console → **Build** → **Firestore Database**
2. Buka collection **users**
3. Setiap **Document ID** = UID user
4. Cari dokumen driver (bisa lihat field `displayName` atau `email`)
5. Copy **Document ID** (itu UID-nya)

### Contoh UID (format)

```
abc123XYZ456def789
```

- Panjang sekitar 28 karakter
- Huruf dan angka, tanpa spasi

---

## Langkah 3: Buat Dokumen di Firestore

### 3.1 Buka Firestore

1. Firebase Console → **Build** → **Firestore Database**
2. Pastikan Anda di tab **Data**

### 3.2 Cek collection `app_config`

- Di panel kiri, lihat daftar collection.
- Jika **app_config** sudah ada, klik untuk expand.
- Jika belum ada, kita akan buat dokumen yang otomatis membuat collection.

### 3.3 Tambah dokumen baru

1. Klik collection **app_config** (atau root jika app_config belum ada)
2. Klik tombol **+ Add document** (atau **Start collection** jika kosong)

### 3.4 Isi Document ID

- Di field **Document ID**, ketik persis:  
  `contribution_exempt_drivers`
- Jangan pakai spasi atau huruf besar/kecil sembarangan.

### 3.5 Tambah field `driverUids`

1. Di bagian **Add field**:
   - **Field**: `driverUids`
   - **Type**: pilih **array**
2. Klik **Add item** di dalam array
3. **Type** item: pilih **string**
4. **Value**: paste UID driver pertama (contoh: `abc123XYZ456def789`)
5. Untuk driver kedua, ketiga, dst: klik **Add item** lagi, pilih **string**, isi UID

### 3.6 Simpan

- Klik **Save**

### Contoh struktur dokumen

| Field       | Type  | Value                                                                 |
|------------|-------|-----------------------------------------------------------------------|
| driverUids | array | [ "uid_driver_1", "uid_driver_2", "uid_driver_3" ]                     |

- Ganti `uid_driver_1`, `uid_driver_2`, dll dengan UID asli dari Langkah 2.

---

## Langkah 4: Jalankan Update (Opsional – Langsung)

Secara default, function berjalan setiap hari jam 00:00 WIB. Jika ingin **langsung** meng-update tanpa menunggu:

### 4.1 Dari Firebase Console

1. Firebase Console → **Functions**
2. Klik function **runContributionExemptUpdate**
3. Tab **Logs** atau **Testing** (jika ada opsi Test)
4. Beberapa project punya tombol **Run** / **Test** untuk callable function

### 4.2 Dari Kode (jika punya akses)

Jika ada script atau aplikasi admin yang bisa memanggil Cloud Function:

```javascript
// Contoh (Node.js / Firebase Admin)
const result = await functions.httpsCallable('runContributionExemptUpdate')({});
```

### 4.3 Tanpa panggil manual

- Tidak masalah jika tidak dipanggil manual.
- Besok jam 00:00 WIB, function scheduled akan jalan otomatis dan meng-update semua driver di daftar.

---

## Menambah Driver Baru ke Daftar

1. Firestore → **app_config** → dokumen **contribution_exempt_drivers**
2. Klik **Edit** (ikon pensil)
3. Di field **driverUids**, klik **Add item**
4. Type: **string**, Value: UID driver baru
5. **Save**

- Perubahan berlaku maksimal 24 jam (saat function scheduled jalan), atau segera jika Anda panggil `runContributionExemptUpdate`.

---

## Menghapus Driver dari Daftar

1. Firestore → **app_config** → **contribution_exempt_drivers**
2. Klik **Edit**
3. Di array **driverUids**, hapus item UID yang ingin dicabut pembebasannya
4. **Save**

- Driver tersebut akan kembali wajib bayar sesuai aturan normal (setelah penumpang dilayani mencapai threshold).

---

## Memastikan Pembebasan Berjalan

### Cek di Firestore

1. Buka **users** → pilih dokumen driver penguji (Document ID = UID)
2. Lihat field **contributionPaidUpToCount**
3. Jika nilainya **999999** → pembebasan aktif

### Cek di Aplikasi

- Login sebagai driver penguji
- Buka halaman kontribusi
- Jika pembebasan aktif, driver **tidak** akan diminta bayar kontribusi

---

## Troubleshooting

### Function tidak jalan / tidak update

- Cek **Functions** → **Logs** di Firebase Console untuk error
- Pastikan dokumen `app_config/contribution_exempt_drivers` ada dan field `driverUids` berisi array (bukan null/kosong)
- Pastikan UID yang dimasukkan benar (sama persis dengan Document ID di `users`)

### UID salah / typo

- Driver tidak akan ter-update
- Cek lagi UID di Authentication atau Firestore `users`
- Edit dokumen `contribution_exempt_drivers`, perbaiki UID, lalu Save

### Collection `app_config` belum ada

- Saat Add document, isi Document ID: `contribution_exempt_drivers`
- Collection `app_config` akan otomatis terbentuk

---

## Ringkasan Cepat

| Langkah | Yang Dilakukan |
|---------|----------------|
| 1 | Deploy Cloud Function (`firebase deploy --only functions`) |
| 2 | Ambil UID driver dari Authentication atau Firestore `users` |
| 3 | Buat dokumen `app_config/contribution_exempt_drivers` dengan field `driverUids` (array UID) |
| 4 | (Opsional) Panggil `runContributionExemptUpdate` untuk update langsung, atau tunggu jam 00:00 WIB |

---

## Catatan Penting

- **Aplikasi tidak perlu di-update** – semua logic di Cloud Function dan Firestore.
- Setelah 1 tahun, cabut pembebasan dengan **menghapus UID** dari array `driverUids`.
- Nilai 999999 setara dengan ratusan ribu penumpang – cukup untuk 1 tahun pengujian.
