# Saran: Otomatis vs Scan Barcode & Pencegahan Permainan Driver

> **Status:** Fitur hybrid (scan + semi-otomatis) sudah diprogram: radius **700 m**, validasi scan, tombol Batal dinonaktifkan saat dekat, tombol "Konfirmasi dijemput" / "Konfirmasi sampai tujuan" tanpa scan (efisien baterai/data). Lihat `OrderService.radiusDekatMeter`, validasi di `applyDriverScanPassenger` / `applyPassengerScanDriver`, dan tombol di Data Order (driver & penumpang).

Dokumen ini berisi **saran** (sebagian sudah diprogram) untuk dua pendekatan: **(1)** penandaan jemput/sampai tujuan secara **otomatis** tanpa scan barcode, dan **(2)** scan barcode dengan **batasan lokasi** plus cara **mencegah permainan driver**.

---

## Ringkasan Dua Pendekatan

| Aspek | Opsi 1: Otomatis | Opsi 2: Scan + Batasan Lokasi |
|-------|------------------|-------------------------------|
| Jemput | Driver & penumpang dekat + konfirmasi / pergerakan sama | Driver scan barcode penumpang **hanya jika** jarak driver–penumpang dekat |
| Sampai tujuan | Driver & penumpang sama-sama di tujuan, lalu lokasi menjauh | Penumpang scan barcode driver **hanya jika** dekat **dan** di lokasi tujuan penumpang |
| Konfirmasi manual | Bisa pakai tombol "Konfirmasi dijemput" / "Sampai tujuan" (opsional) | Tetap pakai scan sebagai bukti |
| Pencegahan abuse | Batasan jarak, waktu, dan validasi lokasi | Batasan jarak + validasi tujuan sebelum scan diizinkan |

---

## 1. Opsi 1: Otomatis (Tanpa Scan Barcode)

### 1.1 Konsep

- **Jemput:** Aplikasi mendeteksi bahwa driver dan penumpang **saling dekat** (misalnya &lt; 200 m), lalu salah satu atau kedua pihak **konfirmasi** "Penumpang sudah dijemput". Alternatif: jika **pergerakan driver dan penumpang sama** (posisi bergerak bersama) dalam waktu tertentu, dianggap penumpang sudah di mobil.
- **Sampai tujuan:** Driver dan penumpang **sama-sama dekat dengan titik tujuan** penumpang (destLat/destLng), lalu setelah **beberapa waktu** (misalnya 1–2 menit) **lokasi penumpang dan driver menjauh** → dianggap penumpang sudah turun, pesanan selesai otomatis.
- **Riwayat:** Pesanan yang selesai otomatis tetap masuk **Data Riwayat** (tidak ada pembatalan).
- **Pembatalan:** Jika driver dan penumpang **sudah saling dekat**, tombol **Batal** dan **Konfirmasi** bisa **dinonaktifkan** (tidak bisa diklik) agar tidak dipakai untuk main-main atau memaksa batalkan di tengah jalan.

### 1.2 Alur Terperinci (Saran)

**A. Penumpang dijemput (otomatis / semi-otomatis)**

- **Trigger:** Lokasi driver dan penumpang **jarak &lt; R meter** (misalnya R = 150–300 m) di sekitar **titik jemput** (passengerLat/passengerLng atau radius).
- **Opsi A – Konfirmasi:** Muncul tombol "Konfirmasi penumpang sudah dijemput" (bisa di sisi driver saja, atau driver + penumpang). Hanya bisa diklik jika jarak driver–penumpang &lt; R. Setelah diklik → status order jadi `picked_up`, catat waktu dan titik jemput (lokasi saat konfirmasi).
- **Opsi B – Otomatis penuh:** Jika jarak &lt; R dan **vektor pergerakan** driver dan penumpang **sama** (bergerak bersama) selama misalnya 1–2 menit, sistem otomatis set `picked_up` dan simpan titik jemput. Lebih rumit (butuh background lokasi + analisis pergerakan).

**B. Penumpang sampai tujuan (otomatis)**

- **Trigger:**  
  1. Driver **dan** penumpang **sama-sama dekat dengan tujuan** penumpang (jarak ke destLat/destLng &lt; T meter, misalnya T = 200–500 m).  
  2. Setelah **durasi tunggu** (misalnya 1–2 menit) di zona tujuan, **lokasi penumpang dan driver menjauh** (jarak antara mereka &gt; D meter, misalnya D = 100–200 m) → dianggap penumpang sudah turun.
