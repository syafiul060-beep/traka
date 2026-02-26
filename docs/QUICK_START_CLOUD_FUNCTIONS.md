# Quick Start: Setup Cloud Functions untuk Email Verifikasi

Panduan cepat untuk setup Cloud Functions dalam 5 langkah.

---

## Prerequisites

- ✅ Node.js terinstall (cek: `node --version`)
- ✅ Gmail account dengan 2-Step Verification aktif
- ✅ Firebase project sudah dibuat

---

## Langkah 1: Install Firebase CLI

```bash
npm install -g firebase-tools
firebase login
```

---

## Langkah 2: Initialize Functions

```bash
cd "C:\Users\syafi\OneDrive\Dokumen\Traka\traka"
firebase init functions
```

Pilih:
- Project: **syafiul-traka** (atau nama project Anda)
- Language: **JavaScript**
- Install dependencies: **Y**

---

## Langkah 3: Setup Cloud Function

1. **Install Nodemailer:**
   ```bash
   cd functions
   npm install nodemailer
   ```

2. **Copy file template:**
   - Copy isi dari `functions_template/index.js`
   - Paste ke `functions/index.js` (replace semua isinya)

3. **Update email & App Password:**
   - Buka `functions/index.js`
   - Ganti `gmailEmail` dengan email Gmail Anda
   - Buat App Password di: https://myaccount.google.com/apppasswords
   - Ganti `gmailAppPassword` dengan App Password (16 karakter, tanpa spasi)

---

## Langkah 4: Deploy

```bash
cd ..
firebase deploy --only functions
```

Tunggu sampai selesai (2-5 menit).

---

## Langkah 5: Test

1. Buka aplikasi Flutter
2. Masuk ke halaman registrasi
3. Isi email → klik tombol refresh (ikon circular arrow)
4. Cek email (termasuk folder Spam)

---

## Troubleshooting

**Email tidak masuk?**
- Cek log: Firebase Console → Functions → `sendVerificationCode` → Logs
- Cek folder Spam/Junk
- Pastikan App Password benar (tanpa spasi)

**Function tidak trigger?**
- Cek apakah document muncul di Firestore: `verification_codes/{email}`
- Pastikan function sudah terdeploy: Firebase Console → Functions

**Error saat deploy?**
- Pastikan `functions/index.js` tidak ada syntax error
- Pastikan sudah `npm install` di folder `functions`

---

Untuk panduan lengkap, lihat: `docs/SETUP_CLOUD_FUNCTIONS_EMAIL.md`
