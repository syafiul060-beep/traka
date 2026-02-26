# Akun Demo untuk Google Play Review

## Cara Membuat Akun Demo

### Opsi 1: Pakai Script (Disarankan)

1. **Buat Service Account Key** (sekali saja):
   - Buka [Firebase Console](https://console.firebase.google.com) → project **syafiul-traka**
   - Project Settings (ikon gear) → Service Accounts
   - Klik "Generate new private key"
   - Simpan file sebagai `traka/functions/serviceAccountKey.json`
   - (Tambahkan ke .gitignore agar tidak ikut commit)

2. **Jalankan script**:
   ```bash
   cd traka/functions
   node scripts/create-demo-account.js
   ```
   (Pastikan `firebase-admin` terinstall: `npm install` di folder functions)

3. **Catat kredensial** yang ditampilkan:
   - Email: `demo@traka.app`
   - Password: `Demo123!`

### Opsi 2: Manual (Lewat Aplikasi)

1. Buka aplikasi Traka
2. Daftar akun baru dengan email yang mudah diingat (mis. `demo.penumpang@gmail.com`)
3. Lengkapi registrasi (verifikasi email, foto, dll.)
4. Catat email dan password

5. **Untuk bypass verifikasi wajah di device reviewer**, tambahkan field di Firestore:
   - Buka Firebase Console → Firestore → `users/{uid}`
   - Tambah field: `isDemoAccount` = `true` (boolean)

---

## Isi di Play Console

1. Buka **Play Console** → Aplikasi Traka
2. **App content** → **App access** → **Manage**
3. Tambah **Login credentials**:
   - Email: (dari langkah di atas)
   - Password: (dari langkah di atas)
   - Instructions: "Akun penumpang untuk demo. Login untuk menguji fitur travel, Lacak Driver, Lacak Barang."

---

## Catatan

- Akun demo dengan `isDemoAccount: true` **tidak perlu verifikasi wajah** saat login dari device baru (untuk reviewer).
- Jangan gunakan akun demo untuk keperluan selain review.
- Setelah review selesai, bisa hapus atau nonaktifkan akun demo.
