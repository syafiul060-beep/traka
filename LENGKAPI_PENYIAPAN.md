# Lengkapi Penyiapan Aplikasi Traka

Checklist langkah demi langkah di Play Console. Selesaikan satu per satu.

---

## Cara Navigasi di Play Console

Dari **Dasbor**, gunakan **sidebar kiri**:
- Scroll ke bawah jika menu tidak terlihat
- Klik panah (▶) untuk membuka submenu

**Alternatif:** Di Dasbor, cari **"Selesaikan penyiapan aplikasi"** atau **"Lihat tugas"** → klik untuk melihat daftar tugas dengan link langsung ke setiap item.

---

## 1. Store Listing

**Lokasi:** Sidebar → **Kembangkan basis pengguna** (Grow) → **Kehadiran di toko** (Store presence) → **Listing utama toko** (Main store listing)

| Field | Isi |
|-------|-----|
| **Short description** (max 80 karakter) | Travel & kirim barang. Lacak driver dan barang real-time. |
| **Full description** | Deskripsi lengkap fitur Traka: pemesanan travel, kirim barang, Lacak Driver, Lacak Barang, verifikasi wajah, dll. |
| **App icon** | 512 x 512 px, PNG (dari `assets/images/icon_traka.png` resize) |
| **Feature graphic** | 1024 x 500 px |
| **Phone screenshots** | Min 2 screenshot HP (ambil dari aplikasi) |
| **App category** | Travel & Local |
| **Contact email** | Email support Anda |
| **Privacy policy URL** | `https://syafiul-traka.web.app/legal/privacy.html` |

---

## 2. Privacy Policy

**Lokasi:** Sidebar → **Kebijakan** (Policy) → **Konten aplikasi** (App content) → **Kebijakan privasi** (Privacy policy)

- Klik **Start** atau **Manage**
- Pilih **Enter URL**
- Isi: `https://syafiul-traka.web.app/legal/privacy.html`
- Simpan

---

## 3. Data Safety

**Lokasi:** Sidebar → **Kebijakan** → **Konten aplikasi** → **Keamanan data** (Data safety)

- Klik **Start** atau **Manage**
- Jawab: **Ya, aplikasi mengumpulkan data**
- Tambahkan data berikut:

| Data | Dikumpulkan | Dibagikan | Tujuan |
|------|-------------|-----------|--------|
| Nama, email | Ya | Tidak | Akun, layanan |
| Nomor telepon | Ya | Tidak | Akun, layanan |
| Foto profil / wajah | Ya | Tidak | Keamanan akun |
| Lokasi | Ya | Ya | Layanan travel, lacak |
| Device ID | Ya | Tidak | Keamanan |

- Untuk data sensitif (foto wajah, KTP): pilih **Ya** dan jelaskan penggunaan
- Simpan

---

## 4. App Access (Akun Demo)

**Lokasi:** Sidebar → **Kebijakan** → **Konten aplikasi** → **Akses aplikasi** (App access)

- Klik **Manage** di "All or some functionality is restricted"
- Pilih **Provide login credentials**
- Tambah **2 petunjuk** (klik "+ Tambahkan petunjuk" dua kali):

  **Petunjuk 1 – Penumpang:**
  - Nama: `Akun demo penumpang Traka`
  - Email: `demo@traka.app`
  - Sandi: `Demo123!`

  **Petunjuk 2 – Driver:**
  - Nama: `Akun demo driver Traka`
  - Email: `codeanalytic9@gmail.com`
  - Sandi: `Syafiul.04`

**Buat akun demo dulu** (jika belum):
```cmd
cd D:\Traka\traka\functions
node scripts/create-demo-account.js
```

---

## 5. Ads / In-App Purchases

**Lokasi:** Sidebar → **Kebijakan** → **Konten aplikasi** → **Iklan atau pembelian dalam aplikasi**

- Pilih **Ya, aplikasi saya berisi pembelian dalam aplikasi** (karena ada Lacak Barang, Lacak Driver)
- Simpan

---

## 6. Target Audience & Content

**Lokasi:** Sidebar → **Kebijakan** → **Konten aplikasi** (semua item di halaman ini)

- **Target age group:** Pilih grup usia yang sesuai (mis. 13+ atau 18+)
- **News app:** Tidak (jika bukan aplikasi berita)
- **COVID-19:** Tidak (jika tidak relevan)
- **Data safety:** Sudah di langkah 3

---

## Checklist Selesai

- [ ] Store listing lengkap
- [ ] Privacy policy URL
- [ ] Data safety
- [ ] App access (akun demo)
- [ ] Ads / in-app purchases
- [ ] Target audience

Semua item di **App content** harus berstatus hijau/complete sebelum bisa submit ke Production.
