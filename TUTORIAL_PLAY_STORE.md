# Tutorial: Submit Aplikasi Traka ke Google Play Store

Panduan langkah demi langkah untuk mengunggah dan mempublikasikan aplikasi Traka di Google Play Console.

---

## Persiapan

Pastikan sudah selesai:
- [x] Build AAB: `flutter build appbundle` → file di `traka/build/app/outputs/bundle/release/app-release.aab`
- [x] Akun Google Play Developer (biaya pendaftaran sekali)
- [x] Privacy Policy dan Terms sudah online

---

## 1. Upload AAB ke Play Console

### 1.1 Buat Aplikasi Baru (jika belum)

1. Buka [Google Play Console](https://play.google.com/console)
2. Klik **Create app**
3. Isi:
   - **App name:** Traka
   - **Default language:** Indonesian
   - **App or game:** App
   - **Free or paid:** Free (dengan in-app purchases)
4. Centang persetujuan dan klik **Create app**

### 1.2 Upload AAB ke Production

1. Di sidebar: **Release** → **Production** → **Create new release**
2. Klik **Upload** dan pilih file:
   ```
   D:\Traka\traka\build\app\outputs\bundle\release\app-release.aab
   ```
3. Tunggu proses upload dan verifikasi
4. Isi **Release name** (mis. `1.0.0 (1)`)
5. Tambahkan **Release notes** (deskripsi singkat fitur/update)
6. Klik **Save** → **Review release** → **Start rollout to Production**

> **Catatan:** Untuk testing dulu, bisa pakai **Internal testing** atau **Closed testing** sebelum Production.

---

## 2. Store Listing

Di sidebar: **Grow** → **Store presence** → **Main store listing**

### 2.1 Informasi Dasar

| Field | Contoh |
|-------|--------|
| **Short description** (max 80 karakter) | Travel & kirim barang. Lacak driver dan barang real-time. |
| **Full description** (max 4000 karakter) | Deskripsi lengkap fitur: travel, kirim barang, lacak driver, lacak barang, pembayaran, dll. |

### 2.2 Grafik

| Asset | Spesifikasi |
|-------|-------------|
| **App icon** | 512 x 512 px, PNG 32-bit |
| **Feature graphic** | 1024 x 500 px |
| **Phone screenshots** | Min 2, max 8; 16:9 atau 9:16 |
| **Tablet screenshots** (opsional) | Min 1 |

### 2.3 Kategori & Kontak

- **App category:** Travel & Local (atau sesuai)
- **Contact email:** email support Anda
- **Privacy policy URL:** `https://syafiul-traka.web.app/legal/privacy.html`

---

## 3. Privacy Policy

1. Di sidebar: **Policy** → **App content**
2. Cari **Privacy policy**
3. Klik **Start** atau **Manage**
4. Pilih **Enter URL** dan isi:
   ```
   https://syafiul-traka.web.app/legal/privacy.html
   ```
5. Simpan

---

## 4. Data Safety

1. Di sidebar: **Policy** → **App content** → **Data safety**
2. Klik **Start** atau **Manage**
3. Jawab pertanyaan sesuai data yang dikumpulkan Traka:

**Data yang dikumpulkan (sesuai Privacy Policy):**

| Data | Dikumpulkan? | Dibagikan? | Tujuan |
|------|--------------|------------|--------|
| Nama, email | Ya | Tidak | Akun, layanan |
| Nomor telepon | Ya (jika user tambah) | Tidak | Akun, layanan |
| Foto profil / verifikasi wajah | Ya | Tidak | Keamanan akun |
| Lokasi | Ya | Ya (ke driver/penumpang) | Layanan travel, lacak |
| Device ID | Ya | Tidak | Keamanan, identifikasi |

4. Jika ada data sensitif (foto wajah, KTP, STNK): pilih **Yes** dan jelaskan penggunaan
5. Simpan dan submit

---

## 5. Akun Demo untuk Reviewer

Google membutuhkan kredensial login agar reviewer bisa menguji aplikasi.

### 5.1 Buat Akun Demo

1. Buka terminal/CMD
2. Jalankan:
   ```cmd
   cd D:\Traka\traka\functions
   node scripts/create-demo-account.js
   ```
3. Pastikan `serviceAccountKey.json` ada di folder `functions/` (dari Firebase Console)
4. Catat output:
   - **Email:** `demo@traka.app`
   - **Password:** `Demo123!`

### 5.2 Isi di Play Console

1. Di sidebar: **Policy** → **App content** → **App access**
2. Klik **Manage** di bagian "All or some functionality is restricted"
3. Pilih **Provide login credentials**
4. Tambah:
   - **Username/Email:** `demo@traka.app`
   - **Password:** `Demo123!`
   - **Instructions:**  
     `Akun penumpang untuk demo. Login untuk menguji fitur travel, Lacak Driver, Lacak Barang. Tidak perlu verifikasi wajah.`

> Detail lengkap: lihat `traka/DEMO_ACCOUNT.md`

---

## 6. In-App Products (Lacak Barang, Lacak Driver, dll.)

Jika aplikasi punya pembelian dalam aplikasi (Lacak Barang, Lacak Driver, violation fee, kontribusi driver):

### 6.1 Setup Merchant

1. Di Play Console: **Monetize** → **Monetization setup**
2. Ikuti langkah untuk menghubungkan **Merchant account** (Google Pay)
3. Lengkapi informasi pajak dan pembayaran

### 6.2 Buat Produk

1. **Monetize** → **Products** → **In-app products**
2. Klik **Create product**
3. Isi untuk setiap produk:

**Contoh: Lacak Barang**
- **Product ID:** `lacak_barang` (harus sama dengan di kode)
- **Name:** Lacak Barang
- **Description:** Fitur lacak lokasi barang real-time
- **Price:** Tentukan harga (mis. Rp 5.000)
- **Status:** Active

**Contoh: Lacak Driver**
- **Product ID:** `lacak_driver`
- **Name:** Lacak Driver
- **Description:** Lacak posisi driver real-time
- **Price:** Sesuai config
- **Status:** Active

4. Pastikan Product ID di Play Console **sama persis** dengan yang dipakai di kode Flutter

### 6.3 Deklarasi di App Content

1. **Policy** → **App content** → **Ads or in-app purchases**
2. Pilih **Yes, my app contains in-app purchases**
3. Simpan

---

## 7. Checklist Sebelum Submit

- [ ] AAB diupload ke Production (atau testing)
- [ ] Store listing lengkap (deskripsi, ikon, screenshot)
- [ ] Privacy policy URL diisi
- [ ] Data safety diisi
- [ ] Akun demo login credentials diisi
- [ ] In-app products dibuat (jika ada)
- [ ] Merchant account terhubung (jika ada pembelian)
- [ ] Semua item di **App content** berstatus hijau/complete

---

## 8. Setelah Submit

1. **Review:** Google biasanya memproses 1–7 hari
2. **Status:** Cek di **Release** → **Production** → status rollout
3. **Update:** Untuk update berikutnya, buat release baru dan upload AAB baru

---

## 9. Referensi

| File | Keterangan |
|------|------------|
| `SIGNING_SETUP.md` | Setup keystore dan signing |
| `DEMO_ACCOUNT.md` | Detail akun demo |
| `CEK_APLIKASI.md` | Ringkasan fitur dan kondisi app |

---

**Terakhir diperbarui:** Februari 2025
