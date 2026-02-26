# Setup Cloud Functions untuk Kirim Email Kode Verifikasi

Dokumen ini menjelaskan langkah-langkah lengkap untuk menggunakan **Cloud Functions** (Opsi 2) untuk mengirim email kode verifikasi otomatis saat user klik "Kirim kode" di aplikasi.

**Perubahan terbaru:** Aplikasi sekarang memanggil **Callable function `requestVerificationCode`** (bukan menulis langsung ke Firestore). Ini mengatasi error "Gagal mengirim kode" akibat Firestore Security Rules, karena penulisan dilakukan via Admin SDK di Cloud Function. Pastikan Anda **deploy ulang** Cloud Functions setelah update: `firebase deploy --only functions`

---

## Daftar Isi

1. [Persiapan](#persiapan)
2. [Install Firebase CLI](#install-firebase-cli)
3. [Setup Cloud Functions di Project](#setup-cloud-functions-di-project)
4. [Buat Cloud Function untuk Kirim Email](#buat-cloud-function-untuk-kirim-email)
5. [Setup Gmail App Password](#setup-gmail-app-password)
6. [Deploy Cloud Function](#deploy-cloud-function)
7. [Test Cloud Function](#test-cloud-function)
8. [Update Kode Flutter (Opsional)](#update-kode-flutter-opsional)
9. [Troubleshooting](#troubleshooting)

---

## Persiapan

Sebelum mulai, pastikan Anda sudah:

- ✅ **Firebase project sudah dibuat** dan aktif
- ✅ **Firestore Database sudah aktif** (sudah dibuat database-nya)
- ✅ **Node.js sudah terinstall** di komputer (versi 14 atau lebih baru)
  - Cek: buka Command Prompt/PowerShell → ketik `node --version`
  - Jika belum ada, download dari: https://nodejs.org/
- ✅ **Gmail account** untuk mengirim email (akan pakai App Password)
- ✅ **2-Step Verification aktif** di Gmail (wajib untuk App Password)

---

## Install Firebase CLI

Firebase CLI adalah tool command-line untuk mengelola Firebase project dari komputer.

### Langkah 1: Install Firebase CLI

1. **Buka Command Prompt atau PowerShell** (bukan Git Bash).
2. **Install Firebase CLI secara global:**
   ```bash
   npm install -g firebase-tools
   ```
3. **Tunggu sampai selesai** (biasanya 1-2 menit).
4. **Verifikasi instalasi:**
   ```bash
   firebase --version
   ```
   Seharusnya muncul versi Firebase CLI (misalnya `13.0.0` atau lebih baru).

### Langkah 2: Login ke Firebase

1. **Login ke Firebase:**
   ```bash
   firebase login
   ```
2. **Browser akan terbuka otomatis** → pilih akun Google yang sama dengan Firebase project.
3. **Klik "Allow"** untuk memberikan izin.
4. **Kembali ke Command Prompt** → seharusnya muncul pesan "Success! Logged in as [email Anda]".

### Langkah 3: Verifikasi Login

1. **Cek apakah sudah login:**
   ```bash
   firebase projects:list
   ```
2. Seharusnya muncul daftar Firebase projects Anda, termasuk project **"syafiul-traka"** (atau nama project Anda).

---

## Setup Cloud Functions di Project

### Langkah 1: Navigate ke Folder Project

1. **Buka Command Prompt atau PowerShell**.
2. **Masuk ke folder project Flutter:**
   ```bash
   cd "C:\Users\syafi\OneDrive\Dokumen\Traka\traka"
   ```
   (Ganti path sesuai lokasi project Anda jika berbeda)

### Langkah 2: Initialize Cloud Functions

1. **Jalankan perintah berikut:**
   ```bash
   firebase init functions
   ```
2. **Pilih project Firebase:**
   - Akan muncul daftar projects → pilih project **"syafiul-traka"** (atau nama project Anda).
   - Tekan **Enter**.

3. **Pilih bahasa:**
   - Pilih **JavaScript** (lebih mudah untuk pemula).
   - Tekan **Enter**.

4. **Install dependencies:**
   - Ketika ditanya "Do you want to install dependencies with npm now?", ketik **Y** (Yes) → tekan **Enter**.
   - Tunggu sampai selesai (biasanya 1-2 menit).

5. **Selesai!** Seharusnya muncul pesan "Firebase initialization complete!".

### Langkah 3: Verifikasi Struktur Folder

Setelah `firebase init functions`, struktur folder project Anda akan menjadi seperti ini:

```
traka/
├── android/
├── ios/
├── lib/
├── functions/          ← Folder baru untuk Cloud Functions
│   ├── index.js       ← File utama untuk Cloud Functions
│   ├── package.json   ← Dependencies untuk Cloud Functions
│   └── node_modules/  ← Dependencies yang sudah diinstall
├── pubspec.yaml
└── firebase.json       ← File konfigurasi Firebase (baru)
```

---

## Buat Cloud Function untuk Kirim Email

### Langkah 1: Install Nodemailer

Nodemailer adalah library Node.js untuk mengirim email.

1. **Masuk ke folder functions:**
   ```bash
   cd functions
   ```

2. **Install Nodemailer:**
   ```bash
   npm install nodemailer
   ```

3. **Tunggu sampai selesai** (biasanya 10-20 detik).

### Langkah 2: Buat Cloud Function

1. **Buka file `functions/index.js`** dengan text editor (VS Code, Notepad++, atau editor lain).

2. **Hapus semua isi file** (jika ada contoh kode default).

3. **Copy-paste kode berikut ke `functions/index.js`:**

```javascript
const functions = require('firebase-functions');
const admin = require('firebase-admin');
const nodemailer = require('nodemailer');

// Initialize Firebase Admin SDK
admin.initializeApp();

// Konfigurasi SMTP untuk Gmail
// GANTI EMAIL DAN APP PASSWORD ANDA DI SINI!
const gmailEmail = 'mcctv921@gmail.com'; // Ganti dengan email Gmail Anda
const gmailAppPassword = 'your-app-password-here'; // Ganti dengan App Password Gmail Anda

// Buat transporter untuk Nodemailer
const transporter = nodemailer.createTransport({
  service: 'gmail',
  auth: {
    user: gmailEmail,
    pass: gmailAppPassword,
  },
});

// Cloud Function yang trigger saat ada document baru di verification_codes
exports.sendVerificationCode = functions.firestore
  .document('verification_codes/{email}')
  .onCreate(async (snap, context) => {
    // Ambil data dari document yang baru dibuat
    const data = snap.data();
    const email = context.params.email; // Email user (document ID)
    const code = data.code; // Kode verifikasi 6 digit
    const expiresAt = data.expiresAt; // Waktu kedaluwarsa

    // Validasi: pastikan field 'code' ada
    if (!code) {
      console.error('Field "code" tidak ditemukan di document');
      return null;
    }

    // Template email (Text)
    const textTemplate = `
Halo,

Terima kasih telah mendaftar di Traka Travel Kalimantan.

Kode verifikasi Anda adalah: ${code}

Kode ini berlaku selama 10 menit.

Masukkan kode ini di aplikasi untuk menyelesaikan pendaftaran.

Jika Anda tidak meminta kode ini, abaikan email ini.

Salam,
Tim Traka Travel Kalimantan
    `.trim();

    // Template email (HTML)
    const htmlTemplate = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <style>
    body {
      font-family: Arial, sans-serif;
      line-height: 1.6;
      color: #333;
      max-width: 600px;
      margin: 0 auto;
      padding: 20px;
    }
    .container {
      background-color: #f9f9f9;
      padding: 30px;
      border-radius: 8px;
    }
    .code-box {
      background-color: #2563EB;
      color: white;
      font-size: 32px;
      font-weight: bold;
      text-align: center;
      padding: 20px;
      border-radius: 8px;
      margin: 20px 0;
      letter-spacing: 5px;
    }
    .footer {
      margin-top: 30px;
      font-size: 12px;
      color: #666;
    }
  </style>
</head>
<body>
  <div class="container">
    <h2>Halo,</h2>
    <p>Terima kasih telah mendaftar di <strong>Traka Travel Kalimantan</strong>.</p>
    
    <p>Kode verifikasi Anda adalah:</p>
    <div class="code-box">${code}</div>
    
    <p>Kode ini berlaku selama <strong>10 menit</strong>.</p>
    <p>Masukkan kode ini di aplikasi untuk menyelesaikan pendaftaran.</p>
    
    <p style="color: #999; font-size: 12px;">
      Jika Anda tidak meminta kode ini, abaikan email ini.
    </p>
    
    <div class="footer">
      <p>Salam,<br>Tim Traka Travel Kalimantan</p>
    </div>
  </div>
</body>
</html>
    `.trim();

    // Konfigurasi email
    const mailOptions = {
      from: `"Traka Travel Kalimantan" <${gmailEmail}>`,
      to: email,
      subject: 'Kode Verifikasi Traka Travel Kalimantan',
      text: textTemplate,
      html: htmlTemplate,
    };

    try {
      // Kirim email
      const info = await transporter.sendMail(mailOptions);
      console.log('Email berhasil dikirim:', info.messageId);
      console.log('Email dikirim ke:', email);
      console.log('Kode verifikasi:', code);
      return null;
    } catch (error) {
      console.error('Error mengirim email:', error);
      // Jangan throw error agar document tetap tersimpan di Firestore
      // User bisa kirim ulang kode jika email gagal
      return null;
    }
  });
```

4. **Simpan file** (`Ctrl + S`).

### Langkah 3: Update Gmail Email dan App Password

1. **Buka file `functions/index.js`**.
2. **Ganti baris 10 dan 11:**
   ```javascript
   const gmailEmail = 'mcctv921@gmail.com'; // Ganti dengan email Gmail Anda
   const gmailAppPassword = 'your-app-password-here'; // Ganti dengan App Password Gmail Anda
   ```
3. **Isi dengan email Gmail Anda** (misalnya `mcctv921@gmail.com`).
4. **Isi dengan App Password Gmail Anda** (16 karakter, tanpa spasi).
   - Jika belum punya App Password, ikuti langkah di bagian [Setup Gmail App Password](#setup-gmail-app-password) di bawah.

---

## Setup Gmail App Password

App Password adalah password khusus untuk aplikasi pihak ketiga (seperti Cloud Functions) agar bisa mengirim email via Gmail.

### Langkah 1: Aktifkan 2-Step Verification

1. **Buka:** https://myaccount.google.com/security
2. **Scroll ke bagian "2-Step Verification"**.
3. **Jika belum aktif:**
   - Klik **"2-Step Verification"** → ikuti langkah-langkah untuk mengaktifkan.
   - Anda perlu nomor HP untuk verifikasi.
4. **Jika sudah aktif:** lanjut ke Langkah 2.

### Langkah 2: Buat App Password

1. **Buka:** https://myaccount.google.com/apppasswords
2. **Jika diminta login:** login dengan akun Gmail Anda.
3. **Pilih app:** pilih **"Mail"** dari dropdown.
4. **Pilih device:** pilih **"Other (Custom name)"** → ketik **"Firebase Cloud Functions"** → klik **"Generate"**.
5. **Copy App Password yang muncul** (16 karakter, contoh: `abcd efgh ijkl mnop`).
   - **PENTING:** Hapus semua spasi saat memakai di kode (jadi: `abcdefghijklmnop`).
6. **Simpan App Password** di tempat aman (Anda tidak akan bisa melihatnya lagi setelah tutup halaman ini).

### Langkah 3: Update Kode Cloud Function

1. **Buka file `functions/index.js`**.
2. **Ganti `gmailAppPassword`** dengan App Password yang baru dibuat (tanpa spasi):
   ```javascript
   const gmailAppPassword = 'abcdefghijklmnop'; // App Password tanpa spasi
   ```
3. **Simpan file**.

---

## Deploy Cloud Function

Setelah kode Cloud Function siap, deploy ke Firebase.

### Langkah 1: Kembali ke Root Folder Project

1. **Dari folder `functions`**, kembali ke root folder:
   ```bash
   cd ..
   ```
   (Sekarang Anda di folder `traka/`)

### Langkah 2: Deploy Cloud Function

1. **Deploy function ke Firebase:**
   ```bash
   firebase deploy --only functions
   ```
2. **Tunggu sampai selesai** (biasanya 2-5 menit).
   - Akan muncul progress bar dan log.
   - Jika berhasil, akan muncul pesan seperti:
     ```
     ✔  functions[sendVerificationCode(us-central1)] Successful create operation.
     Function URL: https://us-central1-syafiul-traka.cloudfunctions.net/sendVerificationCode
     ```

### Langkah 3: Verifikasi Function Terdeploy

1. **Buka Firebase Console** → **Functions** (di menu kiri).
2. **Seharusnya muncul function `sendVerificationCode`** dengan status **"Active"**.
3. **Klik function tersebut** untuk melihat detail (region, trigger, dll.).

---

## Test Cloud Function

### Langkah 1: Test dari Aplikasi Flutter

1. **Buka aplikasi Flutter** di HP atau emulator.
2. **Masuk ke halaman registrasi**.
3. **Isi email** (misalnya `test@email.com`).
4. **Klik tombol refresh** (ikon circular arrow) di samping kolom "Masukkan kode verifikasi".
5. **Tunggu 10-30 detik** (Cloud Function perlu waktu untuk trigger dan kirim email).
6. **Cek email** yang Anda isi:
   - Cek **inbox**.
   - Cek **folder Spam/Junk** (terutama pertama kali).
   - Email seharusnya masuk dengan subjek **"Kode Verifikasi Traka Travel Kalimantan"** dan berisi kode 6 digit.

### Langkah 2: Cek Log Cloud Function

1. **Buka Firebase Console** → **Functions** → klik function **`sendVerificationCode`**.
2. **Buka tab "Logs"** atau **"Activity"**.
3. **Setelah klik "Kirim kode" di app**, tunggu beberapa detik lalu refresh log.
4. **Seharusnya muncul log:**
   - `Email berhasil dikirim: [message-id]`
   - `Email dikirim ke: [email]`
   - `Kode verifikasi: [kode]`
5. **Jika ada error**, log akan menampilkan error message (misalnya "Authentication failed" jika App Password salah).

---

## Update Kode Flutter (Opsional)

Kode Flutter Anda sudah benar dan tidak perlu diubah. Cloud Function akan otomatis trigger saat ada document baru di `verification_codes`.

Namun, jika Anda ingin menghapus SnackBar yang menampilkan kode (karena sekarang email sudah otomatis terkirim), Anda bisa update `register_screen.dart`:

### Langkah 1: Buka File `lib/screens/register_screen.dart`

### Langkah 2: Update Fungsi `_sendVerificationCode`

**Ganti bagian ini** (sekitar baris 162-176):

```dart
      if (!mounted) return;

      // TODO: Untuk production, kirim email lewat Cloud Functions atau email service
      // Untuk development/testing, tampilkan kode di SnackBar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.locale == AppLocale.id
                ? 'Kode verifikasi: $code (untuk testing)'
                : 'Verification code: $code (for testing)',
          ),
          duration: const Duration(seconds: 10),
          backgroundColor: Colors.green,
        ),
      );
```

**Dengan ini:**

```dart
      if (!mounted) return;

      // Cloud Function akan otomatis kirim email saat document dibuat
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.locale == AppLocale.id
                ? 'Kode verifikasi telah dikirim ke email Anda'
                : 'Verification code has been sent to your email',
          ),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.green,
        ),
      );
```

**Atau biarkan seperti sekarang** jika Anda masih ingin melihat kode di SnackBar untuk testing.

---

## Troubleshooting

### "Gagal mengirim kode" atau email tidak masuk

**Checklist singkat:**

1. **Deploy Cloud Functions** (WAJIB):
   ```bash
   cd "C:\Users\syafi\OneDrive\Dokumen\Traka\traka"
   firebase deploy --only functions
   ```
   Tunggu sampai muncul "✔ Deploy complete!". Jika error, pastikan project Blaze/Spark dan Node.js terinstall.

2. **Cek Gmail App Password** di `functions/index.js`:
   - Email: `syafiul060@gmail.com` (atau email Anda)
   - App Password: 16 karakter tanpa spasi (dari https://myaccount.google.com/apppasswords)
   - Jika salah, deploy ulang setelah edit.

3. **Cek Firestore**:
   - Firebase Console → Firestore → collection `verification_codes`
   - Saat klik "Kirim kode" di app, document dengan ID = email harus muncul.
   - Jika tidak muncul: Callable `requestVerificationCode` gagal atau belum terdeploy.

4. **Cek log Functions**:
   - Firebase Console → Functions → Logs
   - Cari error atau "Email berhasil dikirim" dari `sendVerificationCode`.

5. **Cek Spam/Junk** di inbox email.

### Error: "Authentication failed" saat kirim email

**Penyebab:** App Password salah atau format salah.

**Solusi:**
1. **Cek App Password di `functions/index.js`**:
   - Pastikan tidak ada spasi.
   - Pastikan 16 karakter (tanpa spasi).
2. **Buat App Password baru** di https://myaccount.google.com/apppasswords
3. **Update `gmailAppPassword` di `functions/index.js`**.
4. **Deploy ulang:** `firebase deploy --only functions`

### Error: "Function failed to deploy"

**Penyebab:** Ada syntax error di kode JavaScript atau dependencies belum diinstall.

**Solusi:**
1. **Cek syntax error:**
   - Buka `functions/index.js` → pastikan tidak ada typo atau tanda kurung yang tidak tertutup.
2. **Install dependencies:**
   ```bash
   cd functions
   npm install
   ```
3. **Deploy ulang:**
   ```bash
   cd ..
   firebase deploy --only functions
   ```

### Email tidak masuk

**Penyebab:** Cloud Function tidak trigger atau email masuk ke Spam.

**Solusi:**
1. **Cek apakah document muncul di Firestore:**
   - Firebase Console → Firestore Database → collection `verification_codes`
   - Setelah klik "Kirim kode", document harus muncul dengan ID = email.
2. **Cek log Cloud Function:**
   - Firebase Console → Functions → `sendVerificationCode` → Logs
   - Cek apakah ada error atau log "Email berhasil dikirim".
3. **Cek folder Spam/Junk** di email.
4. **Cek email yang diisi:** pastikan email benar dan bisa menerima email.

### Function tidak trigger

**Penyebab:** Trigger path salah atau function belum terdeploy.

**Solusi:**
1. **Cek trigger path di `functions/index.js`:**
   ```javascript
   .document('verification_codes/{email}')
   ```
   Pastikan collection name = `verification_codes` (persis seperti itu).
2. **Cek apakah function sudah terdeploy:**
   - Firebase Console → Functions → harus ada function `sendVerificationCode` dengan status "Active".
3. **Deploy ulang jika perlu:**
   ```bash
   firebase deploy --only functions
   ```

### Error: "firebase: command not found"

**Penyebab:** Firebase CLI belum terinstall atau tidak ada di PATH.

**Solusi:**
1. **Install ulang Firebase CLI:**
   ```bash
   npm install -g firebase-tools
   ```
2. **Restart Command Prompt/PowerShell**.
3. **Cek instalasi:**
   ```bash
   firebase --version
   ```

---

## Checklist Setup Cloud Functions

| No | Langkah | Sudah? | Catatan |
|----|---------|--------|---------|
| 1 | **Node.js terinstall** | ☐ | Cek: `node --version` |
| 2 | **Firebase CLI terinstall** | ☐ | Cek: `firebase --version` |
| 3 | **Login ke Firebase** | ☐ | `firebase login` |
| 4 | **Initialize Functions** | ☐ | `firebase init functions` |
| 5 | **Install Nodemailer** | ☐ | `cd functions && npm install nodemailer` |
| 6 | **Buat Cloud Function** | ☐ | Edit `functions/index.js` |
| 7 | **Setup Gmail App Password** | ☐ | https://myaccount.google.com/apppasswords |
| 8 | **Update email & App Password di kode** | ☐ | Edit `functions/index.js` |
| 9 | **Deploy Function** | ☐ | `firebase deploy --only functions` |
| 10 | **Test kirim kode di app** | ☐ | Klik tombol refresh di app |
| 11 | **Email masuk ke inbox** | ☐ | Cek email (termasuk Spam) |

---

## Catatan Penting

1. **Biaya Cloud Functions:**
   - Firebase memberikan **free tier** untuk Cloud Functions (2 juta invocations per bulan).
   - Untuk penggunaan normal, biasanya masih dalam free tier.
   - Cek pricing di: https://firebase.google.com/pricing

2. **Security:**
   - **Jangan commit App Password ke Git!**
   - Untuk production, gunakan **Environment Variables** atau **Firebase Config** (lihat di bawah).

### Konfigurasi Gmail via Environment Variables (Production)

Kode `functions/index.js` mendukung:

1. **Environment variables**: `GMAIL_EMAIL`, `GMAIL_APP_PASSWORD` (prioritas)
2. **Fallback** di kode (untuk migrasi; jangan commit ke Git di production)

**Catatan:** `firebase functions:config` sudah dihapus di firebase-functions v7. Gunakan environment variables.

**Cara set via Firebase Console (Environment variables):**
1. Firebase Console → Functions → pilih function → Edit
2. Atau: Project Settings → Environment variables
3. Tambah `GMAIL_EMAIL` dan `GMAIL_APP_PASSWORD`

**Cara set via .env (development):**
Buat file `functions/.env` dengan isi:
```
GMAIL_EMAIL=email@gmail.com
GMAIL_APP_PASSWORD=app-password-16-karakter
```

3. **Region:**
   - Cloud Function default menggunakan region **us-central1**.
   - Jika ingin ubah region (misalnya ke **asia-southeast1** untuk Indonesia), edit `firebase.json`:
     ```json
     {
       "functions": {
         "source": "functions",
         "runtime": "nodejs18"
       }
     }
     ```
     Dan update trigger di `functions/index.js`:
     ```javascript
     exports.sendVerificationCode = functions
       .region('asia-southeast1')
       .firestore
       .document('verification_codes/{email}')
       .onCreate(async (snap, context) => {
         // ...
       });
     ```

---

Setelah semua langkah di atas selesai, setiap kali user klik tombol "Kirim kode" di aplikasi Flutter, Cloud Function akan otomatis trigger dan mengirim email berisi kode verifikasi ke email pendaftar.