- **Aksi:** Status order jadi `completed`, simpan titik turun (lokasi penumpang saat "menjauh"), hitung jarak dan tarif seperti sekarang.
- **Riwayat:** Order completed tetap masuk riwayat (driver & penumpang).

**C. Pembatalan – batasan**

- Jika **jarak driver–penumpang &lt; batas** (misalnya 300 m): **tombol Batal** dan **Konfirmasi** (yang terkait kesepakatan/jemput) **tidak bisa diklik** (disabled). Alasannya: agar tidak ada pembatalan atau konfirmasi "main-main" saat mereka sudah bertemu.
- Batas jarak bisa pakai nilai yang sama dengan batas "dekat untuk jemput".

### 1.3 Kelebihan & Kekurangan (Otomatis)

**Kelebihan:**

- Tidak perlu scan barcode; UX lebih sederhana.
- Bisa dipakai di daerah/HP yang kamera atau barcode bermasalah.
- Selesai perjalanan bisa benar-benar otomatis jika logika pergerakan + zona tujuan jelas.

**Kekurangan:**

- Butuh **lokasi real-time** driver dan penumpang (background / polling) → baterai dan privacy.
- Deteksi "bergerak bersama" atau "sudah sampai lalu menjauh" bisa salah (GPS noise, delay).
- Tanpa scan, **bukti fisik** "jemput/sampai" lebih lemah; driver/penumpang bisa klaim tidak jemput/sampai.

### 1.4 Pencegahan Permainan Driver (Opsi Otomatis)

- **Hanya set "dijemput" jika jarak &lt; R** dan (opsional) **hanya dalam radius X km dari titik jemput** penumpang (passengerLat/passengerLng). Jadi driver tidak bisa "klik jemput" dari jauh.
- **Selesai tujuan:** Hanya bisa otomatis completed jika **keduanya pernah dalam radius tujuan** (destLat/destLng) dan **baru kemudian** jarak mereka menjauh. Tambah **minimum waktu** di zona tujuan (misalnya 1 menit) agar tidak langsung selesai begitu masuk radius.
- **Rate limit / flag:** Jika satu driver sering memicu "jemput" atau "selesai" dalam waktu sangat singkat atau pola mencurigakan, bisa di-flag untuk review admin.
- **Tombol Batal/Konfirmasi dinonaktifkan saat dekat** mengurangi main-main di saat ketemu.

---

## 2. Opsi 2: Scan Barcode + Batasan Lokasi

### 2.1 Konsep

- **Tetap pakai scan barcode** untuk jemput dan sampai tujuan, tapi **scan hanya diizinkan** jika kondisi lokasi terpenuhi.
- **Driver scan penumpang:** Hanya bisa dilakukan jika **jarak driver–penumpang dekat** (misalnya &lt; 200 m). Mencegah driver scan dari rumah tanpa benar-benar jemput.
- **Penumpang scan driver:** Hanya bisa dilakukan jika **(1)** jarak driver–penumpang dekat **dan (2)** mereka **berada di/dekat lokasi tujuan** penumpang (destLat/destLng, radius misalnya 300 m). Mencegah penumpang scan di tengah jalan atau driver minta scan sebelum sampai.

### 2.2 Alur Terperinci (Saran)

**A. Driver scan barcode penumpang (jemput)**

- **Validasi sebelum scan dianggap sah:**
  - Lokasi **driver** dan **penumpang** (dari order: passengerLat/passengerLng atau lokasi real-time penumpang) **jarak &lt; R_ Jemput** (misalnya 200 m).
- Jika scan dilakukan **di luar jarak** tersebut: tampilkan error "Lokasi Anda belum dekat dengan penumpang. Mendekatlah untuk melakukan scan."
- Jika **di dalam jarak**: proses scan seperti sekarang (update driverScannedAt, pickupLat/pickupLng, status picked_up, dll).

**B. Penumpang scan barcode driver (sampai tujuan)**

- **Validasi sebelum scan dianggap sah:**
  1. **Jarak driver–penumpang &lt; R_Turun** (misalnya 200 m) — mereka masih bertemu.
  2. **Lokasi penumpang (atau driver)** **dekat dengan tujuan** penumpang: jarak ke **destLat, destLng** &lt; T meter (misalnya T = 300–500 m).
- Jika scan dilakukan **sebelum sampai tujuan** (jarak ke tujuan masih besar): tampilkan error "Anda belum di lokasi tujuan. Scan hanya dapat dilakukan saat sudah sampai tujuan."
- Jika **sudah dekat tujuan dan dekat driver**: proses scan seperti sekarang (passengerScannedAt, dropLat/dropLng, tripDistanceKm, tripFareRupiah, status completed).

