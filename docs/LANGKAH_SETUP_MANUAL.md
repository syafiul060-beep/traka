# Langkah Setup Manual Cloud Functions (Tanpa `firebase init`)

File-file sudah dibuat otomatis. Ikuti langkah-langkah berikut untuk menyelesaikan setup.

---

## ✅ Yang Sudah Dibuat Otomatis

- ✅ Folder `functions/` sudah dibuat
- ✅ File `functions/package.json` sudah dibuat
- ✅ File `functions/index.js` sudah dibuat (template Cloud Function)
- ✅ File `firebase.json` sudah diupdate dengan konfigurasi Functions

---

## Langkah 1: Install Dependencies

1. **Buka Command Prompt atau PowerShell.**
2. **Masuk ke folder `functions`:**
   ```bash
   cd "C:\Users\syafi\OneDrive\Dokumen\Traka\traka\functions"
   ```

3. **Install dependencies:**
   ```bash
   npm install
   ```
4. **Tunggu sampai selesai** (biasanya 30-60 detik).

---

## Langkah 2: Setup Gmail App Password

Cloud Function perlu App Password Gmail untuk mengirim email.

### 2.1: Aktifkan 2-Step Verification (jika belum)

1. **Buka:** https://myaccount.google.com/security
2. **Scroll ke "2-Step Verification"** → aktifkan jika belum.

### 2.2: Buat App Password

1. **Buka:** https://myaccount.google.com/apppasswords
2. **Pilih app:** "Mail"
3. **Pilih device:** "Other (Custom name)" → ketik **"Firebase Cloud Functions"** → klik **"Generate"**
4. **Copy App Password** yang muncul (16 karakter, contoh: `abcd efgh ijkl mnop`)
   - **PENTING:** Hapus semua spasi saat memakai di kode (jadi: `abcdefghijklmnop`)

---

## Langkah 3: Update Email & App Password di Kode

1. **Buka file `functions/index.js`** dengan text editor (VS Code, Notepad++, dll.).

2. **Cari baris 10 dan 11:**
   ```javascript
   const gmailEmail = 'mcctv921@gmail.com'; // Ganti dengan email Gmail Anda
   const gmailAppPassword = 'your-app-password-here'; // Ganti dengan App Password Gmail Anda
   ```

3. **Update dengan data Anda:**
   - Ganti `mcctv921@gmail.com` dengan email Gmail Anda (jika berbeda).
   - Ganti `your-app-password-here` dengan App Password yang baru dibuat (16 karakter, **tanpa spasi**).

4. **Simpan file** (`Ctrl + S`).

---

## Langkah 4: Set Project Firebase

Pastikan Firebase CLI menggunakan project yang benar.

1. **Kembali ke root folder project:**
   ```bash
   cd ..
   ```

2. **Set project Firebase:**
   ```bash
   firebase use syafiul-traka
   ```
   (Ganti `syafiul-traka` dengan nama project Firebase Anda jika berbeda)

3. **Verifikasi:**
   ```bash
   firebase use
   ```
   Seharusnya muncul: `syafiul-traka (alias: default)` atau serupa.

---

## Langkah 5: Deploy Cloud Function

1. **Deploy function ke Firebase:**
   ```bash
   firebase deploy --only functions
   ```

2. **Tunggu sampai selesai** (biasanya 2-5 menit).
   - Akan muncul progress bar dan log.
   - Jika berhasil, akan muncul pesan seperti:
     ```
     ✔  functions[sendVerificationCode(us-central1)] Successful create operation.
     ```

---

## Langkah 6: Verifikasi Function Terdeploy

1. **Buka Firebase Console:** https://console.firebase.google.com/
2. **Pilih project:** `syafiul-traka`
3. **Klik "Functions"** di menu kiri.
4. **Seharusnya muncul function `sendVerificationCode`** dengan status **"Active"**.

---

## Langkah 7: Test di Aplikasi Flutter

1. **Buka aplikasi Flutter** di HP atau emulator.
2. **Masuk ke halaman registrasi.**
3. **Isi email** (misalnya `test@email.com`).
4. **Klik tombol refresh** (ikon circular arrow) di samping kolom "Masukkan kode verifikasi".
5. **Tunggu 10-30 detik** (Cloud Function perlu waktu untuk trigger dan kirim email).
6. **Cek email** yang Anda isi:
   - Cek **inbox**.
   - Cek **folder Spam/Junk** (terutama pertama kali).
   - Email seharusnya masuk dengan subjek **"Kode Verifikasi Traka Travel Kalimantan"** dan berisi kode 6 digit.

---

## Cek Log Cloud Function

Jika email tidak masuk, cek log untuk melihat error:

1. **Firebase Console** → **Functions** → klik function **`sendVerificationCode`**.
2. **Buka tab "Logs"** atau **"Activity"**.
3. **Setelah klik "Kirim kode" di app**, tunggu beberapa detik lalu refresh log.
4. **Seharusnya muncul log:**
   - `Email berhasil dikirim: [message-id]`
   - `Email dikirim ke: [email]`
   - `Kode verifikasi: [kode]`
5. **Jika ada error**, log akan menampilkan error message (misalnya "Authentication failed" jika App Password salah).

---

## Troubleshooting

### Error: "Authentication failed" saat deploy atau kirim email

**Penyebab:** App Password salah atau format salah.

**Solusi:**
1. Cek App Password di `functions/index.js`:
   - Pastikan tidak ada spasi.
   - Pastikan 16 karakter (tanpa spasi).
2. Buat App Password baru di https://myaccount.google.com/apppasswords
3. Update `gmailAppPassword` di `functions/index.js`.
4. Deploy ulang: `firebase deploy --only functions`

### Error: "Project not found" saat deploy

**Penyebab:** Project Firebase tidak sesuai.

**Solusi:**
1. Cek project aktif: `firebase use`
2. Set project yang benar: `firebase use syafiul-traka`
3. Deploy lagi: `firebase deploy --only functions`

### Email tidak masuk

**Penyebab:** Cloud Function tidak trigger atau email masuk ke Spam.

**Solusi:**
1. Cek apakah document muncul di Firestore: `verification_codes/{email}`
2. Cek log Cloud Function di Firebase Console
3. Cek folder Spam/Junk di email
4. Pastikan email yang diisi benar dan bisa menerima email

---

## Checklist

| No | Langkah | Sudah? |
|----|---------|--------|
| 1 | **Install dependencies** (`npm install` di folder `functions`) | ☐ |
| 2 | **Setup Gmail App Password** | ☐ |
| 3 | **Update email & App Password di `functions/index.js`** | ☐ |
| 4 | **Set project Firebase** (`firebase use syafiul-traka`) | ☐ |
| 5 | **Deploy function** (`firebase deploy --only functions`) | ☐ |
| 6 | **Verifikasi function terdeploy** (Firebase Console → Functions) | ☐ |
| 7 | **Test kirim kode di app** | ☐ |
| 8 | **Email masuk ke inbox** | ☐ |

---

Setelah semua langkah selesai, setiap kali user klik tombol "Kirim kode" di aplikasi Flutter, Cloud Function akan otomatis trigger dan mengirim email berisi kode verifikasi ke email pendaftar.
