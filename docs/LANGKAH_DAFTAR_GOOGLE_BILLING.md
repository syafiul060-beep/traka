# Langkah-Langkah Daftar & Setup Pembayaran Google Play Billing (Traka)

Panduan ini menjelaskan cara mendaftar dan mengatur **Google Play Billing** agar fitur pembayaran in-app di aplikasi Traka bisa berjalan (Kontribusi driver, Lacak Driver, Lacak Barang, Pelanggaran).

---

## Daftar Isi

1. [Persyaratan Awal](#1-persyaratan-awal)
2. [Daftar Akun Google Play Developer](#2-daftar-akun-google-play-developer)
3. [Buat Aplikasi di Play Console](#3-buat-aplikasi-di-play-console)
4. [Aktifkan Billing di Play Console](#4-aktifkan-billing-di-play-console)
5. [Buat Produk In-App (Kontribusi)](#5-buat-produk-in-app-kontribusi)
5b. [Buat Produk Lacak Driver (Wajib untuk Bayar Lacak Driver)](#5b-buat-produk-lacak-driver-wajib-untuk-bayar-lacak-driver)
6. [Uji Coba dengan Akun Tes](#6-uji-coba-dengan-akun-tes)
7. [Linking ke Aplikasi (Package Name & SHA)](#7-linking-ke-aplikasi-package-name--sha)
8. [Ringkasan Data untuk Traka](#8-ringkasan-data-untuk-traka)

---

## 1. Persyaratan Awal

- **Akun Google** (Gmail).
- **Kartu kredit/debit** atau metode pembayaran lain untuk **biaya pendaftaran developer** (sekali bayar, sekitar **US$ 25**).
- **Aplikasi Traka** sudah bisa di-build Android (minimal debug/development build).
- **Package name** aplikasi: harus sama persis dengan yang di Play Console. Di project Traka dipakai: **`id.traka.app`**.

---

## 2. Daftar Akun Google Play Developer

1. Buka: **[Google Play Console](https://play.google.com/console)**  
   → [https://play.google.com/console](https://play.google.com/console)

2. Login dengan akun Google yang akan dipakai sebagai **pemilik developer**.

3. Jika belum terdaftar sebagai developer:
   - Klik **「Buat akun developer」** / **「Daftar」**.
   - Baca dan setujui **Perjanjian Developer Distribution**.
   - Isi data:
     - **Nama developer** (bisa nama pribadi atau nama usaha).
     - **Email**, **negara**, **jenis akun** (pribadi/perusahaan).
   - **Bayar biaya pendaftaran** (sekali bayar, ~US$ 25) dengan kartu kredit/debit.
   - Selesaikan verifikasi identitas jika diminta.

4. Setelah akun aktif, Anda akan masuk ke **Dasbor Play Console**.

---

## 3. Buat Aplikasi di Play Console

1. Di Play Console, klik **「Buat aplikasi」** / **「Create app」**.

2. Isi:
   - **Nama aplikasi:** misalnya **Traka** atau **Traka Travel Kalimantan**.
   - **Bahasa default:** Indonesia (atau sesuai).
   - **Jenis:** Aplikasi atau Game (pilih **Aplikasi**).
   - **Gratis atau berbayar:** pilih **Gratis** (karena kontribusi driver adalah in-app purchase, bukan harga aplikasi).

3. Centang pernyataan kebijakan privasi & aturan, lalu **「Buat」**.

4. Di sisi kiri, buka **「Kebijakan」** → selesaikan **Kebijakan privasi** dan **Kebijakan aplikasi** jika wajib (perlu untuk publish).

5. **Setup aplikasi** (penting untuk Billing):
   - Buka **「Semua aplikasi」** → pilih aplikasi Traka.
   - Masuk ke **「Setup」** → **「Detail aplikasi」**.
   - Isi **Package name** harus **sama persis** dengan `applicationId` di project Android: **`id.traka.app`**.

---

## 4. Aktifkan Billing di Play Console

1. Di menu kiri aplikasi, buka **「Monetize」** (Monetisasi) → **「Produk」** → **「In-app products」** (Produk dalam aplikasi).

2. Jika muncul opsi **「Aktifkan penagihan」** / **「Enable billing」**, ikuti langkah untuk:
   - Menerima **Perjanjian layanan penagihan** Google Play.
   - Melengkapi **profil pembayaran** (nama, alamat, pajak, metode pembayaran untuk menerima payout dari Google).

3. Setelah penagihan aktif, Anda bisa membuat **In-app products**.

---

## 5. Buat Produk In-App (Kontribusi)

1. Masuk ke **「Monetize」** → **「In-app products」** → **「Buat produk」** / **「Create product」**.

2. Pilih **「Managed products」** (produk sekali beli, bukan langganan).

3. Isi form:

   | Field | Nilai untuk Traka | Keterangan |
   |-------|-------------------|------------|
   | **Product ID** | **`traka_contribution_once`** | **Harus persis** sama dengan di kode (`kContributionProductId` di `contribution_driver_screen.dart`). Tidak bisa diubah setelah dibuat. |
   | **Name** | Kontribusi Traka (atau nama lain) | Nama yang tampil di Play. |
   | **Description** | Bayar kontribusi driver setelah melayani penumpang 2× kapasitas mobil. | Deskripsi untuk review. |
   | **Price** | Tentukan harga (misalnya Rp 5.000 / Rp 10.000) | Bisa pakai **Harga default** atau atur per negara. |

4. **Status:** set **「Active」** setelah selesai (bisa diaktifkan setelah testing).

5. Simpan. Produk **`traka_contribution_once`** akan muncul di daftar produk dalam aplikasi.

6. **Penting:** Pastikan **Package name** aplikasi di Play Console sama dengan **applicationId** di `android/app/build.gradle.kts` (atau `build.gradle`) agar Billing API mengenali aplikasi.

---

## 5b. Buat Produk Lacak Driver (Wajib untuk Bayar Lacak Driver)

**Error "Item yang Anda coba beli tidak dapat ditemukan"** muncul karena produk **belum dibuat** di Google Play Console. Ikuti langkah berikut:

1. Masuk ke **「Monetize」** → **「In-app products」** → **「Buat produk」** / **「Create product」**.

2. Pilih **「Consumable products」** (produk habis pakai – bisa dibeli berulang per pesanan).

3. Isi form:

   | Field | Nilai | Keterangan |
   |-------|-------|------------|
   | **Product ID** | **`traka_lacak_driver`** | **Harus persis** sama dengan di kode. Untuk Rp 3000 pakai ID ini. |
   | **Name** | Lacak Driver | Nama yang tampil di Play. |
   | **Description** | Bayar untuk melacak posisi driver di peta per pesanan. Berlaku sampai driver memindai barcode atau terkonfirmasi otomatis. | Deskripsi untuk review. |
   | **Price** | Rp 3.000 | Google Play minimum Rp 3.000. Atur di **Default price** atau per negara. |

4. **Status:** set **「Active」** setelah selesai.

5. Simpan. Produk **`traka_lacak_driver`** akan muncul di daftar.

6. **Jika tarif diubah** (via Firestore `app_config/settings.lacakDriverFeeRupiah` ke nilai selain 3000), buat produk tambahan dengan ID **`traka_lacak_driver_{amount}`**, misalnya `traka_lacak_driver_5000` untuk Rp 5.000.

**Lokasi di kode:** `lib/screens/lacak_driver_payment_screen.dart` → `lacakDriverProductId()`

**Backend verifikasi:** Cloud Function `verifyPassengerTrackPayment`

---

## 6. Uji Coba dengan Akun Tes

1. **License testing (opsional tapi berguna):**
   - Buka **「Setup」** → **「License testing」**.
   - Tambahkan **email Gmail** yang dipakai di HP/emulator untuk testing.
   - Dengan ini Anda bisa **membeli produk tanpa debit kartu sungguhan** (Google memberi “pembelian tes”).

2. **Internal testing / Closed testing:**
   - Buat **track testing** (Internal atau Closed).
   - Upload **AAB** (Android App Bundle) aplikasi Traka.
   - Tambahkan **tester** (email). Tester bisa mengunduh dari link testing dan melakukan pembelian tes.

3. Di HP/emulator:
   - Login dengan **akun tester**.
   - Buka aplikasi Traka → masuk sebagai driver → trigger **Bayar kontribusi** (saat `mustPayContribution` true).
   - Pilih produk **traka_contribution_once** → selesaikan alur pembelian tes.
   - Cek di backend (Firestore `users/{uid}.contributionPaidUpToCount`) bahwa verifikasi pembayaran diproses (jika Cloud Function `verifyContributionPayment` sudah dipanggil).

---

## 7. Linking ke Aplikasi (Package Name & SHA)

Agar **Google Play Billing** mengenali aplikasi:

1. **Package name** di Play Console **harus sama** dengan **applicationId** di project:
   - File: **`android/app/build.gradle.kts`** (atau `build.gradle`).
   - Nilai yang dipakai: **`applicationId = "id.traka.app"`**. Harus **sama persis** dengan package name yang didaftarkan di Play Console untuk aplikasi Traka.

2. **Signing key:**
   - Untuk **release** dan **upload ke Play**, aplikasi harus di-sign dengan **upload key** / **app signing key** yang terdaftar di Play Console.
   - Setelah upload AAB pertama, Play akan menampilkan **App signing** (SHA-1, dll.). Tidak perlu konfigurasi tambahan khusus hanya untuk Billing; yang penting aplikasi ter-upload dengan package name yang benar.

3. **Cloud Function** (verifikasi pembayaran):
   - Di `functions/index.js`, callable **`verifyContributionPayment`** memakai default **`packageName = "id.traka.app"`**. App bisa mengirim `packageName` opsional; jika tidak, backend memakai `id.traka.app`.

---

## 8. Ringkasan Data untuk Traka

| Fitur | Product ID | Jenis | Lokasi di kode |
|-------|------------|-------|----------------|
| **Kontribusi driver** | `traka_contribution_once` | Managed (sekali beli) | `contribution_driver_screen.dart` |
| **Lacak Driver** | `traka_lacak_driver` (Rp 3000) | Consumable | `lacak_driver_payment_screen.dart` |
| **Lacak Driver (nominal lain)** | `traka_lacak_driver_{amount}` | Consumable | idem |
| **Lacak Barang** | `traka_lacak_barang_{tier}_{amount}` | Consumable | `lacak_barang_payment_screen.dart` |
| **Pelanggaran** | `traka_violation_fee_{amount}` | Consumable | `violation_pay_screen.dart` |

| Item | Nilai |
|------|--------|
| **Package name app** | **`id.traka.app`** (sama dengan `applicationId` di `android/app/build.gradle.kts`) |
| **Backend verifikasi** | `verifyContributionPayment`, `verifyPassengerTrackPayment`, dll. |

**Catatan:** Setelah package name diubah ke **id.traka.app**, di **Firebase Console** tambah aplikasi Android dengan package **id.traka.app** dan unduh **google-services.json** baru ke `android/app/`. Lihat **LANGKAH_UBAH_PACKAGE_NAME_MANUAL.md** untuk langkah lengkap.

---

## Troubleshooting Singkat

- **Produk tidak muncul di app:** Pastikan Product ID **persis sama** dengan di kode, status produk **Active**, dan aplikasi sudah di-upload ke track testing/production dengan package name yang sama.
- **"Item yang Anda coba beli tidak dapat ditemukan" / "Item not found":** Produk **belum dibuat** di Play Console. Buat produk dengan Product ID yang benar (misalnya **`traka_lacak_driver`** untuk Lacak Driver Rp 3000). Lihat [5b. Buat Produk Lacak Driver](#5b-buat-produk-lacak-driver-wajib-untuk-bayar-lacak-driver).
- **Cek License testing / akun tester:** Kadang perlu menunggu beberapa menit setelah produk diaktifkan.
- **Pembayaran tidak tervalidasi di backend:** Pastikan Cloud Function dipanggil dengan **purchaseToken** dan **orderId** dari `PurchaseDetails` setelah pembelian berhasil; untuk production, verifikasi ke **Google Play Developer API** (androidpublisher) disarankan.

Setelah langkah di atas selesai, alur pembayaran in-app (Lacak Driver, Kontribusi, dll.) siap dipakai di lingkungan testing dan production.