**C. Pembatalan**

- Jika **jarak driver–penumpang &lt; batas** (misalnya 300 m): **tombol Batal** (dan konfirmasi terkait) **tidak bisa diklik**. Alasannya: saat sudah ketemu, tidak boleh asal batalkan tanpa alasan yang wajar (bisa ditambah flow "laporkan masalah" kalau mau).

### 2.3 Kelebihan & Kekurangan (Scan + Lokasi)

**Kelebihan:**

- **Bukti kuat:** Scan = bukti bahwa kedua pihak bertemu (jemput) dan bertemu di tujuan (turun).
- **Mencegah jemput palsu:** Driver tidak bisa scan dari jauh.
- **Mencegah selesai palsu:** Penumpang tidak bisa scan sebelum sampai tujuan; driver tidak bisa maksa scan di tengah jalan.

**Kekurangan:**

- Tetap butuh **lokasi real-time** (driver dan penumpang) untuk validasi jarak dan "di tujuan".
- Di daerah GPS jelek, kadang "sudah di tujuan" belum terdeteksi → user bisa bingung. Solusi: radius tujuan jangan terlalu ketat (misalnya 300–500 m), dan tampilkan pesan yang jelas.

### 2.4 Pencegahan Permainan Driver (Opsi Scan)

- **Driver tidak bisa scan dari jauh:** Hanya boleh scan jika jarak ke penumpang &lt; R. Server/cloud function bisa validasi: terima lokasi driver saat scan, bandingkan dengan lokasi penumpang (real-time atau terakhir), tolak jika &gt; R.
- **Penumpang tidak bisa scan sebelum sampai:** Validasi "di tujuan" berdasarkan destLat/destLng + radius. Scan yang dikirim dari lokasi yang jauh dari tujuan → ditolak dengan pesan jelas.
- **Lokasi wajib dikirim saat scan:** Saat scan (driver atau penumpang), app kirim **latitude, longitude** ke backend. Backend menghitung jarak dan memutuskan terima/tolak. Jangan hanya andal validasi di app (bisa dimanipulasi).
- **Tombol Batal dinonaktifkan saat dekat:** Mengurangi skenario "sudah ketemu lalu batalkan" untuk main-main atau memaksa.

---

## 3. Rekomendasi Singkat

- **Kalau ingin minimal permainan dan bukti kuat:** **Opsi 2 (Scan + batasan lokasi)** lebih aman: driver harus dekat untuk scan jemput, penumpang harus dekat dan di tujuan untuk scan selesai; validasi jarak dan tujuan sebaiknya **di backend** (Cloud Function) dengan lokasi yang dikirim saat scan.
- **Kalau ingin tanpa scan dan UX paling sederhana:** **Opsi 1 (Otomatis)** bisa dipakai dengan **konfirmasi "Penumpang dijemput"** (tombol, hanya aktif saat dekat) dan **selesai otomatis** ketika di tujuan lalu lokasi menjauh; tetap batasi tombol Batal saat dekat.
- **Kombinasi:** Bisa juga **hybrid:** jemput pakai **konfirmasi + jarak dekat** (tanpa scan), sampai tujuan pakai **scan + wajib dekat dan di tujuan** agar bukti sampai tujuan tetap kuat dan permainan driver berkurang.

---

## 4. Yang Perlu Dipersiapkan (Tanpa Detail Kode)

- **Lokasi real-time:** Mekanisme kirim/update lokasi driver dan penumpang (periodik atau on-demand) ke backend/Firestore, plus hak baca yang aman.
- **Backend validasi:** Cloud Function (atau Firestore rules + function) yang menerima lokasi saat aksi (scan/konfirmasi), menghitung jarak, cek "di tujuan", lalu mengizinkan atau menolak update status order.
- **Parameter:** Tentukan nilai R (radius "dekat" untuk jemput/turun dan untuk nonaktif tombol batal), T (radius "di tujuan"), dan durasi tunggu untuk opsi otomatis; bisa disimpan di Firestore (misalnya di `app_config/settings`) agar bisa diubah tanpa ganti kode.
- **UX:** Pesan error yang jelas ("Mendekatlah ke penumpang", "Anda belum di lokasi tujuan") dan, jika perlu, indikator "Anda sudah dekat / sudah di tujuan" di layar.

Dokumen ini sengaja **hanya saran dan alur**; implementasi detail (kode, struktur Firestore, API) bisa dibuat setelah Anda memilih opsi (otomatis penuh, scan + lokasi, atau hybrid) dan menyepakati nilai parameter (R, T, durasi, dll).
